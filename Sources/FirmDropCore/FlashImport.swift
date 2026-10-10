import Foundation

public enum FlashImport {
    public static func folder(_ url: URL) throws -> [FlashSlot: FlashPackage] {
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return try FlashPackage.select(files)
    }

    static func zipMembers(_ lines: [String]) throws -> [String] {
        let members = lines.filter { FlashSlot.identify(($0 as NSString).lastPathComponent) != nil }
        guard !members.isEmpty, members.count <= 5 else { throw FlashError.invalidZIP }
        var names = Set<String>()
        for member in members {
            let components = member.split(separator: "/", omittingEmptySubsequences: false)
            guard components.allSatisfy({ Identifiers.isPlainFileName(String($0)) }),
                  names.insert((member as NSString).lastPathComponent).inserted else { throw FlashError.invalidZIP }
        }
        return members
    }

    static func declaredSizes(_ lines: [String], of members: [String]) throws -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for line in lines {
            let fields = line.split(separator: " ", maxSplits: 3)
            guard fields.count == 4, let size = Int64(fields[0]), size >= 0 else { continue }
            let name = String(fields[3].drop(while: { $0 == " " }))
            sizes[name] = max(sizes[name] ?? 0, size)
        }
        return try Dictionary(uniqueKeysWithValues: members.map { member in
            guard let size = sizes[member] else { throw FlashError.invalidZIP }
            return (member, size)
        })
    }

    public static func extractZIP(_ url: URL, into directory: URL,
                                  onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> [FlashSlot: FlashPackage] {
        guard url.isFileURL, url.pathExtension.lowercased() == "zip" else { throw FlashError.invalidZIP }
        let unzip = URL(filePath: "/usr/bin/unzip")
        let members = try zipMembers(try await CommandRunner.run(unzip, arguments: ["-Z1", url.path], timeout: 30).completeLines())
        let details = try await CommandRunner.run(unzip, arguments: ["-l", url.path], timeout: 30).completeLines()
        let sizes = try declaredSizes(details, of: members)
        let needed = sizes.values.reduce(0, +)
        let parent = directory.deletingLastPathComponent()
        if let available = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, needed > available {
            throw FlashError.notEnoughSpace(needed)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            for member in members {
                let name = (member as NSString).lastPathComponent
                onLine(String(localized: "Extraindo \(name)…"))
                let output = directory.appending(path: name)
                let result = try await CommandRunner.run(unzip, arguments: ["-p", url.path, member], outputFile: output, onLine: onLine)
                try result.requireSuccess()
                guard FileManager.default.fileSize(at: output) == sizes[member] else { throw FlashError.invalidZIP }
            }
            let packages = try folder(directory)
            guard packages.count == FlashSlot.allCases.count else { throw FlashError.invalidZIP }
            return packages
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
