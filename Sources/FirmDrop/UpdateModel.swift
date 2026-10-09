import AppKit
import FirmDropCore
import Observation
import os

/// Verifica novas versões do app nas Releases do GitHub: ao abrir, uma vez por dia e sob demanda.
@MainActor @Observable
final class UpdateModel {
    private(set) var isChecking = false
    private(set) var lastCheck: Date?

    /// Enquanto retornar true, a verificação automática espera (para não interromper downloads).
    var isBusy: () -> Bool = { false }

    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let log = Logger(subsystem: "com.julianamarques.FirmDrop", category: "updates")

    init() {
        lastCheck = UserDefaults.standard.object(forKey: SettingsKey.lastUpdateCheck) as? Date
    }

    var currentVersion: String { AppVersion.current?.description ?? "desconhecida" }

    func startAutomaticChecks() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                guard let self else { return }
                if UserDefaults.standard.bool(forKey: SettingsKey.autoCheckUpdates), self.isDue, !self.isBusy() {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private var isDue: Bool {
        lastCheck.map { Date().timeIntervalSince($0) >= Self.interval } ?? true
    }

    private func check(userInitiated: Bool) async {
        guard !isChecking, let current = AppVersion.current else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let releases = try await UpdateChecker.fetchReleases()
            let now = Date()
            lastCheck = now
            UserDefaults.standard.set(now, forKey: SettingsKey.lastUpdateCheck)

            let skipped = UserDefaults.standard.string(forKey: SettingsKey.skippedUpdateVersion)
            if let release = UpdateChecker.newestRelease(in: releases, newerThan: current),
               userInitiated || release.tagName != skipped {
                Self.log.info("Nova versão disponível: \(release.tagName, privacy: .public)")
                present(release, current: current)
            } else if userInitiated {
                inform("Você está usando a versão mais recente", "O FirmDrop \(current) é a versão mais nova disponível.")
            }
        } catch {
            Self.log.error("Falha ao verificar atualizações: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                inform("Não foi possível verificar atualizações", "Confira sua conexão com a internet e tente de novo.")
            }
        }
    }

    private func present(_ release: AppRelease, current: AppVersion) {
        let changes = UpdateChecker.summary(of: release.body).map { "• \($0)" }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = "Nova versão do FirmDrop"
        alert.informativeText = ["A versão \(release.version?.description ?? release.tagName) está disponível. Você está usando a \(current).", changes]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: "Baixar Atualização")
        alert.addButton(withTitle: "Agora Não")
        alert.addButton(withTitle: "Ignorar Esta Versão")
        NSApp.activate()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.tagName, forKey: SettingsKey.skippedUpdateVersion)
        default:
            break
        }
    }

    private func inform(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
