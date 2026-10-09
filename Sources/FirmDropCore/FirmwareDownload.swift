import Foundation
import Synchronization

public enum DownloadPhase: Sendable {
    case connecting
    case verifyingPartial
    case downloading
    case decrypting
}

public struct DownloadProgress: Sendable {
    public var phase: DownloadPhase
    public var completed: Int64
    public var total: Int64
}

public struct FirmwareDownload: Sendable {
    public var model: String
    public var region: String
    public var version: String
    public var directory: URL
    public var keepEncrypted = false

    static let chunkSize = 8 << 20
    static let maxRetries = 5

    public init(model: String, region: String, version: String, directory: URL) {
        self.model = model
        self.region = region
        self.version = version
        self.directory = directory
    }

    public func run(
        authenticator: Authenticator,
        onInfo: @Sendable (BinaryInfo) -> Void = { _ in },
        onProgress: @Sendable (DownloadProgress) -> Void = { _ in },
        onRetry: @Sendable (Int, Error) -> Void = { _, _ in }
    ) async throws -> URL {
        onProgress(DownloadProgress(phase: .connecting, completed: 0, total: 0))
        let client = try await FUSClient(authenticator: authenticator)
        let info = try await client.binaryInform(model: model, region: region, version: version)
        onInfo(info)

        let fm = FileManager.default
        let (encURL, decURL) = try Self.localURLs(for: info, in: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if info.key != nil, fm.fileExists(atPath: decURL.path) { return decURL }

        try await download(info, to: encURL, client: client, onProgress: onProgress, onRetry: onRetry)

        guard let key = info.key else { return encURL }
        try await Self.decrypt(encURL, to: decURL, key: key, onProgress: onProgress)
        if !keepEncrypted { try? fm.removeItem(at: encURL) }
        return decURL
    }

    public static func localURLs(for info: BinaryInfo, in directory: URL) throws -> (encrypted: URL, decrypted: URL) {
        for name in [info.localName, info.decryptedName] where !Identifiers.isPlainFileName(name) {
            throw FUSError.unsafeFileName(name)
        }
        return (directory.appending(path: info.localName), directory.appending(path: info.decryptedName))
    }

    private func download(
        _ info: BinaryInfo,
        to url: URL,
        client: FUSClient,
        onProgress: @Sendable (DownloadProgress) -> Void,
        onRetry: @Sendable (Int, Error) -> Void
    ) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        var offset = fm.fileSize(at: url) ?? 0
        guard offset <= info.size else { throw FUSError.fileTooLarge }

        var crc = CRC32()
        if offset > 0 {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            var read: Int64 = 0
            var throttle = ProgressThrottle()
            while let chunk = try reader.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                try Task.checkCancellation()
                crc.update(chunk)
                read += Int64(chunk.count)
                if throttle.shouldReport() {
                    onProgress(DownloadProgress(phase: .verifyingPartial, completed: read, total: offset))
                }
                await Task.yield()
            }
        }

        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        try writer.seekToEnd()

        if offset < info.size { try await client.binaryInit(info) }
        onProgress(DownloadProgress(phase: .downloading, completed: offset, total: info.size))

        var attempt = 0
        while offset < info.size {
            do {
                let (session, request) = try await client.downloadRequest(for: info, offset: offset)
                var buffer = Data()
                buffer.reserveCapacity(Self.chunkSize)
                var throttle = ProgressThrottle()

                func flush() throws {
                    guard !buffer.isEmpty else { return }
                    try writer.write(contentsOf: buffer)
                    crc.update(buffer)
                    offset += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                }

                do {
                    let (chunks, consumed) = Self.stream(session: session, request: request, expectPartial: offset > 0)
                    for try await data in chunks {
                        consumed(data.count)
                        buffer.append(data)
                        if buffer.count >= Self.chunkSize { try flush() }
                        if throttle.shouldReport() {
                            onProgress(DownloadProgress(phase: .downloading, completed: offset + Int64(buffer.count), total: info.size))
                        }
                    }
                    try flush()
                } catch {
                    try? flush()
                    throw error
                }
                guard offset >= info.size else {
                    throw FUSError.badResponse(String(localized: "conexão encerrada antes do fim do arquivo"))
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if error as? FUSError == .rangeNotSupported { throw error }
                attempt += 1
                guard attempt <= Self.maxRetries else { throw error }
                onRetry(attempt, error)
                try await Task.sleep(for: .seconds(min(1 << attempt, 30)))
                do {
                    try await client.reset()
                    _ = try await client.binaryInform(model: info.model, region: info.region, version: info.version)
                    try await client.binaryInit(info)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    onRetry(attempt, error)
                }
            }
        }

        onProgress(DownloadProgress(phase: .downloading, completed: offset, total: info.size))
        guard offset == info.size else { throw FUSError.sizeMismatch(expected: info.size, got: offset) }
        if let expected = info.crc32, crc.value != expected {
            throw FUSError.crcMismatch(expected: expected, got: crc.value)
        }
    }

    static func stream(
        session: URLSession, request: URLRequest, expectPartial: Bool
    ) -> (chunks: AsyncThrowingStream<Data, Error>, consumed: @Sendable (Int) -> Void) {
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let task = session.dataTask(with: request)
        let delegate = StreamDelegate(continuation: continuation, expectPartial: expectPartial)
        delegate.task = task
        task.delegate = delegate
        continuation.onTermination = { _ in task.cancel() }
        task.resume()
        return (chunks, delegate.consumed)
    }

    static func decrypt(_ src: URL, to dst: URL, key: Data, onProgress: @Sendable (DownloadProgress) -> Void) async throws {
        let fm = FileManager.default
        let size = fm.fileSize(at: src) ?? 0
        guard size % 16 == 0 else { throw FUSError.badResponse(String(localized: "tamanho do arquivo não é múltiplo de 16")) }

        let reader = try FileHandle(forReadingFrom: src)
        defer { try? reader.close() }
        guard try FirmwareCrypto.keyMatches(key, firstBlock: reader.read(upToCount: 16) ?? Data()) else {
            throw FUSError.wrongKey
        }
        try reader.seek(toOffset: 0)

        let tmp = dst.appendingPathExtension("part")
        fm.createFile(atPath: tmp.path, contents: nil)
        let writer = try FileHandle(forWritingTo: tmp)
        var writerOpen = true
        defer { if writerOpen { try? writer.close() } }

        let decryptor = try AESECBDecryptor(key: key)
        var remaining = size
        var throttle = ProgressThrottle()
        while remaining > 0 {
            try Task.checkCancellation()
            guard var chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty else {
                throw FUSError.sizeMismatch(expected: size, got: size - remaining)
            }
            remaining -= Int64(chunk.count)
            try decryptor.decrypt(&chunk)
            try writer.write(contentsOf: remaining == 0 ? FirmwareCrypto.unpad(chunk) : chunk)
            if throttle.shouldReport(force: remaining == 0) {
                onProgress(DownloadProgress(phase: .decrypting, completed: size - remaining, total: size))
            }
            await Task.yield()
        }
        try writer.close()
        writerOpen = false
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.moveItem(at: tmp, to: dst)
    }
}

private struct ProgressThrottle {
    static let interval: TimeInterval = 0.2
    private var last = Date.distantPast

    mutating func shouldReport(force: Bool = false) -> Bool {
        let now = Date()
        guard force || now.timeIntervalSince(last) >= Self.interval else { return false }
        last = now
        return true
    }
}

struct Backpressure: Sendable {
    let high: Int
    let low: Int
    private(set) var pending = 0
    private(set) var paused = false

    init(high: Int = 64 << 20, low: Int = 16 << 20) {
        self.high = high
        self.low = low
    }

    mutating func received(_ count: Int) -> Bool {
        pending += count
        guard !paused, pending >= high else { return false }
        paused = true
        return true
    }

    mutating func consumed(_ count: Int) -> Bool {
        pending -= count
        guard paused, pending <= low else { return false }
        paused = false
        return true
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    let expectPartial: Bool
    weak var task: URLSessionDataTask?
    private let backpressure = Mutex(Backpressure())

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation, expectPartial: Bool) {
        self.continuation = continuation
        self.expectPartial = expectPartial
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            continuation.finish(throwing: FUSError.http(endpoint: "download", status: status))
            completionHandler(.cancel)
        } else if expectPartial && status != 206 {
            continuation.finish(throwing: FUSError.rangeNotSupported)
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        backpressure.withLock { if $0.received(data.count) { dataTask.suspend() } }
        continuation.yield(data)
    }

    func consumed(_ count: Int) {
        backpressure.withLock { if $0.consumed(count) { task?.resume() } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.finish(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            continuation.finish()
        }
    }
}
