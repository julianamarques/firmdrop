import Foundation

extension Sequence<UInt8> {
    public var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension FileManager {
    public func fileSize(at url: URL) -> Int64? {
        (try? attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
