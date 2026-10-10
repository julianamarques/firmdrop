import Foundation

public enum FlashSlot: String, CaseIterable, Sendable, Identifiable {
    case bl = "BL", ap = "AP", cp = "CP", csc = "CSC"
    public var id: String { rawValue }

    public static func identify(_ filename: String) -> FlashSlot? {
        guard filename.hasSuffix(".tar.md5") || filename.hasSuffix(".tar"),
              Identifiers.isPlainFileName(filename) else { return nil }
        if filename.hasPrefix("HOME_CSC_") { return .csc }
        return allCases.first { filename.hasPrefix($0.rawValue + "_") }
    }
}

public struct FlashPackage: Equatable, Sendable, Identifiable {
    public let url: URL
    public let slot: FlashSlot
    public let size: Int64
    public let modified: Date
    public let fileNumber: UInt64
    public let volumeNumber: UInt64
    public var id: FlashSlot { slot }
    public var preservesData: Bool { slot == .csc && url.lastPathComponent.hasPrefix("HOME_CSC_") }

    public init(url: URL) throws {
        guard url.isFileURL, let slot = FlashSlot.identify(url.lastPathComponent) else {
            throw FlashError.invalidPackage(url.lastPathComponent)
        }
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              let size = (values[.size] as? NSNumber)?.int64Value, size >= 512,
              let modified = values[.modificationDate] as? Date,
              let fileNumber = (values[.systemFileNumber] as? NSNumber)?.uint64Value,
              let volumeNumber = (values[.systemNumber] as? NSNumber)?.uint64Value else {
            throw FlashError.invalidPackage(url.lastPathComponent)
        }
        self.url = url.standardizedFileURL
        self.slot = slot
        self.size = size
        self.modified = modified
        self.fileNumber = fileNumber
        self.volumeNumber = volumeNumber
    }

    public func checkUnchanged() throws {
        guard try FlashPackage(url: url) == self else { throw FlashError.changedPackage(url.lastPathComponent) }
    }

    public func build(for model: String) -> String? {
        let code = String(model.dropFirst(3))
        let name = url.lastPathComponent
        let stem = String(name.dropLast(name.hasSuffix(".tar.md5") ? 8 : 4))
        return stem.split(separator: "_").map(String.init).first { token in
            guard token.hasPrefix(code) else { return false }
            let suffix = String(token.dropFirst(code.count))
            return suffix.wholeMatch(of: /[A-Z]{2}[A-Z0-9]{5,16}/) != nil
        }
    }

    public static func select(_ urls: [URL]) throws -> [FlashSlot: FlashPackage] {
        var result: [FlashSlot: FlashPackage] = [:]
        let packages = try urls.filter { FlashSlot.identify($0.lastPathComponent) != nil }.map { try FlashPackage(url: $0) }
        for slot in FlashSlot.allCases {
            let matching = packages.filter { $0.slot == slot }
            if slot == .csc {
                let home = matching.filter(\.preservesData)
                let reset = matching.filter { !$0.preservesData }
                guard home.count <= 1, reset.count <= 1 else { throw FlashError.ambiguousSlot(slot.rawValue) }
                result[slot] = home.first ?? reset.first
            } else {
                guard matching.count <= 1 else { throw FlashError.ambiguousSlot(slot.rawValue) }
                result[slot] = matching.first
            }
        }
        return result
    }
}

public struct FlashPlan: Equatable, Sendable {
    public let model: String
    public let packages: [FlashPackage]
    public let device: FlashDevice
    public let reboot: Bool
    public var preservesData: Bool { packages.contains(where: \.preservesData) }

    public init(model: String, packages: [FlashSlot: FlashPackage], device: FlashDevice, reboot: Bool) throws {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard model.wholeMatch(of: /SM-[A-Z0-9]{5,12}/) != nil else { throw FUSError.invalidModel(model) }
        guard device.isDownloadMode else { throw FlashError.notInDownloadMode }
        var ordered: [FlashPackage] = []
        for slot in FlashSlot.allCases {
            guard let package = packages[slot], package.slot == slot else { throw FlashError.missingSlot(slot.rawValue) }
            try package.checkUnchanged()
            guard package.build(for: model) != nil else { throw FlashError.modelMismatch(package.url.lastPathComponent, model) }
            ordered.append(package)
        }
        guard packages[.bl]?.build(for: model) == packages[.ap]?.build(for: model) else {
            throw FlashError.mixedBuilds
        }
        self.model = model
        self.packages = ordered
        self.device = device
        self.reboot = reboot
    }

    public func arguments(resume: Bool = false) throws -> [String] {
        for package in packages { try package.checkUnchanged() }
        var arguments = ["--flash", "--target", device.target, "--connection", String(device.connection)]
        if preservesData { arguments.append("--preserve") }
        if !reboot { arguments.append("--no-reboot") }
        if resume { arguments.append("--resume") }
        for package in packages { arguments += ["--file", package.url.path] }
        return arguments
    }
}

public enum FlashError: LocalizedError, Equatable, Sendable {
    case invalidPackage(String), changedPackage(String), ambiguousSlot(String), missingSlot(String)
    case modelMismatch(String, String), mixedBuilds, notInDownloadMode, engineMissing
    case commandFailed(Int32, String), timedOut, outputTooLarge, invalidZIP
    case deviceChanged, probeRequired, incompleteFlash, notEnoughSpace(Int64)

    public var errorDescription: String? {
        switch self {
        case let .invalidPackage(name): String(localized: "Pacote inválido: \(name). Selecione um arquivo BL, AP, CP ou CSC em .tar ou .tar.md5.")
        case let .changedPackage(name): String(localized: "O arquivo \(name) mudou desde a seleção. Selecione-o novamente.")
        case let .ambiguousSlot(slot): String(localized: "Há mais de um pacote para \(slot). Selecione os arquivos individualmente.")
        case let .missingSlot(slot): String(localized: "Selecione o pacote \(slot).")
        case let .modelMismatch(name, model): String(localized: "O nome de \(name) não corresponde ao modelo \(model).")
        case .mixedBuilds: String(localized: "BL e AP pertencem a versões diferentes. Use arquivos do mesmo download.")
        case .notInDownloadMode: String(localized: "O aparelho não está em modo Download.")
        case .engineMissing: String(localized: "O motor de instalação não está incluído neste build. Compile com scripts/build-app.sh.")
        case let .commandFailed(code, detail): String(localized: "A operação falhou (código \(code)): \(detail)")
        case .timedOut: String(localized: "O aparelho ou processo não respondeu a tempo. Reconecte em modo Download e tente novamente.")
        case .outputTooLarge: String(localized: "A resposta excedeu o limite de tamanho permitido.")
        case .invalidZIP: String(localized: "O ZIP não contém um conjunto válido de pacotes Samsung ou contém nomes ambíguos.")
        case .deviceChanged: String(localized: "A conexão USB mudou. Detecte e teste o aparelho novamente.")
        case .probeRequired: String(localized: "Teste a conexão com o aparelho antes de instalar.")
        case let .notEnoughSpace(bytes):
            String(localized: "Espaço insuficiente para extrair os pacotes. São necessários \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) livres no disco.")
        case .incompleteFlash: String(localized: "O motor encerrou sem confirmar a conclusão da instalação. Consulte o registro antes de tentar novamente.")
        }
    }
}
