import Foundation
import Testing
@testable import FirmDropCore

@Suite struct UntrustedXMLTests {
    private func withSecretFile(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "firmdrop-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = dir.appending(path: "secret.txt")
        try Data("CONTEUDO-SECRETO".utf8).write(to: secret)
        try body(secret)
    }

    @Test func doesNotResolveExternalEntities() throws {
        try withSecretFile { secret in
            let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE r [<!ENTITY xxe SYSTEM "\(secret.absoluteString)">]>
            <r><v>&xxe;</v></r>
            """
            let doc = try XMLDocument.untrusted(Data(xml.utf8))
            let value = try doc.nodes(forXPath: "/r/v").first?.stringValue ?? ""
            #expect(!value.contains("SECRETO"))
        }
    }

    @Test func versionXMLDoesNotLeakLocalFiles() throws {
        try withSecretFile { secret in
            let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE versioninfo [<!ENTITY xxe SYSTEM "\(secret.absoluteString)">]>
            <versioninfo><firmware><version><latest>&xxe;/B/C</latest></version></firmware></versioninfo>
            """
            let versions = try? Versions.parse(Data(xml.utf8), model: "SM-X", region: "ZTO")
            #expect(versions?.latest?.contains("SECRETO") != true)
        }
    }
}
