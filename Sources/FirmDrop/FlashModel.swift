import AppKit
import FirmDropCore
import Observation
import UniformTypeIdentifiers

enum FirmwareTab: Hashable {
    case download, install
}

@MainActor @Observable
final class FlashModel {
    var selectedTab: FirmwareTab = .download
    var modelText = ""
    var selectedDeviceID = ""
    var reboot = true
    private(set) var devices: [FlashDevice] = []
    private(set) var packages: [FlashSlot: FlashPackage] = [:]
    private(set) var probedDevice: FlashDevice?
    private(set) var isScanning = false
    private(set) var isBusy = false
    private(set) var isFlashing = false
    private(set) var isADBOperation = false
    private(set) var progress: Double?
    private(set) var stage = ""
    private(set) var logs: [String] = []
    private(set) var error: String?
    private(set) var deviceError: String?
    private(set) var success = false
    private var ownedDirectory: URL?
    private var activity: NSObjectProtocol?

    var selectedDevice: FlashDevice? { devices.first { $0.id == selectedDeviceID } }
    var connectionTested: Bool { selectedDevice != nil && selectedDevice == probedDevice }
    var canReview: Bool { !isBusy && reviewRequirement == nil }

    var reviewRequirement: String? {
        guard let device = selectedDevice else { return String(localized: "Conecte o aparelho e clique em Detectar.") }
        guard device.isDownloadMode else { return String(localized: "Coloque o aparelho em modo Download.") }
        guard connectionTested else { return String(localized: "Clique em Testar conexão.") }
        let missing = FlashSlot.allCases.filter { packages[$0] == nil }
        guard missing.isEmpty else {
            return String(localized: "Falta selecionar: \(missing.map(\.rawValue).formatted(.list(type: .and))).")
        }
        guard !modelText.isEmpty else { return String(localized: "Informe o modelo do aparelho.") }
        return nil
    }

    func refreshDevices() async {
        guard !isBusy, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            let found = try await FlashEngine.bundled().devices()
            guard !isBusy else { return }
            devices = found
            deviceError = nil
            if !found.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = found.count == 1 ? found[0].id : ""
            }
            if let probedDevice, !found.contains(probedDevice) { self.probedDevice = nil }
        } catch {
            deviceError = error.localizedDescription
            devices = []
            probedDevice = nil
        }
    }

    func probe() {
        guard !isBusy, let device = selectedDevice else { return }
        begin(String(localized: "Testando a conexão…"))
        probedDevice = nil
        Task {
            defer { finish() }
            do {
                let version = try await FlashEngine.bundled().probe(device, onLine: logHandler())
                guard devices.contains(device), selectedDevice == device else { throw FlashError.deviceChanged }
                probedDevice = device
                stage = String(localized: "Conexão testada · protocolo \(version)")
                append(stage)
            } catch { fail(error) }
        }
    }

    func rebootToDownload() {
        guard !isBusy else { return }
        begin(String(localized: "Verificando o ADB e o Modo de manutenção…"), adb: true)
        probedDevice = nil
        Task {
            defer { finish() }
            do {
                let adb = try ADBDownload.bundled()
                let engine = try FlashEngine.bundled()
                let connected = try await engine.devices()
                guard connected.count <= 1 else { throw ADBError.multipleDevices }
                guard let source = connected.first else { throw ADBError.noDevice }
                try await adb.rebootToDownload(from: source, using: engine, onLine: logHandler())
                stage = String(localized: "Reinício solicitado. Aguardando o modo Download…")
                append(stage)
                let deadline = ContinuousClock.now + .seconds(45)
                while ContinuousClock.now < deadline {
                    let found = try await engine.devices()
                    devices = found
                    if !found.contains(where: { $0.id == selectedDeviceID }) { selectedDeviceID = "" }
                    if let target = found.first(where: {
                        $0.target == source.target && $0.connection != source.connection && $0.isDownloadMode
                    }) {
                        selectedDeviceID = target.id
                        deviceError = nil
                        stage = String(localized: "Modo Download detectado. Clique em Testar conexão para continuar.")
                        append(stage)
                        return
                    }
                    try await Task.sleep(for: .seconds(1))
                }
                throw ADBError.downloadNotDetected
            } catch { fail(error) }
        }
    }

    func importDownload(_ item: DownloadItem) {
        guard !isBusy, case let .completed(url) = item.state else { return }
        modelText = item.model
        selectedTab = .install
        importZIP(url)
    }

    func chooseZIP() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = AppDefaults.downloadFolder
        panel.prompt = String(localized: "Importar")
        if panel.runModal() == .OK, let url = panel.url { importZIP(url) }
    }

    func chooseFolder() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = AppDefaults.downloadFolder
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let selected = try FlashImport.folder(url)
                guard !selected.isEmpty else { throw FlashError.invalidZIP }
                packages = selected
                if let ownedDirectory, !selected.values.contains(where: { $0.url.deletingLastPathComponent() == ownedDirectory }) {
                    cleanup()
                }
                error = nil
                success = false
            } catch { fail(error) }
        }
    }

    func choosePackage(_ slot: FlashSlot) {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = ownedDirectory ?? AppDefaults.downloadFolder
        panel.message = String(localized: "Selecione o pacote \(slot.rawValue).")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let package = try FlashPackage(url: url)
                guard package.slot == slot else { throw FlashError.invalidPackage(url.lastPathComponent) }
                packages[slot] = package
                error = nil
                success = false
            } catch { fail(error) }
        }
    }

    func review() -> FlashPlan? {
        do {
            guard let device = selectedDevice, device == probedDevice else { throw FlashError.probeRequired }
            return try FlashPlan(model: Format.cleanModel(modelText), packages: packages, device: device, reboot: reboot)
        } catch {
            fail(error)
            return nil
        }
    }

    func start(_ plan: FlashPlan) {
        guard !isBusy else { return }
        guard plan.device == selectedDevice, plan.device == probedDevice else { fail(FlashError.deviceChanged); return }
        begin(String(localized: "Conferindo os pacotes antes de instalar…"))
        isFlashing = true
        append(String(localized: "Instalação de \(plan.model) · USB \(plan.device.target)"))
        for package in plan.packages { append(package.url.lastPathComponent) }
        Task {
            defer {
                isFlashing = false
                probedDevice = nil
                finish()
            }
            do {
                try await FlashEngine.bundled().flash(plan, onLine: logHandler())
                success = true
                progress = 1
                stage = String(localized: "Instalação concluída")
                append(stage)
            } catch { fail(error) }
        }
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logs.joined(separator: "\n"), forType: .string)
    }

    func cleanup() {
        guard let ownedDirectory else { return }
        try? FileManager.default.removeItem(at: ownedDirectory)
        self.ownedDirectory = nil
    }

    private func importZIP(_ url: URL) {
        guard !isBusy else { return }
        begin(String(localized: "Extraindo os pacotes do ZIP…"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "FirmDrop-flash-\(UUID().uuidString)")
        Task {
            defer { finish() }
            do {
                let selected = try await FlashImport.extractZIP(url, into: directory, onLine: logHandler())
                cleanup()
                ownedDirectory = directory
                packages = selected
                stage = String(localized: "Pacotes preparados. Conecte e teste o aparelho.")
            } catch { fail(error) }
        }
    }

    private func begin(_ message: String, adb: Bool = false) {
        isBusy = true
        isADBOperation = adb
        error = nil
        success = false
        progress = nil
        stage = message
        append(message)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Instalando firmware")
    }

    private func finish() {
        isBusy = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        success = false
        progress = nil
        stage = String(localized: "A operação não foi concluída")
        append(error.localizedDescription)
    }

    private func logHandler() -> @Sendable (String) -> Void {
        { [weak self] line in Task { @MainActor in self?.receive(line) } }
    }

    private func receive(_ line: String) {
        switch FlashEvent(line: line) {
        case let .progress(completed, total):
            if isBusy { progress = Double(completed) / Double(total) }
        case let .stage(value):
            if isBusy {
                progress = nil
                if isFlashing, value.hasPrefix("Flashing") {
                    stage = String(localized: "Instalando firmware… Não desconecte o cabo.")
                }
            }
            append(value)
        case .done, .device, .probe: break
        case nil: append(line)
        }
    }

    private func append(_ line: String) {
        logs.append(line)
        if logs.count > 800 { logs.removeFirst(logs.count - 800) }
    }
}
