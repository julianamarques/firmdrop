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
            "Nenhum firmware encontrado para \(model) na região \(region). Confira o modelo (ex.: SM-A556E) e o CSC."
        case let .invalidModel(model):
            "Modelo inválido: “\(model)”. Use o código do aparelho, por exemplo SM-A556E."
        case let .invalidRegion(region):
            "Região inválida: “\(region)”. Use o código CSC, por exemplo ZTO."
        case let .unsafeFileName(name):
            "O servidor informou um nome de arquivo inválido: “\(name)”."
        case let .noVersionAvailable(model, region):
            "Nenhuma versão publicada para \(model) em \(region)."
        case let .invalidVersion(v):
            "Versão inválida: “\(v)”. O formato esperado é PDA/CSC/MODEM."
        case let .http(endpoint, status):
            "O servidor respondeu HTTP \(status) em \(endpoint)."
        case let .badResponse(detail):
            "Resposta inesperada do servidor: \(detail)."
        case let .status(code):
            switch code {
            case "F01": "Versão de firmware inválida para este modelo/região."
            case "408": "O servidor exigiu IMEI/número de série para este modelo."
            case "401": "Autenticação recusada pelo servidor. O esquema de autenticação pode ter mudado."
            default: "Firmware não encontrado para essa combinação de modelo, região e versão (status \(code))."
            }
        case let .noBinary(model, region, version):
            "Nenhum arquivo disponível para \(model)/\(region) na versão \(version)."
        case .missingKey:
            "O servidor não forneceu a chave para decifrar o arquivo."
        case let .authParams(detail):
            "Não foi possível obter os parâmetros de autenticação: \(detail)."
        case .rangeNotSupported:
            "O servidor não aceitou retomar o download."
        case let .sizeMismatch(expected, got):
            "Tamanho final (\(got) bytes) diferente do esperado (\(expected) bytes)."
        case let .crcMismatch(expected, got):
            String(format: "O CRC32 não confere (esperado %08x, obtido %08x). Apague o arquivo e baixe novamente.", expected, got)
        case .wrongKey:
            "A chave não decifra este arquivo (o resultado não é um ZIP)."
        case .fileTooLarge:
            "O arquivo parcial é maior que o esperado. Apague-o e baixe novamente."
        }
    }
}
