import Foundation
import Observation
import FirmDropCore

@MainActor @Observable
final class SearchModel {
    enum State {
        case idle
        case loading
        case loaded(FirmwareVersions)
        case failed(String)
    }

    var modelText = ""
    var region: String = UserDefaults.standard.string(forKey: SettingsKey.defaultRegion) ?? Region.defaultCode
    private(set) var state: State = .idle
    /// Detalhes da versão mais recente (nome comercial, tamanho), obtidos do FUS.
    private(set) var latestInfo: BinaryInfo?
    private(set) var latestInfoError: String?
    private(set) var recentModels: [String] = UserDefaults.standard.stringArray(forKey: SettingsKey.recentModels) ?? []

    private var searchTask: Task<Void, Never>?

    var canSearch: Bool { !Format.cleanModel(modelText).isEmpty && !region.isEmpty }

    func search() {
        let model = Format.cleanModel(modelText)
        let region = region.trimmingCharacters(in: .whitespaces).uppercased()
        guard !model.isEmpty, !region.isEmpty else { return }
        modelText = model

        searchTask?.cancel()
        state = .loading
        latestInfo = nil
        latestInfoError = nil

        searchTask = Task {
            do {
                let versions = try await Versions.fetch(model: model, region: region)
                guard !Task.isCancelled else { return }
                state = .loaded(versions)
                remember(model)
                if let latest = versions.latest { await loadInfo(model: model, region: region, version: latest) }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadInfo(model: String, region: String, version: String) async {
        do {
            let client = try await FUSClient(authenticator: try await AuthProvider.shared.authenticator())
            let info = try await client.binaryInform(model: model, region: region, version: version)
            guard !Task.isCancelled else { return }
            latestInfo = info
        } catch {
            guard !Task.isCancelled else { return }
            latestInfoError = error.localizedDescription
        }
    }

    private func remember(_ model: String) {
        recentModels.removeAll { $0 == model }
        recentModels.insert(model, at: 0)
        recentModels = Array(recentModels.prefix(8))
        UserDefaults.standard.set(recentModels, forKey: SettingsKey.recentModels)
    }

    func clearRecents() {
        recentModels = []
        UserDefaults.standard.removeObject(forKey: SettingsKey.recentModels)
    }
}
