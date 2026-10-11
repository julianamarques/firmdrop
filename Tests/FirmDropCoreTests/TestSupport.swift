import Foundation

func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "firmdrop-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try await body(dir)
}

/// Writes an executable shell script that runs from its own directory.
func makeScript(_ name: String, body: String, in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try ("#!/bin/sh\ncd -- \"$(dirname -- \"$0\")\"\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}

/// Writes a placeholder firmware package; only its name and size matter to the app.
@discardableResult
func writePackage(_ name: String, in directory: URL) throws -> URL {
    let url = directory.appending(path: name)
    try Data(repeating: 0, count: 512).write(to: url)
    return url
}

func fileExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appending(path: name).path)
}
