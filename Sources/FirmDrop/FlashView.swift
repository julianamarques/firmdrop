import FirmDropCore
import SwiftUI

struct FlashView: View {
    @Environment(FlashModel.self) private var flash
    @State private var review: FlashReview?

    var body: some View {
        @Bindable var flash = flash
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Instalar firmware").font(.largeTitle.bold())
                    Text("Instalação experimental via USB · motor Brokkr")
                        .foregroundStyle(.secondary)
                }
                deviceCard
                firmwareCard
                if !flash.stage.isEmpty || flash.error != nil {
                    statusCard
                }
                HStack {
                    Toggle("Reiniciar após instalar", isOn: $flash.reboot)
                        .disabled(flash.isBusy)
                    Spacer()
                    Button("Revisar instalação…") {
                        if let plan = flash.review() { review = FlashReview(plan: plan) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!flash.canReview)
                }
                if !flash.logs.isEmpty { logCard }
            }
            .padding(20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .sheet(item: $review) { reviewed in
            FlashConfirmation(plan: reviewed.plan) { flash.start(reviewed.plan) }
        }
        .task {
            while !Task.isCancelled {
                await flash.refreshDevices()
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
            }
        }
    }

    private var deviceCard: some View {
        @Bindable var flash = flash
        return FlashCard(title: "Aparelho", symbol: "cable.connector") {
            HStack {
                if flash.devices.isEmpty {
                    Label("Nenhum Samsung detectado no USB", systemImage: "cable.connector.slash")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Aparelho USB", selection: $flash.selectedDeviceID) {
                        Text("Selecione o aparelho").tag("")
                        ForEach(flash.devices) { device in
                            Text(device.target + " · " + (device.isDownloadMode ? "Download" : "USB"))
                                .tag(device.id)
                        }
                    }
                    .disabled(flash.isBusy)
                }
                Spacer()
                if flash.isScanning { ProgressView().controlSize(.small) }
                Button("Detectar") { Task { await flash.refreshDevices() } }
                    .disabled(flash.isBusy || flash.isScanning)
                Button("Testar conexão") { flash.probe() }
                    .disabled(flash.isBusy || flash.selectedDevice?.isDownloadMode != true)
            }
            if let device = flash.selectedDevice {
                HStack {
                    Text("USB 04e8:\(String(format: "%04x", device.productID))")
                        .font(.system(.caption, design: .monospaced))
                    if flash.connectionTested {
                        Label("Comunicação confirmada", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if device.isDownloadMode {
                        Text("Modo Download detectado. Teste a comunicação antes de instalar.")
                    } else {
                        Text("O macOS detectou o aparelho, mas ele não está em modo Download.")
                    }
                }
                .font(.callout)
            }
            Text("No S25: desligue, segure os dois botões de volume e conecte o cabo ao Mac. Confirme o modo Download com Volume +. Feche OdinMac, Smart Switch e outros programas que usam o aparelho.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Detectar consulta o USB. Testar conexão abre uma sessão do protocolo sem gravar partições. O suporte ao S25 ainda precisa ser validado com um aparelho real.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = flash.deviceError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
    }

    private var firmwareCard: some View {
        @Bindable var flash = flash
        return FlashCard(title: "Pacotes do firmware", symbol: "shippingbox") {
            HStack {
                TextField("Modelo do aparelho, ex.: SM-S931B", text: $flash.modelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                Spacer()
                Button("Importar ZIP…") { flash.chooseZIP() }
                Button("Abrir pasta…") { flash.chooseFolder() }
            }
            .disabled(flash.isBusy)
            Text("Informe o PRODUCT NAME exibido na tela de Download. O USB não confirma o modelo nem a revisão mínima do bootloader.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(FlashSlot.allCases) { slot in
                HStack(spacing: 12) {
                    Text(slot.rawValue)
                        .font(.system(.headline, design: .monospaced))
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        if let package = flash.packages[slot] {
                            Text(package.url.lastPathComponent)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                                .help(package.url.path)
                            Text(Format.bytes(package.size)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Nenhum arquivo selecionado").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Selecionar…") { flash.choosePackage(slot) }
                        .disabled(flash.isBusy)
                        .accessibilityLabel(Text("Selecionar \(slot.rawValue)"))
                }
                .padding(10)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            }
            if let csc = flash.packages[.csc] {
                if csc.preservesData {
                    Label("HOME_CSC: tenta preservar os dados. Tenha um backup antes de instalar.", systemImage: "externaldrive.badge.checkmark")
                        .font(.callout)
                } else {
                    Label("CSC: esta instalação pode apagar todos os dados do aparelho.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            } else {
                Text("HOME_CSC é escolhido por padrão ao importar. Para uma instalação limpa, selecione CSC no último campo.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        FlashCard(title: "Andamento", symbol: flash.success ? "checkmark.circle" : "arrow.triangle.2.circlepath") {
            Text(flash.stage).font(.headline).foregroundStyle(flash.success ? Color.green : .primary)
            if flash.isBusy {
                if let progress = flash.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            if let error = flash.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                Text("Se o teste de conexão falhar, reconecte em modo Download e teste outra porta ou cabo de dados diretamente no Mac. Consulte o registro para distinguir acesso USB de falha no protocolo.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var logCard: some View {
        FlashCard(title: "Registro da operação", symbol: "text.alignleft") {
            HStack {
                Text("Mensagens do motor de instalação")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copiar registro") { flash.copyLog() }
            }
            ScrollView {
                Text(flash.logs.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 160)
        }
    }
}

private struct FlashCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

private struct FlashReview: Identifiable {
    let id = UUID()
    let plan: FlashPlan
}

private struct FlashConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let plan: FlashPlan
    let start: () -> Void
    @State private var confirmed = false
    @State private var confirmedErase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revisar instalação").font(.title2.bold())
            Text("Modelo informado: \(plan.model)").font(.headline)
            Text("Aparelho USB: \(plan.device.target)").font(.system(.callout, design: .monospaced))
            ForEach(plan.packages) { package in
                Text(package.slot.rawValue + ": " + package.url.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
            }
            Text(plan.preservesData ? String(localized: "HOME_CSC: preservar dados") : String(localized: "CSC: instalação limpa, com possível perda de dados"))
                .font(.headline)
            Text("A instalação pode causar perda de dados ou impedir a inicialização se o firmware for incompatível. O teste de USB não verifica modelo, bloqueios de segurança ou anti-rollback. A compatibilidade com o S25 ainda não foi validada em hardware.")
                .font(.callout)
            Toggle("Conferi o PRODUCT NAME e a revisão do bootloader na tela do aparelho e tenho backup.", isOn: $confirmed)
            if !plan.preservesData {
                Toggle("Autorizo a instalação com CSC e a possível exclusão de todos os dados.", isOn: $confirmedErase)
            }
            Text("Mantenha o Mac ligado e o cabo conectado. Depois de iniciar, aguarde a conclusão; a gravação não pode ser pausada.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Iniciar instalação", role: .destructive) { dismiss(); start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!confirmed || (!plan.preservesData && !confirmedErase))
            }
        }
        .padding(26)
        .frame(width: 580)
    }
}
