import Foundation

public enum DownloadPhase: String, Sendable, Codable {
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
    public var decrypt = true
    public var keepEncrypted = false
    public var maxRetries = 5

    static let chunkSize = 8 << 20
    static let progressInterval: TimeInterval = 0.2

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
        let decrypting = decrypt && info.isEncrypted

        if decrypting, fm.fileExists(atPath: decURL.path) { return decURL }

        try await download(info, to: encURL, client: client, onProgress: onProgress, onRetry: onRetry)

        guard decrypting, let key = info.key else { return encURL }
        try Self.decrypt(encURL, to: decURL, key: key, onProgress: onProgress)
        if !keepEncrypted { try? fm.removeItem(at: encURL) }
        return decURL
    }

    static func localURLs(for info: BinaryInfo, in directory: URL) throws -> (encrypted: URL, decrypted: URL) {
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
        var offset = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard offset <= info.size else { throw FUSError.fileTooLarge }

        var crc = CRC32()
        if offset > 0 {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            var read: Int64 = 0
            var lastReport = Date.distantPast
            while let chunk = try reader.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                try Task.checkCancellation()
                crc.update(chunk)
                read += Int64(chunk.count)
                if Date().timeIntervalSince(lastReport) >= Self.progressInterval {
                    onProgress(DownloadProgress(phase: .verifyingPartial, completed: read, total: offset))
                    lastReport = Date()
                }
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
                let (session, request) = await client.downloadRequest(for: info, offset: offset)
                var buffer = Data()
                buffer.reserveCapacity(Self.chunkSize)
                var lastReport = Date.distantPast

                func flush() throws {
                    guard !buffer.isEmpty else { return }
                    try writer.write(contentsOf: buffer)
                    crc.update(buffer)
                    offset += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                }

                do {
                    for try await data in Self.stream(session: session, request: request, expectPartial: offset > 0) {
                        buffer.append(data)
                        if buffer.count >= Self.chunkSize { try flush() }
                        if Date().timeIntervalSince(lastReport) >= Self.progressInterval {
                            onProgress(DownloadProgress(phase: .downloading, completed: offset + Int64(buffer.count), total: info.size))
                            lastReport = Date()
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
                if let fus = error as? FUSError, case .rangeNotSupported = fus { throw fus }
                attempt += 1
                guard attempt <= maxRetries else { throw error }
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

    static func stream(session: URLSession, request: URLRequest, expectPartial: Bool) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let delegate = StreamDelegate(continuation: continuation, expectPartial: expectPartial)
            let task = session.dataTask(with: request)
            task.delegate = delegate
            continuation.onTermination = { _ in task.cancel() }
            task.resume()
        }
    }

    static func decrypt(_ src: URL, to dst: URL, key: Data, onProgress: @Sendable (DownloadProgress) -> Void) throws {
        let fm = FileManager.default
        let size = (try fm.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value ?? 0
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
        var lastReport = Date.distantPast
        while remaining > 0 {
            try Task.checkCancellation()
            guard let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty else {
                throw FUSError.sizeMismatch(expected: size, got: size - remaining)
            }
            remaining -= Int64(chunk.count)
            let plain = try decryptor.update(chunk)
            try writer.write(contentsOf: remaining == 0 ? FirmwareCrypto.unpad(plain) : plain)
            if Date().timeIntervalSince(lastReport) >= progressInterval || remaining == 0 {
                onProgress(DownloadProgress(phase: .decrypting, completed: size - remaining, total: size))
                lastReport = Date()
            }
        }
        try writer.close()
        writerOpen = false
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.moveItem(at: tmp, to: dst)
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<Data, Error>.Continuation
    let expectPartial: Bool

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
        continuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.finish(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        } else {
            continuation.finish()
        }
    }
}
