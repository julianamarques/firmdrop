import AppKit
import SwiftUI

@main
struct FirmDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var search = SearchModel()

    var body: some Scene {
        Window("FirmDrop", id: "main") {
            ContentView()
                .environment(search)
                .environment(appDelegate.downloads)
                .environment(appDelegate.flash)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Verificar Atualizações…") { appDelegate.updates.checkNow() }
            }
        }

        Settings {
            SettingsView()
                .environment(appDelegate.updates)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let downloads = DownloadManager()
    let updates = UpdateModel()
    let flash = FlashModel()

    override init() {
        SettingsKey.registerDefaults()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        updates.isBusy = { [downloads, flash] in downloads.runningCount > 0 || flash.isBusy }
        updates.startAutomaticChecks()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if flash.isBusy {
            let alert = NSAlert()
            alert.messageText = String(localized: "Há uma operação de firmware em andamento")
            alert.informativeText = String(localized: "Aguarde a conclusão antes de fechar o FirmDrop. Durante a instalação, mantenha o cabo conectado.")
            alert.addButton(withTitle: String(localized: "Aguardar"))
            alert.runModal()
            return .terminateCancel
        }
        guard downloads.runningCount > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Há downloads em andamento")
        alert.informativeText = String(localized: "Eles serão pausados e poderão ser retomados quando você abrir o FirmDrop de novo.")
        alert.addButton(withTitle: String(localized: "Pausar e Sair"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        downloads.pauseAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        downloads.save()
        flash.cleanup()
    }
}
