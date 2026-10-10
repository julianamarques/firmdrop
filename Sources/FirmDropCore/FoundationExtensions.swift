import Foundation

extension Sequence<UInt8> {
    public var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension FileManager {
    public func fileSize(at url: URL) -> Int64? {
        (try? attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    func firstExecutable(in candidates: [URL]) -> URL? {
        candidates.first {
            (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && isExecutableFile(atPath: $0.path)
        }
    }
}

extension Bundle {
    static func helperExecutable(_ name: String, development path: String) -> URL? {
        var candidates = [main.bundleURL.appending(path: "Contents/MacOS/\(name)")]
        if main.bundleURL.pathExtension != "app" {
            candidates.append(URL(filePath: FileManager.default.currentDirectoryPath).appending(path: path))
        }
        return FileManager.default.firstExecutable(in: candidates)
    }
}
