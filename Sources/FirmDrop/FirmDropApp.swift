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
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 760)
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
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let downloads = DownloadManager()
    let updates = UpdateModel()

    override init() {
        SettingsKey.registerDefaults()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Quando executado fora de um .app (swift run), garante janela e ícone no Dock.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        updates.isBusy = { [downloads] in downloads.runningCount > 0 }
        updates.startAutomaticChecks()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard downloads.runningCount > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Há downloads em andamento"
        alert.informativeText = "Eles serão pausados e poderão ser retomados quando você abrir o FirmDrop de novo."
        alert.addButton(withTitle: "Pausar e sair")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        downloads.pauseAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        downloads.save()
    }
}
