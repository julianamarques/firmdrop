import CommonCrypto
import Foundation
import Testing
@testable import FirmDropCore

private func aesECBEncrypt(_ data: Data, key: Data) -> Data {
    var out = Data(count: data.count)
    var moved = 0
    _ = out.withUnsafeMutableBytes { o in
        data.withUnsafeBytes { i in
            key.withUnsafeBytes { k in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                        k.baseAddress, key.count, nil, i.baseAddress, data.count, o.baseAddress, data.count, &moved)
            }
        }
    }
    return out
}

private func pkcs7(_ data: Data) -> Data {
    let n = 16 - data.count % 16
    return data + Data(repeating: UInt8(n), count: n)
}

@Suite struct VersionTests {
    @Test func normalize() throws {
        #expect(try Versions.normalize("A/B/C") == "A/B/C/A")
        #expect(try Versions.normalize("A/B/") == "A/B/A/A")
        #expect(try Versions.normalize("A/B/C/D") == "A/B/C/D")
        #expect(throws: FUSError.self) { try Versions.normalize("A/B") }
    }

    @Test func buildDate() {
        #expect(Versions.buildDate("S928BXXS6DZI1/S928BOWO6DZI1/S928BXXS6DZI1") == DateComponents(year: 2026, month: 9))
        #expect(Versions.buildDate("S928BXXS1AXBL/S928BOWO1AXBL/S928BXXS1AXBL") == DateComponents(year: 2024, month: 2))
        #expect(Versions.buildDate("XXXXXXXXXXAA1") == DateComponents(year: 2027, month: 1))
        #expect(Versions.buildDate("S928B123") == nil)
    }

    @Test func compact() {
        #expect(Versions.compact("X1/Y1/X1/X1") == "X1/Y1")
    }

    @Test func parseVersionXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <versioninfo><firmware><model>SM-A556E</model><cc>ZTO</cc><version>
        <latest o="16">A556EXXSIDZI3/A556EOWOIDZI3/A556EXXSIDZI3</latest>
        <upgrade>
        <value rcount='1' fwsize='1'>A556EXXU1AXC1/A556EOWO1AXC1/A556EXXU1AXC1</value>
        <value rcount='1' fwsize='1'>A556EXXS9CZB2/A556EOWO9CZB2/</value>
        <value rcount='1' fwsize='1'>A556EXXU5BYF3/A556EOWO5BYF3/A556EXXU5BYF3</value>
        </upgrade></version></firmware></versioninfo>
        """
        let v = try Versions.parse(Data(xml.utf8), model: "SM-A556E", region: "ZTO")
        #expect(v.latest == "A556EXXSIDZI3/A556EOWOIDZI3/A556EXXSIDZI3/A556EXXSIDZI3")
        #expect(v.android == "16")
        #expect(v.previous.map { $0.split(separator: "/")[0] } == ["A556EXXS9CZB2", "A556EXXU5BYF3", "A556EXXU1AXC1"])
        #expect(v.previous[0] == "A556EXXS9CZB2/A556EOWO9CZB2/A556EXXS9CZB2/A556EXXS9CZB2")
    }
}

@Suite struct CryptoTests {
    @Test func logicCheck() {
        #expect(FirmwareCrypto.logicCheck("0123456789abcdef", nonce: "abc") == "123")
        #expect(FirmwareCrypto.logicCheck("curto", nonce: "abc") == "")
    }

    @Test func v2Key() {
        let key = FirmwareCrypto.v2Key(version: "V", model: "SM-X", region: "ZTO")
        #expect(key.hexString == "a4c55baa5eb4c3a37686fa7952d3d093")
    }

    @Test func unpad() {
        #expect(FirmwareCrypto.unpad(Data([1, 2, 3, 3, 3])) == Data([1, 2]))
        #expect(FirmwareCrypto.unpad(Data([1, 2, 0])) == Data([1, 2, 0]))
        #expect(FirmwareCrypto.unpad(Data(repeating: 65, count: 32)) == Data(repeating: 65, count: 32))
    }

    @Test func decryptRoundtrip() throws {
        let key = Data((0..<16).map { UInt8($0) })
        let plain = Data([0x50, 0x4B, 0x03, 0x04] + (0..<5000).map { UInt8($0 % 251) })
        let enc = aesECBEncrypt(pkcs7(plain), key: key)
        #expect(try FirmwareCrypto.keyMatches(key, firstBlock: enc))
        #expect(try !FirmwareCrypto.keyMatches(Data(count: 16), firstBlock: enc))
        var dec = enc
        try AESECBDecryptor(key: key).decrypt(&dec)
        #expect(FirmwareCrypto.unpad(dec) == plain)
    }

    @Test func decryptFile() async throws {
        try await withTemporaryDirectory { dir in
            let key = Data((0..<16).map { UInt8(15 - $0) })
            let plain = Data([0x50, 0x4B, 0x03, 0x04] + (0..<(9 << 20)).map { UInt8($0 % 253) })
            let src = dir.appending(path: "fw.zip.enc4")
            let dst = dir.appending(path: "fw.zip")
            try aesECBEncrypt(pkcs7(plain), key: key).write(to: src)

            try await FirmwareDownload.decrypt(src, to: dst, key: key, onProgress: { _ in })
            #expect(try Data(contentsOf: dst) == plain)
            await #expect(throws: FUSError.wrongKey) {
                try await FirmwareDownload.decrypt(src, to: dst, key: Data(count: 16), onProgress: { _ in })
            }
        }
    }

    @Test func crc32() {
        var crc = CRC32()
        crc.update(Data("hel".utf8))
        crc.update(Data("lo".utf8))
        #expect(crc.value == 0x3610A686)
    }
}

@Suite struct BinaryInfoTests {
    @Test func names() {
        let info = BinaryInfo(
            model: "SM-A556E", region: "ZTO",
            version: "A556EXXSIDZI3/A556EOWOIDZI3/A556EXXSIDZI3/A556EXXSIDZI3",
            filename: "SM-A556E_4_20260915000521_613i6lvoq5_fac.zip.enc4",
            path: "/neofus/910/", size: 1, crc32: nil, key: Data(count: 16)
        )
        #expect(info.localName == "SM-A556E_4_20260915000521_613i6lvoq5_fac_A556EXXSIDZI3_A556EOWOIDZI3_ZTO.zip.enc4")
        #expect(info.decryptedName == "SM-A556E_4_20260915000521_613i6lvoq5_fac_A556EXXSIDZI3_A556EOWOIDZI3_ZTO.zip")
        #expect(info.remoteFile == "/neofus/910/SM-A556E_4_20260915000521_613i6lvoq5_fac.zip.enc4")
    }
}

@Suite struct AuthenticatorTests {
    @Test func knownVector() async throws {
        let auth: Authenticator
        do { auth = try Authenticator.load() } catch {
            print("auth_param.dat indisponível, pulando: \(error)")
            return
        }
        #expect(auth.sign(nonce: "m6t3lzskiwqjp1js") == "fa8ada2b59406e896961a59b85c6e41c")
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIRMDROP_LIVE"] == "1"))
struct LiveTests {
    @Test func informAndFirstBlock() async throws {
        let versions = try await Versions.fetch(model: "SM-A556E", region: "ZTO")
        let latest = try #require(versions.latest)
        let client = try await FUSClient(authenticator: try Authenticator.load())
        let info = try await client.binaryInform(model: "SM-A556E", region: "ZTO", version: latest)
        #expect(info.size > 1_000_000_000)
        #expect(info.displayName?.contains("A55") == true)
        try await client.binaryInit(info)

        let (session, request) = await client.downloadRequest(for: info, offset: 0)
        var partial = request
        partial.setValue("bytes=0-15", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: partial)
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(try FirmwareCrypto.keyMatches(try #require(info.key), firstBlock: data))
    }

    @Test func unknownModel() async {
        await #expect(throws: FUSError.modelNotFound(model: "SM-X9999", region: "ZTO")) {
            try await Versions.fetch(model: "SM-X9999", region: "ZTO")
        }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIRMDROP_LIVE"] == "1"))
struct LiveDownloadTests {
    final class Box: @unchecked Sendable { var info: BinaryInfo?; var maxCompleted: Int64 = 0; var phases = Set<DownloadPhase>() }

    func downloadUntil(_ bytes: Int64, job: FirmwareDownload, auth: Authenticator, box: Box) async {
        let task = Task {
            try await job.run(authenticator: auth, onInfo: { box.info = $0 }, onProgress: { p in
                box.phases.insert(p.phase)
                if p.phase == .downloading { box.maxCompleted = max(box.maxCompleted, p.completed) }
            })
        }
        while box.maxCompleted < bytes { try? await Task.sleep(for: .milliseconds(100)) }
        task.cancel()
        _ = await task.result
    }

    @Test(.timeLimit(.minutes(3))) func pauseAndResume() async throws {
        try await withTemporaryDirectory { dir in
            let auth = try Authenticator.load()
            let latest = try #require(try await Versions.fetch(model: "SM-R860", region: "ZTO").latest)
            let job = FirmwareDownload(model: "SM-R860", region: "ZTO", version: latest, directory: dir)

            let box = Box()
            await downloadUntil(20 << 20, job: job, auth: auth, box: box)
            let file = dir.appending(path: try #require(box.info).localName)
            let size1 = try #require(FileManager.default.fileSize(at: file))
            #expect(size1 >= 20 << 20)

            let box2 = Box()
            await downloadUntil(size1 + (10 << 20), job: job, auth: auth, box: box2)
            let size2 = try #require(FileManager.default.fileSize(at: file))
            #expect(box2.phases.contains(.verifyingPartial))
            #expect(size2 >= size1 + (10 << 20))

            let head = try FileHandle(forReadingFrom: file).read(upToCount: 16) ?? Data()
            #expect(try FirmwareCrypto.keyMatches(try #require(box.info?.key), firstBlock: head))
        }
    }
}
