import Foundation

public struct FlashDevice: Equatable, Sendable, Identifiable {
    public let target: String
    public let connection: UInt64
    public let productID: UInt16
    public let isDownloadMode: Bool
    public var id: String { "\(target):\(connection)" }

    public init(target: String, connection: UInt64, productID: UInt16, isDownloadMode: Bool) {
        self.target = target
        self.connection = connection
        self.productID = productID
        self.isDownloadMode = isDownloadMode
    }
}

public enum FlashEvent: Equatable, Sendable {
    case device(FlashDevice), probe(Int), stage(String), progress(completed: UInt64, total: UInt64), done

    public init?(line: String) {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts[0] == "@firmdrop" else { return nil }
        switch parts[1] {
        case "DEVICE":
            guard parts.count == 6, parts[2].wholeMatch(of: /0x[0-9a-f]{8}/) != nil,
                  let connection = UInt64(parts[3]), connection > 0, let product = UInt16(parts[4]),
                  ["download", "other"].contains(parts[5]) else { return nil }
            self = .device(FlashDevice(target: parts[2], connection: connection, productID: product, isDownloadMode: parts[5] == "download"))
        case "PROBE":
            guard parts.count == 3, let version = Int(parts[2]), version > 0 else { return nil }
            self = .probe(version)
        case "STAGE":
            guard parts.count == 3 else { return nil }
            self = .stage(parts[2])
        case "PROGRESS":
            guard parts.count == 4, let done = UInt64(parts[2]), let total = UInt64(parts[3]), total > 0, done <= total else { return nil }
            self = .progress(completed: done, total: total)
        case "DONE":
            guard parts.count == 2 else { return nil }
            self = .done
        default: return nil
        }
    }
}

public struct FlashEngine: Sendable {
    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    public static func bundled() throws -> FlashEngine {
        var candidates = [Bundle.main.bundleURL.appending(path: "Contents/MacOS/firmdrop-flash")]
        if Bundle.main.bundleURL.pathExtension != "app" {
            candidates.append(URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "build/flash-engine/firmdrop-flash"))
        }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw FlashError.engineMissing
        }
        return FlashEngine(executable: executable)
    }

    public func devices() async throws -> [FlashDevice] {
        let result = try await CommandRunner.run(executable, arguments: ["--list"], timeout: 15)
        try result.requireSuccess()
        guard !result.truncated else { throw FlashError.outputTooLarge }
        return result.lines.compactMap { line in
            if case let .device(device) = FlashEvent(line: line) { device } else { nil }
        }
    }

    public func probe(_ device: FlashDevice, resume: Bool = false,
                      onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Int {
        guard device.isDownloadMode else { throw FlashError.notInDownloadMode }
        let arguments = ["--probe", "--target", device.target, "--connection", String(device.connection)]
        let result = try await CommandRunner.run(executable, arguments: arguments + (resume ? ["--resume"] : []),
                                                 timeout: 30, onLine: onLine)
        try result.requireSuccess()
        guard let version = result.lines.compactMap({ line -> Int? in
            if case let .probe(version) = FlashEvent(line: line) { version } else { nil }
        }).last else { throw FlashError.probeRequired }
        return version
    }

    public func flash(_ plan: FlashPlan, resume: Bool = false, onLine: @escaping @Sendable (String) -> Void) async throws {
        guard try await devices().contains(plan.device) else { throw FlashError.deviceChanged }
        let arguments = try plan.arguments(resume: resume)
        let result = try await CommandRunner.run(executable, arguments: arguments, onLine: onLine)
        try result.requireSuccess()
        guard result.lines.contains("@firmdrop\tDONE") else { throw FlashError.incompleteFlash }
    }
}
