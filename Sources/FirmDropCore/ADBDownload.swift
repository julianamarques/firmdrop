import Foundation

struct ADBDevice: Equatable, Sendable {
    let serial: String
    let transport: UInt64
    let state: String

    init?(line: String) {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 4, ["device", "unauthorized", "offline"].contains(fields[1]),
              fields.contains(where: { $0.hasPrefix("usb:") }),
              let field = fields.first(where: { $0.hasPrefix("transport_id:") }),
              let transport = UInt64(field.dropFirst("transport_id:".count)), transport > 0 else { return nil }
        self.serial = fields[0]
        self.transport = transport
        self.state = fields[1]
    }
}

public struct ADBDownload: Sendable {
    public let executable: URL
    private let serverRunning: @Sendable () -> Bool

    public init(executable: URL) {
        self.init(executable: executable, serverRunning: { Self.isServerRunning() })
    }

    init(executable: URL, serverRunning: @escaping @Sendable () -> Bool) {
        self.executable = executable
        self.serverRunning = serverRunning
    }

    public static func bundled() throws -> ADBDownload {
        guard Bundle.main.bundleURL.pathExtension != "app" else {
            return try locate([Bundle.main.bundleURL.appending(path: "Contents/MacOS/adb")])
        }
        let environment = ProcessInfo.processInfo.environment
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "build/adb/adb"),
            URL(filePath: "/opt/homebrew/bin/adb"),
            URL(filePath: "/usr/local/bin/adb"),
            homeDirectory.appending(path: "Library/Android/sdk/platform-tools/adb"),
        ]
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = environment[key], path.hasPrefix("/") {
                candidates.append(URL(filePath: path).appending(path: "platform-tools/adb"))
            }
        }
        candidates += (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(filePath: String($0)).appending(path: "adb") }
        return try locate(candidates)
    }

    static func locate(_ candidates: [URL]) throws -> ADBDownload {
        guard let url = candidates.first(where: {
            guard $0.isFileURL, FileManager.default.isExecutableFile(atPath: $0.path) else { return false }
            return (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                || (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) else { throw ADBError.notInstalled }
        return ADBDownload(executable: url)
    }

    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        for key in ["ANDROID_ADB_SERVER_PORT", "ADB_SERVER_SOCKET", "ANDROID_SERIAL"] { environment[key] = nil }
        environment["ADB_MDNS"] = "0"
        return environment
    }()

    static func isServerRunning() -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(5037).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    public func rebootToDownload(from device: FlashDevice, using engine: FlashEngine,
                                 onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        guard !device.isDownloadMode else { throw ADBError.alreadyInDownloadMode }
        let startsServer = !serverRunning()
        do {
            try await reboot(device, using: engine, onLine: onLine)
        } catch {
            if startsServer { _ = try? await command(["kill-server"]) }
            throw error
        }
        if startsServer { _ = try? await command(["kill-server"]) }
    }

    private func reboot(_ device: FlashDevice, using engine: FlashEngine,
                        onLine: @escaping @Sendable (String) -> Void) async throws {
        try await checkUSB(device, using: engine)
        let target = try await singleDevice()
        let prefix = ["-t", String(target.transport)]
        let manufacturer = try await command(prefix + ["shell", "getprop", "ro.product.manufacturer"])
        guard manufacturer.lowercased() == "samsung" else { throw ADBError.notSamsung }
        let maintenance = try await command(prefix + ["shell", "getprop", "persist.sys.is_in_maintenance_mode"])
        guard maintenance == "true" else { throw ADBError.maintenanceRequired }
        guard try await singleDevice() == target else { throw ADBError.deviceChanged }
        try await checkUSB(device, using: engine)
        _ = try await command(prefix + ["reboot", "download"], onLine: onLine)
    }

    private func singleDevice() async throws -> ADBDevice {
        let result = try await command(["devices", "-l"])
        let devices = result.components(separatedBy: .newlines).compactMap(ADBDevice.init(line:))
        guard !devices.isEmpty else { throw ADBError.noDevice }
        guard devices.count == 1 else { throw ADBError.multipleDevices }
        guard let device = devices.first else { throw ADBError.noDevice }
        guard device.state != "unauthorized" else { throw ADBError.unauthorized }
        guard device.state == "device" else { throw ADBError.offline }
        return device
    }

    private func checkUSB(_ device: FlashDevice, using engine: FlashEngine) async throws {
        let connected = try await engine.devices()
        guard connected.count <= 1 else { throw ADBError.multipleDevices }
        guard connected == [device] else { throw ADBError.deviceChanged }
    }

    private func command(_ arguments: [String], onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let result = try await CommandRunner.run(executable, arguments: arguments, environment: Self.environment,
                                                 timeout: 15, onLine: onLine)
        try result.requireSuccess()
        guard !result.truncated else { throw FlashError.outputTooLarge }
        return result.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ADBError: LocalizedError, Equatable, Sendable {
    case notInstalled, noDevice, multipleDevices, unauthorized, offline, notSamsung
    case maintenanceRequired, deviceChanged, alreadyInDownloadMode, downloadNotDetected

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            String(localized: "O ADB incluído no FirmDrop não foi encontrado. Reinstale o app.")
        case .noDevice:
            String(localized: "Nenhum aparelho USB disponível no ADB. Mantenha o Samsung ligado, ative a depuração USB e autorize este Mac na tela do aparelho.")
        case .multipleDevices:
            String(localized: "Há mais de um aparelho conectado. Para reiniciar por ADB, deixe apenas o Samsung desejado conectado por USB.")
        case .unauthorized:
            String(localized: "Autorize a depuração USB neste Mac pela tela do aparelho e tente novamente.")
        case .offline:
            String(localized: "O aparelho está offline no ADB. Desbloqueie a tela, reconecte o cabo e tente novamente.")
        case .notSamsung:
            String(localized: "O aparelho conectado ao ADB não foi identificado como Samsung.")
        case .maintenanceRequired:
            String(localized: "Ative o Modo de manutenção no Samsung e aguarde o reinício. Deixe esse modo ativo e o telefone ligado para reiniciar em Download por ADB.")
        case .deviceChanged:
            String(localized: "A conexão do aparelho mudou durante a verificação do ADB. Confira o cabo e tente novamente.")
        case .alreadyInDownloadMode:
            String(localized: "O aparelho já está em modo Download. Use Testar conexão para continuar.")
        case .downloadNotDetected:
            String(localized: "O reinício foi solicitado, mas o modo Download não apareceu no USB a tempo. Confira a tela do aparelho. Se aparecer Reboot Device - D2, ele não permaneceu em modo Download.")
        }
    }
}
