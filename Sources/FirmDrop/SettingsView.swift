import FirmDropCore
import SwiftUI

struct SettingsView: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Escolher"
        panel.directoryURL = AppDefaults.downloadFolder
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path(percentEncoded: false)
        }
    }
}
