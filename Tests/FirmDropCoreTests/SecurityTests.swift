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

@Suite struct IdentifierTests {
    @Test(arguments: ["SM-A556E", "SM-S928B", "GT-I9300", "SM-R860"])
    func acceptsModels(model: String) {
        #expect(Identifiers.isValidModel(model))
    }

    @Test(arguments: ["", "SM A556E", "SM-A556E/DS", "../SM-X", "SM-X?x=1", "-SM", "sm-a556e"])
    func rejectsModels(model: String) {
        #expect(!Identifiers.isValidModel(model))
    }

    @Test func validatesRegions() {
        #expect(Identifiers.isValidRegion("ZTO"))
        #expect(Identifiers.isValidRegion("XAR"))
        #expect(!Identifiers.isValidRegion("../ZTO"))
        #expect(!Identifiers.isValidRegion("Z"))
        #expect(!Identifiers.isValidRegion("ZT O"))
    }

    @Test func validatesVersions() {
        #expect(Identifiers.isValidVersion("A556EXXSIDZI3/A556EOWOIDZI3/A556EXXSIDZI3/A556EXXSIDZI3"))
        #expect(!Identifiers.isValidVersion("A556EXXSIDZI3/../x"))
        #expect(!Identifiers.isValidVersion("A556EXXSIDZI3//x"))
        #expect(!Identifiers.isValidVersion("A556E XXSIDZI3"))
    }

    @Test(arguments: ["SM-A556E_4_20260915000521_613i6lvoq5_fac.zip.enc4", "fw.zip"])
    func acceptsPlainFileNames(name: String) {
        #expect(Identifiers.isPlainFileName(name))
    }

    @Test(arguments: ["../fw.zip.enc4", "a/b.zip", "..", ".hidden.zip", "", "fw.zip\u{0}"])
    func rejectsUnsafeFileNames(name: String) {
        #expect(!Identifiers.isPlainFileName(name))
    }

    @Test func fetchRejectsInvalidInputBeforeAnyRequest() async {
        await #expect(throws: FUSError.invalidModel("../SM-X")) {
            try await Versions.fetch(model: "../sm-x", region: "ZTO")
        }
        await #expect(throws: FUSError.invalidRegion("../ZTO")) {
            try await Versions.fetch(model: "SM-A556E", region: "../zto")
        }
    }

    @Test func versionXMLDropsMalformedVersions() throws {
        let xml = """
        <versioninfo><firmware><version><latest o="16">A1/B1/A1</latest><upgrade>
        <value>A0/B0/A0</value><value>A0/../x</value><value>A 0/B0/A0</value>
        </upgrade></version></firmware></versioninfo>
        """
        let versions = try Versions.parse(Data(xml.utf8), model: "SM-X", region: "ZTO")
        #expect(versions.previous == ["A0/B0/A0/A0"])
    }
}

@Suite struct LocalFileTests {
    private func info(filename: String, version: String = "A1/B1/A1/A1", region: String = "ZTO") -> BinaryInfo {
        BinaryInfo(model: "SM-X", region: region, version: version, filename: filename,
                   path: "/p/", size: 1, crc32: nil, key: Data(count: 16))
    }

    @Test func keepsFilesInsideTheDestination() throws {
        let dir = URL(filePath: "/tmp/destino", directoryHint: .isDirectory)
        let urls = try FirmwareDownload.localURLs(for: info(filename: "fw_fac.zip.enc4"), in: dir)
        #expect(urls.encrypted.path == "/tmp/destino/fw_fac_A1_B1_ZTO.zip.enc4")
        #expect(urls.decrypted.path == "/tmp/destino/fw_fac_A1_B1_ZTO.zip")
    }

    @Test(arguments: [("../escapou.zip.enc4", "ZTO"), ("fw.zip.enc4", "../../x"), ("fw.zip.enc4", "Z/x")])
    func refusesNamesThatEscapeTheDestination(filename: String, region: String) {
        #expect(throws: FUSError.self) {
            try FirmwareDownload.localURLs(for: info(filename: filename, region: region),
                                           in: URL(filePath: "/tmp/destino", directoryHint: .isDirectory))
        }
    }

    @Test func versionSeparatorsNeverLeaveTheDestination() throws {
        let dir = URL(filePath: "/tmp/destino", directoryHint: .isDirectory)
        let urls = try FirmwareDownload.localURLs(for: info(filename: "fw.zip.enc4", version: "A1/../../x/A1"), in: dir)
        #expect(urls.encrypted.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        #expect(urls.decrypted.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
    }
}

@Suite struct UpdateLinkTests {
    private func release(asset: String?, html: String) throws -> AppRelease {
        let assets = asset.map { #"[{"name": "FirmDrop.dmg", "browser_download_url": "\#($0)"}]"# } ?? "[]"
        let json = #"{"tag_name": "v9.0.0", "html_url": "\#(html)", "body": null, "draft": false, "prerelease": false, "assets": \#(assets)}"#
        return try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
    }

    @Test func opensTheProjectDownload() throws {
        let url = "https://github.com/julianamarques/firmdrop/releases/download/v9.0.0/FirmDrop.dmg"
        #expect(try release(asset: url, html: "https://github.com/julianamarques/firmdrop/releases/tag/v9.0.0").downloadURL.absoluteString == url)
    }

    @Test(arguments: [
        "file:///Applications/Calculator.app",
        "http://github.com/julianamarques/firmdrop/releases/download/v9.0.0/FirmDrop.dmg",
        "https://evil.example/julianamarques/firmdrop/releases/download/v9.0.0/FirmDrop.dmg",
        "https://github.com/outra-pessoa/firmdrop/releases/download/v9.0.0/FirmDrop.dmg",
        "https://github.com.evil.example/julianamarques/firmdrop/releases/FirmDrop.dmg",
        "https://user@github.com/julianamarques/firmdrop/releases/FirmDrop.dmg",
        "x-apple.systempreferences:com.apple.preference.security",
    ])
    func neverOpensUntrustedLinks(link: String) throws {
        #expect(try release(asset: link, html: link).downloadURL == UpdateChecker.releasesPage)
    }

    @Test func fallsBackToTheReleasePageWhenTheAssetIsUntrusted() throws {
        let page = "https://github.com/julianamarques/firmdrop/releases/tag/v9.0.0"
        #expect(try release(asset: "file:///tmp/x.dmg", html: page).downloadURL.absoluteString == page)
    }
}
