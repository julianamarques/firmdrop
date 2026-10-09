import Foundation

public enum FUSError: LocalizedError, Equatable, Sendable {
    case modelNotFound(model: String, region: String)
    case invalidModel(String)
    case invalidRegion(String)
    case unsafeFileName(String)
    case noVersionAvailable(model: String, region: String)
    case invalidVersion(String)
    case http(endpoint: String, status: Int)
    case badResponse(String)
    case status(code: String)
    case noBinary(model: String, region: String, version: String)
    case missingKey
    case authParams(String)
    case rangeNotSupported
    case sizeMismatch(expected: Int64, got: Int64)
    case crcMismatch(expected: UInt32, got: UInt32)
    case wrongKey
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case let .modelNotFound(model, region):
            String(localized: "Nenhum firmware encontrado para \(model) na região \(region). Confira o modelo (ex.: SM-A556E) e o CSC.")
        case let .invalidModel(model):
            String(localized: "Modelo inválido: “\(model)”. Use o código do aparelho, por exemplo SM-A556E.")
        case let .invalidRegion(region):
            String(localized: "Região inválida: “\(region)”. Use o código CSC, por exemplo ZTO.")
        case let .unsafeFileName(name):
            String(localized: "O servidor informou um nome de arquivo inválido: “\(name)”.")
        case let .noVersionAvailable(model, region):
            String(localized: "Nenhuma versão publicada para \(model) em \(region).")
        case let .invalidVersion(v):
            String(localized: "Versão inválida: “\(v)”. O formato esperado é PDA/CSC/MODEM.")
        case let .http(endpoint, status):
            String(localized: "O servidor respondeu HTTP \(status) em \(endpoint).")
        case let .badResponse(detail):
            String(localized: "Resposta inesperada do servidor: \(detail).")
        case let .status(code):
            switch code {
            case "F01": String(localized: "Versão de firmware inválida para este modelo/região.")
            case "408": String(localized: "O servidor exigiu IMEI/número de série para este modelo.")
            case "401": String(localized: "Autenticação recusada pelo servidor. O esquema de autenticação pode ter mudado.")
            default: String(localized: "Firmware não encontrado para essa combinação de modelo, região e versão (status \(code)).")
            }
        case let .noBinary(model, region, version):
            String(localized: "Nenhum arquivo disponível para \(model)/\(region) na versão \(version).")
        case .missingKey:
            String(localized: "O servidor não forneceu a chave para decifrar o arquivo.")
        case let .authParams(detail):
            String(localized: "Não foi possível obter os parâmetros de autenticação: \(detail).")
        case .rangeNotSupported:
            String(localized: "O servidor não aceitou retomar o download.")
        case let .sizeMismatch(expected, got):
            String(localized: "Tamanho final (\(got) bytes) diferente do esperado (\(expected) bytes).")
        case let .crcMismatch(expected, got):
            String(localized: "O CRC32 não confere (esperado \(String(format: "%08x", expected)), obtido \(String(format: "%08x", got))). Apague o arquivo e baixe novamente.")
        case .wrongKey:
            String(localized: "A chave não decifra este arquivo (o resultado não é um ZIP).")
        case .fileTooLarge:
            String(localized: "O arquivo parcial é maior que o esperado. Apague-o e baixe novamente.")
        }
    }
}
