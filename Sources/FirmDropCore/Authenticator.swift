import CryptoKit
import Foundation

public struct Authenticator: Sendable {
    public static let paramsSHA256 = "6f969176bbe3eca193b51509313ca45d32366cf1825a907f04fde5b64d3f35b4"

    private static let headerSize = 56
    private static let shift = [0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11]

    private let tables: [UInt8]
    private let block1Size: Int
    private let block2Size: Int
    private let block3Size: Int

    public init(params: Data) throws {
        guard Self.sha256(params) == Self.paramsSHA256 else {
            throw FUSError.authParams(String(localized: "auth_param.dat com SHA-256 inesperado"))
        }
        let bytes = [UInt8](params)
        func int32(at index: Int) -> Int {
            let o = index * 4
            return Int(Int32(bitPattern: UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8
                | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24))
        }
        block1Size = int32(at: 3)
        block2Size = int32(at: 5)
        block3Size = int32(at: 11)
        tables = Array(bytes[Self.headerSize...])
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func transform(_ block: [UInt8]) -> [UInt8] {
        precondition(block.count == 16, "o bloco de autenticação precisa ter 16 bytes")
        let shift = Self.shift
        return tables.withUnsafeBufferPointer { t in
            var state = [Int](repeating: 0, count: 320)
            for i in 0..<16 { state[i] = Int(block[i]) }
            var v15 = [Int](repeating: 0, count: 64)
            let baseFinal = block1Size
            let selBase = baseFinal + block2Size
            let tblBaseOffset = baseFinal + block2Size + block3Size

            for j in 0..<9 {
                let src = j * 32, next = (j + 1) * 32, mid = src + 16
                for idx in 0..<16 { state[mid + idx] = state[src + shift[idx]] }

                for i in 0..<4 {
                    let i4 = i << 2, i16 = i << 4
                    let blkRow = j * 16 + i4
                    let base262 = tblBaseOffset + 6144 * (i + (j << 2))

                    for k in 0..<4 {
                        let blkId = blkRow + k
                        let src16 = (blkId << 12) + (state[mid + i4 + k] << 4)
                        let selector = selBase + (blkId << 5)
                        let out = i16 + (k << 2)
                        for outIdx in 0..<4 {
                            var acc = 0
                            for bit in 0..<8 {
                                let sel = Int(t[selector + (outIdx << 3) + bit])
                                let srcIdx = (sel >> 3) & 0x1F
                                let srcByte = srcIdx < 16 ? Int(t[src16 + srcIdx]) : 0
                                acc |= ((srcByte >> (7 - (sel & 7))) & 1) << (7 - bit)
                            }
                            v15[out + outIdx] = acc
                        }
                    }

                    for k2 in 0..<4 {
                        let a1 = v15[i16 + k2], a2 = v15[i16 + k2 + 4]
                        let a3 = v15[i16 + k2 + 8], a4 = v15[i16 + k2 + 12]
                        let tb = base262 + 1536 * k2
                        func tbl(_ i: Int) -> Int { Int(t[tb + i]) }
                        let v6 = ((tbl((a1 & 0xF0) | (a2 >> 4)) << 4) ^ tbl(256 + (((a1 & 0x0F) << 4) | (a2 & 0x0F)))) & 0xFF
                        let v7 = ((tbl(512 + ((a3 & 0xF0) | (a4 >> 4))) << 4) ^ tbl(768 + (((a3 & 0x0F) << 4) | (a4 & 0x0F)))) & 0xFF
                        state[next + i4 + k2] =
                            ((tbl(1024 + ((v6 & 0xF0) | (v7 >> 4))) << 4) ^ tbl(1280 + (((v6 & 0x0F) << 4) | (v7 & 0x0F)))) & 0xFF
                    }
                }
            }
            return (0..<16).map { idx in t[baseFinal + (idx << 8) + state[288 + shift[idx]]] }
        }
    }

    public func sign(nonce: String) -> String {
        var block = Array(nonce.utf8.prefix(16))
        block += [UInt8](repeating: UInt8(ascii: "0"), count: 16 - block.count)
        return transform(block).map { String(format: "%02x", $0) }.joined()
    }

    static var paramsCandidates: [URL] {
        [
            Bundle.main.url(forResource: "auth_param", withExtension: "dat"),
            URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "Resources/auth_param.dat"),
        ].compactMap { $0 }
    }

    public static func load() throws -> Authenticator {
        for url in paramsCandidates {
            if let data = try? Data(contentsOf: url) {
                return try Authenticator(params: data)
            }
        }
        throw FUSError.authParams(String(localized: "auth_param.dat não encontrado no app; rode scripts/fetch-auth-params.sh"))
    }
}
