import FirmDropCore
import SwiftUI

struct DownloadsTray: View {
    @Environment(DownloadManager.self) private var downloads

    private var hasFinished: Bool {
        downloads.items.contains { if case .completed = $0.state { true } else { false } }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Downloads", systemImage: "arrow.down.circle")
                    .font(.headline)
                if downloads.runningCount > 0 {
                    Text("\(downloads.runningCount) em andamento")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.4)), in: .capsule)
                }
                Spacer()
                if hasFinished {
                    Button("Limpar concluídos") {
                        withAnimation(.smooth) { downloads.clearFinished() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if downloads.items.count <= 3 {
                rows
            } else {
                ScrollView { rows }
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
                    .frame(height: 260)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach(downloads.items) { item in
                DownloadRow(item: item)
            }
        }
    }
}

struct DownloadRow: View {
    @Environment(DownloadManager.self) private var downloads
    let item: DownloadItem
    @State private var confirmCancel = false

    var body: some View {
        HStack(spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(Versions.compact(item.version))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(item.region)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: .capsule)
                }

                switch item.state {
                case .running(.connecting):
                    ProgressView().progressViewStyle(.linear)
                case .running, .paused:
                    ProgressView(value: item.fraction ?? 0)
                        .progressViewStyle(.linear)
                        .tint(item.isRunning ? .accentColor : .secondary)
                default:
                    EmptyView()
                }

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 20))
        .contextMenu { menuItems }
        .confirmationDialog("Cancelar o download de \(item.title)?", isPresented: $confirmCancel) {
            Button("Cancelar e apagar arquivo parcial", role: .destructive) { downloads.cancel(item) }
            Button("Continuar baixando", role: .cancel) {}
        } message: {
            Text("O que já foi baixado será apagado.")
        }
    }

    private var statusSymbol: (name: String, tint: Color?) {
        switch item.state {
        case .running(.decrypting): ("lock.open.fill", .accentColor)
        case .running: ("arrow.down", .accentColor)
        case .paused: ("pause.fill", nil)
        case .completed: ("checkmark", .green)
        case .failed: ("exclamationmark", .orange)
        }
    }

    private var statusIcon: some View {
        let symbol = statusSymbol
        return Image(systemName: symbol.name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(symbol.tint == nil ? Color.secondary : Color.white)
            .symbolEffect(.pulse, isActive: item.isRunning)
            .frame(width: 36, height: 36)
            .glassEffect(symbol.tint.map { Glass.regular.tint($0) } ?? .regular, in: .circle)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                switch item.state {
                case .running:
                    iconButton("pause.fill", help: "Pausar") { downloads.pause(item) }
                case .paused:
                    iconButton("play.fill", help: "Retomar") { downloads.resume(item) }
                case .failed:
                    iconButton("arrow.clockwise", help: "Tentar de novo") { downloads.resume(item) }
                case .completed:
                    EmptyView()
                }
                iconButton("magnifyingglass", help: "Mostrar no Finder") { downloads.reveal(item) }
                if case .completed = item.state {
                    iconButton("xmark", help: "Remover da lista") {
                        withAnimation(.smooth) { downloads.remove(item) }
                    }
                } else {
                    iconButton("xmark", help: "Cancelar download") { confirmCancel = true }
                }
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Mostrar no Finder") { downloads.reveal(item) }
        if case .completed = item.state {
            Button("Remover da lista") { downloads.remove(item) }
        } else {
            Button("Remover da lista (manter arquivo parcial)") { downloads.remove(item) }
            Button("Cancelar e apagar arquivo parcial…") { confirmCancel = true }
        }
        if let key = item.info?.key {
            Divider()
            Button("Copiar chave de decifragem") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.map { String(format: "%02x", $0) }.joined(), forType: .string)
            }
        }
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
    }

    private var progressText: String {
        item.total > 0 ? String(localized: "\(Format.bytes(item.completed)) de \(Format.bytes(item.total))") : ""
    }

    private var statusLine: String {
        switch item.state {
        case .running(.connecting):
            return String(localized: "Conectando ao servidor da Samsung…")
        case .running(.verifyingPartial):
            return String(localized: "Conferindo a parte já baixada… \(percent)")
        case .running(.downloading):
            if let retry = item.retryMessage { return retry }
            var parts = [progressText]
            if item.bytesPerSecond > 0 { parts.append(Format.speed(item.bytesPerSecond)) }
            if let eta = item.secondsRemaining.flatMap(Format.remaining) { parts.append(eta) }
            return parts.joined(separator: " · ")
        case .running(.decrypting):
            return String(localized: "Decifrando… \(percent)")
        case .paused:
            return progressText.isEmpty ? String(localized: "Pausado") : String(localized: "Pausado · \(progressText)")
        case let .completed(url):
            return url.lastPathComponent
        case let .failed(message):
            return message
        }
    }

    private var percent: String {
        (item.fraction ?? 0).formatted(.percent.precision(.fractionLength(0)))
    }

    private var statusColor: Color {
        if case .failed = item.state { return .red }
        if item.retryMessage != nil, item.isRunning { return .orange }
        return .secondary
    }
}
