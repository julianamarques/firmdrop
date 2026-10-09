import FirmDropCore
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updates
    @AppStorage(SettingsKey.autoCheckUpdates) private var autoCheckUpdates = true
    @AppStorage(SettingsKey.downloadFolder) private var downloadFolder = ""
    @AppStorage(SettingsKey.keepEncrypted) private var keepEncrypted = false
    @AppStorage(SettingsKey.defaultRegion) private var defaultRegion = Region.defaultCode

    var body: some View {
        Form {
            Section {
                LabeledContent("Salvar em") {
                    HStack {
                        Image(systemName: "folder")
                        Text(AppDefaults.downloadFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(AppDefaults.downloadFolder.path(percentEncoded: false))
                        Button("Escolher…", action: chooseFolder)
                    }
                }
                Toggle("Manter o arquivo cifrado (.enc4) depois de decifrar", isOn: $keepEncrypted)
            } footer: {
                Text("Durante a decifragem é preciso o dobro do tamanho do firmware livre em disco.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Região padrão", selection: $defaultRegion) {
                    ForEach(Region.brazil) { region in
                        Text("\(region.code) — \(region.name)").tag(region.code)
                    }
                }
            } footer: {
                Text("Os códigos do Brasil servem o mesmo firmware; o CSC ativo é escolhido pelo chip.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Verificar atualizações automaticamente", isOn: $autoCheckUpdates)
                LabeledContent("Versão instalada", value: updates.currentVersion)
                LabeledContent("Última verificação") {
                    if let lastCheck = updates.lastCheck {
                        Text(lastCheck, format: .dateTime.day().month().hour().minute())
                    } else {
                        Text("Nunca")
                    }
                }
                HStack {
                    Button("Verificar Agora") { updates.checkNow() }
                        .disabled(updates.isChecking)
                    if updates.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }
            } header: {
                Text("Atualizações")
            } footer: {
                Text("No modo automático, o app verifica ao abrir e uma vez por dia. As novas versões são baixadas da página de Releases no GitHub.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Escolher")
        panel.directoryURL = AppDefaults.downloadFolder
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path(percentEncoded: false)
        }
    }
}
