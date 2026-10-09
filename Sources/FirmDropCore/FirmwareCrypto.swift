import CommonCrypto
import CryptoKit
import Foundation
import zlib

public enum FirmwareCrypto {
    public static func logicCheck(_ input: String, nonce: String) -> String {
        let chars = Array(input.utf8)
        guard chars.count >= 16 else { return "" }
        return String(decoding: nonce.utf8.map { chars[Int($0 & 0xF)] }, as: UTF8.self)
    }

    public static func v2Key(version: String, model: String, region: String) -> Data {
        Data(Insecure.MD5.hash(data: Data("\(region):\(model):\(version)".utf8)))
    }

    public static func v4Key(version: String, logicValue: String) -> Data {
        Data(Insecure.MD5.hash(data: Data(logicCheck(version, nonce: logicValue).utf8)))
    }

    public static func unpad(_ data: Data) -> Data {
        guard let n = data.last, (1...16).contains(n), data.count >= Int(n),
              data.suffix(Int(n)).allSatisfy({ $0 == n }) else { return data }
        return data.dropLast(Int(n))
    }

    public static func keyMatches(_ key: Data, firstBlock: Data) throws -> Bool {
        guard firstBlock.count >= 16 else { return false }
        let decryptor = try AESECBDecryptor(key: key)
        return try decryptor.update(firstBlock.prefix(16)).starts(with: [0x50, 0x4B, 0x03, 0x04])
    }
}

public final class AESECBDecryptor {
    private var cryptor: CCCryptorRef?

    public init(key: Data) throws {
        guard key.count == kCCKeySizeAES128 else { throw FUSError.missingKey }
        let status = key.withUnsafeBytes { keyPtr in
            CCCryptorCreate(
                CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                keyPtr.baseAddress, key.count, nil, &cryptor
            )
        }
        guard status == kCCSuccess else { throw FUSError.badResponse("falha ao iniciar AES (\(status))") }
    }

    deinit { CCCryptorRelease(cryptor) }

    public func update(_ data: Data) throws -> Data {
        var out = Data(count: data.count)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                CCCryptorUpdate(cryptor, inPtr.baseAddress, data.count, outPtr.baseAddress, data.count, &moved)
            }
        }
        guard status == kCCSuccess else { throw FUSError.badResponse("falha ao decifrar (\(status))") }
        out.count = moved
        return out
    }
}

public struct CRC32: Sendable {
    public private(set) var value: UInt32 = 0

    public init() {}

    public mutating func update(_ data: Data) {
        value = data.withUnsafeBytes { ptr in
            UInt32(crc32(uLong(value), ptr.bindMemory(to: Bytef.self).baseAddress, uInt(ptr.count)))
        }
    }
}
