import FirmDropCore
import SwiftUI

struct ContentView: View {
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        ResultView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !downloads.items.isEmpty {
                    DownloadsTray()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: downloads.items.isEmpty)
            .background { GlassBackdrop() }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                    .help("Ajustes")
                }
            }
    }
}

struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle()
                .fill(Color.blue.opacity(0.35))
                .frame(width: 560)
                .blur(radius: 150)
                .offset(x: -300, y: -260)
            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: 460)
                .blur(radius: 140)
                .offset(x: 320, y: 40)
            Circle()
                .fill(Color.indigo.opacity(0.30))
                .frame(width: 520)
                .blur(radius: 160)
                .offset(x: -60, y: 360)
        }
        .ignoresSafeArea()
    }
}

struct SearchBar: View {
    @Environment(SearchModel.self) private var search
    @FocusState private var modelFocused: Bool
    @State private var customRegion = false

    var body: some View {
        @Bindable var search = search
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(.secondary)
                        TextField("Modelo", text: $search.modelText, prompt: Text("Modelo, ex.: SM-A556E"))
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .monospaced))
                            .focused($modelFocused)
                            .onSubmit { search.search() }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    regionMenu

                    if customRegion {
                        TextField("CSC", text: $search.region, prompt: Text("CSC"))
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 64, height: 46)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .onSubmit { search.search() }
                    }

                    Button {
                        search.search()
                    } label: {
                        Label("Buscar", systemImage: "magnifyingglass")
                            .labelStyle(.titleAndIcon)
                            .frame(height: 30)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!search.canSearch)
                }
            }

            if !search.recentModels.isEmpty {
                HStack(spacing: 6) {
                    Text("Recentes")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(search.recentModels, id: \.self) { model in
                                Button(model) {
                                    search.modelText = model
                                    search.search()
                                }
                                .font(.system(.callout, design: .monospaced))
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    Spacer()
                    Button("Limpar") { search.clearRecents() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }
        }
        .onAppear {
            customRegion = Region.brazil(search.region) == nil
            modelFocused = true
        }
    }

    private var regionLabel: String {
        if customRegion { return String(localized: "Outra") }
        return Region.brazil(search.region).map { "\($0.code) · \($0.name)" } ?? search.region
    }

    private var regionMenu: some View {
        Menu {
            ForEach(Region.brazil) { region in
                Button(region.title) {
                    customRegion = false
                    search.region = region.code
                }
            }
            Divider()
            Button("Outra região…") {
                customRegion = true
                search.region = ""
            }
        } label: {
            Label(regionLabel, systemImage: "globe.americas.fill")
                .frame(height: 30)
        }
        .menuIndicator(.visible)
        .buttonStyle(.glass)
        .controlSize(.large)
        .fixedSize()
    }
}

struct ResultView: View {
    @Environment(SearchModel.self) private var search

    var body: some View {
        switch search.state {
        case .idle:
            ContentUnavailableView {
                Label("Busque um modelo", systemImage: "iphone.gen3")
            } description: {
                Text("Digite o modelo do aparelho (Configurações › Sobre o telefone), por exemplo SM-A556E ou SM-S928B.")
            }
        case .loading:
            ProgressView("Buscando versões…")
                .controlSize(.large)
        case let .failed(message):
            ContentUnavailableView {
                Label("Não foi possível buscar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Tentar de novo") { search.search() }
                    .buttonStyle(.glass)
            }
        case let .loaded(versions):
            if let latest = versions.latest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LatestCard(versions: versions, latest: latest)
                        if !versions.previous.isEmpty {
                            PreviousVersions(versions: versions)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                ContentUnavailableView(
                    "Nenhum firmware publicado",
                    systemImage: "tray",
                    description: Text("Não há firmware para \(versions.model) na região \(versions.region).")
                )
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct LatestCard: View {
    @Environment(SearchModel.self) private var search
    let versions: FirmwareVersions
    let latest: String

    var body: some View {
        GlassCard(title: "Versão mais recente", symbol: "sparkles") {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.tint(.accentColor), in: .circle)

                VStack(alignment: .leading, spacing: 6) {
                    Text(search.latestBinary?.displayName ?? versions.model)
                        .font(.title2.bold())
                    HStack(spacing: 6) {
                        Text("Região \(versions.region)")
                        if let android = versions.android {
                            Text("·")
                            Text("Android \(android)")
                        }
                        if let date = Format.buildDate(latest) {
                            Text("·")
                            Text(date)
                        }
                    }
                    .foregroundStyle(.secondary)

                    Text(Versions.compact(latest))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 2)

                    Group {
                        switch search.latestInfo {
                        case let .success(info)?:
                            Label(Format.bytes(info.size), systemImage: "internaldrive")
                        case let .failure(error)?:
                            Text(error.localizedDescription).foregroundStyle(.red)
                        case nil:
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Consultando tamanho…")
                            }
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                DownloadButton(model: versions.model, region: versions.region, version: latest, prominent: true)
            }
        }
    }
}

struct PreviousVersions: View {
    let versions: FirmwareVersions

    var body: some View {
        GlassCard(title: "Versões anteriores (\(versions.previous.count))", symbol: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                ForEach(Array(versions.previous.enumerated()), id: \.element) { index, version in
                    if index > 0 { Divider().opacity(0.5) }
                    HStack {
                        Text(Versions.compact(version))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        if let date = Format.buildDate(version) {
                            Text(date)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .frame(width: 150, alignment: .trailing)
                        }
                        DownloadButton(model: versions.model, region: versions.region, version: version, prominent: false)
                            .frame(width: 170, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}

struct DownloadButton: View {
    @Environment(DownloadManager.self) private var downloads
    let model: String
    let region: String
    let version: String
    let prominent: Bool

    private var item: DownloadItem? {
        downloads.item(model: model, region: region, version: version)
    }

    @ViewBuilder private var downloadButton: some View {
        let button = Button { downloads.start(model: model, region: region, version: version) } label: {
            Label("Baixar", systemImage: "arrow.down")
                .padding(.horizontal, prominent ? 6 : 0)
        }
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    var body: some View {
        Group {
            switch item?.state {
            case .running?:
                Button {} label: { Label("Baixando…", systemImage: "arrow.down.circle") }
                    .buttonStyle(.glass)
                    .disabled(true)
            case .completed?:
                Button { if let item { downloads.reveal(item) } } label: {
                    Label("Mostrar no Finder", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.glass)
                .tint(.green)
            case .paused?, .failed?:
                Button { if let item { downloads.resume(item) } } label: {
                    Label("Retomar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            case nil:
                downloadButton
            }
        }
        .controlSize(prominent ? .extraLarge : .regular)
    }
}
