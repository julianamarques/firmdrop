import Foundation

func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "firmdrop-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try await body(dir)
}
