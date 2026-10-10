import Foundation
import Synchronization

struct CommandResult: Sendable {
    let status: Int32
    let lines: [String]
    let truncated: Bool

    func requireSuccess(hiding hidden: (String) -> Bool = { _ in false }) throws {
        guard status == 0 else {
            throw FlashError.commandFailed(status, lines.filter { !hidden($0) }.suffix(12).joined(separator: "\n"))
        }
    }

    func completeLines(hiding hidden: (String) -> Bool = { _ in false }) throws -> [String] {
        try requireSuccess(hiding: hidden)
        guard !truncated else { throw FlashError.outputTooLarge }
        return lines
    }
}

struct CommandLines {
    private var pending = Data()

    mutating func append(_ bytes: Data, finished: Bool = false) throws -> [String] {
        pending.append(bytes)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            if end > pending.startIndex { lines.append(String(decoding: pending[..<end], as: UTF8.self)) }
            pending.removeSubrange(...end)
        }
        guard pending.count <= 64 * 1024 else { throw FlashError.outputTooLarge }
        if finished, !pending.isEmpty {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines
    }
}

enum CommandRunner {
    static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval? = nil, outputFile: URL? = nil, onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            let file: FileHandle?
            if let outputFile {
                guard FileManager.default.createFile(atPath: outputFile.path, contents: nil) else {
                    throw FlashError.invalidPackage(outputFile.lastPathComponent)
                }
                file = try FileHandle(forWritingTo: outputFile)
                process.standardOutput = file
            } else {
                file = nil
                process.standardOutput = pipe
            }
            process.standardError = pipe
            defer {
                try? file?.close()
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            try process.run()
            try pipe.fileHandleForWriting.close()
            let timedOut = Mutex(false)
            let timer = DispatchSource.makeTimerSource(queue: .global())
            if let timeout {
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        timedOut.withLock { $0 = true }
                        process.terminate()
                    }
                }
            }
            timer.resume()
            defer { timer.cancel() }
            var decoder = CommandLines()
            var lines: [String] = []
            var size = 0
            var truncated = false
            func receive(_ received: [String]) {
                for line in received {
                    onLine(line)
                    lines.append(line)
                    size += line.utf8.count
                }
                while size > 256 * 1024, !lines.isEmpty {
                    size -= lines.removeFirst().utf8.count
                    truncated = true
                }
            }
            do {
                while let chunk = try pipe.fileHandleForReading.read(upToCount: 16384), !chunk.isEmpty {
                    receive(try decoder.append(chunk))
                }
                receive(try decoder.append(Data(), finished: true))
            } catch {
                if process.isRunning { process.terminate() }
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 16384), !chunk.isEmpty {}
                process.waitUntilExit()
                throw error
            }
            process.waitUntilExit()
            if timedOut.withLock({ $0 }) { throw FlashError.timedOut }
            return CommandResult(status: process.terminationStatus, lines: lines, truncated: truncated)
        }.value
    }
}
