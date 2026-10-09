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
    private(set) var latestInfo: Result<BinaryInfo, any Error>?
    private(set) var recentModels: [String] = UserDefaults.standard.stringArray(forKey: SettingsKey.recentModels) ?? []

    private var searchTask: Task<Void, Never>?

    var latestBinary: BinaryInfo? { try? latestInfo?.get() }

    var canSearch: Bool { !Format.cleanModel(modelText).isEmpty && !region.isEmpty }

    func search() {
        let model = Format.cleanModel(modelText)
        let region = region.trimmingCharacters(in: .whitespaces).uppercased()
        guard !model.isEmpty, !region.isEmpty else { return }
        modelText = model

        searchTask?.cancel()
        state = .loading
        latestInfo = nil

        searchTask = Task {
            async let client = FUSClient(authenticator: Authenticator.shared())
            do {
                let versions = try await Versions.fetch(model: model, region: region)
                guard !Task.isCancelled else { return }
                state = .loaded(versions)
                remember(model)
                guard let latest = versions.latest else { return }
                let info: Result<BinaryInfo, any Error>
                do {
                    info = .success(try await client.binaryInform(model: model, region: region, version: latest))
                } catch {
                    info = .failure(error)
                }
                guard !Task.isCancelled else { return }
                latestInfo = info
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
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
