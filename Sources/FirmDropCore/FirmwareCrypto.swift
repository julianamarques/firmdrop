import CommonCrypto
import CryptoKit
import Foundation
import zlib

/// Criptografia dos arquivos de firmware (a assinatura dos pedidos fica em `Authenticator`).
///
/// Os arquivos vêm cifrados com AES-128-ECB:
/// - `.enc2` → chave = MD5("REGIÃO:MODELO:VERSÃO")
/// - `.enc4` → chave = MD5(logicCheck(versão, LOGIC_VALUE_FACTORY))
public enum FirmwareCrypto {
    /// Seleciona caracteres de `input` usando os 4 bits baixos de cada caractere de `nonce`.
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

    /// Remove padding PKCS#7 se houver; caso contrário devolve os dados intactos
    /// (o ZIP tolera bytes extras no final, e nem todo arquivo vem com padding).
    public static func unpad(_ data: Data) -> Data {
        guard let n = data.last, (1...16).contains(n), data.count >= Int(n),
              data.suffix(Int(n)).allSatisfy({ $0 == n }) else { return data }
        return data.dropLast(Int(n))
    }

    /// Confere a chave decifrando só o primeiro bloco: o resultado deve começar com a assinatura do ZIP.
    public static func keyMatches(_ key: Data, firstBlock: Data) throws -> Bool {
        guard firstBlock.count >= 16 else { return false }
        let decryptor = try AESECBDecryptor(key: key)
        return try decryptor.update(firstBlock.prefix(16)).starts(with: [0x50, 0x4B, 0x03, 0x04])
    }
}

/// AES-128-ECB sem padding, em streaming (CommonCrypto, acelerado por hardware).
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

    /// Decifra `data` (o tamanho precisa ser múltiplo de 16).
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

/// CRC32 incremental (zlib do sistema).
public struct CRC32: Sendable {
    public private(set) var value: UInt32 = 0

    public init() {}

    public mutating func update(_ data: Data) {
        value = data.withUnsafeBytes { ptr in
            UInt32(crc32(uLong(value), ptr.bindMemory(to: Bytef.self).baseAddress, uInt(ptr.count)))
        }
    }
}
