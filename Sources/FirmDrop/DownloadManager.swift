import AppKit
import Foundation
import Observation
import FirmDropCore
import UserNotifications

@MainActor @Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case running(DownloadPhase)
        case paused
        case completed(URL)
        case failed(String)
    }

    let id: UUID
    let model: String
    let region: String
    let version: String
    let directory: URL
    var info: BinaryInfo?
    var state: State
    var completed: Int64 = 0
    var total: Int64 = 0
    var bytesPerSecond: Double = 0
    var retryMessage: String?

    fileprivate var task: Task<Void, Never>?
    fileprivate var speedSample: (time: Date, bytes: Int64)?

    init(id: UUID = UUID(), model: String, region: String, version: String, directory: URL, state: State) {
        self.id = id
        self.model = model
        self.region = region
        self.version = version
        self.directory = directory
        self.state = state
    }

    var title: String { info?.displayName ?? model }
    var isRunning: Bool { if case .running = state { true } else { false } }
    var fraction: Double? { total > 0 ? min(1, Double(completed) / Double(total)) : nil }

    var encryptedFile: URL? {
        guard let info else { return nil }
        let url = directory.appending(path: info.localName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor @Observable
final class DownloadManager {
    private(set) var items: [DownloadItem] = []
    private var activity: NSObjectProtocol?
    private let storeKey = "downloads.v1"

    init() {
        restore()
    }

    var runningCount: Int { items.filter(\.isRunning).count }

    func start(model: String, region: String, version: String) {
        if let existing = items.first(where: { $0.model == model && $0.region == region && $0.version == version }) {
            if case .completed = existing.state { return }
            resume(existing)
            return
        }
        let item = DownloadItem(model: model, region: region, version: version,
                                directory: AppDefaults.downloadFolder, state: .paused)
        items.insert(item, at: 0)
        requestNotificationPermission()
        resume(item)
    }

    func resume(_ item: DownloadItem) {
        guard !item.isRunning else { return }
        item.state = .running(.connecting)
        item.retryMessage = nil
        item.bytesPerSecond = 0
        item.speedSample = nil

        var job = FirmwareDownload(model: item.model, region: item.region, version: item.version, directory: item.directory)
        job.keepEncrypted = UserDefaults.standard.bool(forKey: SettingsKey.keepEncrypted)

        item.task = Task { [weak self, weak item] in
            do {
                let auth = try await AuthProvider.shared.authenticator()
                let url = try await job.run(
                    authenticator: auth,
                    onInfo: { info in Task { @MainActor in item?.info = info; self?.save() } },
                    onProgress: { progress in Task { @MainActor in item?.apply(progress) } },
                    onRetry: { attempt, error in
                        Task { @MainActor in
                            item?.retryMessage = String(localized: "Falha (\(error.localizedDescription)). Nova tentativa \(attempt)…")
                        }
                    }
                )
                guard let item else { return }
                item.state = .completed(url)
                item.retryMessage = nil
                self?.notify(title: String(localized: "Download concluído"), body: "\(item.title) — \(Versions.compact(item.version))")
            } catch is CancellationError {
                item?.state = .paused
            } catch {
                guard let item else { return }
                item.state = .failed(error.localizedDescription)
                self?.notify(title: String(localized: "Falha no download"), body: "\(item.title): \(error.localizedDescription)")
            }
            item?.task = nil
            self?.updateActivity()
            self?.save()
        }
        updateActivity()
        save()
    }

    func pause(_ item: DownloadItem) {
        item.task?.cancel()
    }

    func cancel(_ item: DownloadItem) {
        item.task?.cancel()
        if case .completed = item.state {} else if let file = item.encryptedFile {
            try? FileManager.default.removeItem(at: file)
        }
        remove(item)
    }

    func remove(_ item: DownloadItem) {
        item.task?.cancel()
        items.removeAll { $0.id == item.id }
        updateActivity()
        save()
    }

    func clearFinished() {
        items.removeAll { if case .completed = $0.state { true } else { false } }
        save()
    }

    func pauseAll() {
        items.forEach { $0.task?.cancel() }
    }

    func reveal(_ item: DownloadItem) {
        if case let .completed(url) = item.state, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let file = item.encryptedFile {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(item.directory)
        }
    }

    private func updateActivity() {
        let running = runningCount
        NSApp?.dockTile.badgeLabel = running > 0 ? "\(running)" : nil
        if running > 0, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Baixando firmware"
            )
        } else if running == 0, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private struct Record: Codable {
        var id: UUID
        var model: String
        var region: String
        var version: String
        var directory: URL
        var info: BinaryInfo?
        var completedFile: URL?
        var failure: String?
        var completed: Int64
        var total: Int64
    }

    func save() {
        let records = items.map { item -> Record in
            var record = Record(id: item.id, model: item.model, region: item.region, version: item.version,
                                directory: item.directory, info: item.info, completed: item.completed, total: item.total)
            switch item.state {
            case let .completed(url): record.completedFile = url
            case let .failed(message): record.failure = message
            default: break
            }
            return record
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return }
        items = records.map { r in
            let state: DownloadItem.State = if let url = r.completedFile { .completed(url) }
                else if let failure = r.failure { .failed(failure) }
                else { .paused }
            let item = DownloadItem(id: r.id, model: r.model, region: r.region, version: r.version,
                                    directory: r.directory, state: state)
            item.info = r.info
            item.total = r.total
            if case .paused = state, let file = item.encryptedFile,
               let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value {
                item.completed = size
            } else {
                item.completed = r.completed
            }
            return item
        }
    }
}

extension DownloadItem {
    func apply(_ progress: DownloadProgress) {
        guard isRunning else { return }
        if state != .running(progress.phase) {
            bytesPerSecond = 0
            speedSample = nil
        }
        state = .running(progress.phase)
        if retryMessage != nil, progress.completed > completed { retryMessage = nil }
        completed = progress.completed
        total = progress.total

        guard progress.phase == .downloading || progress.phase == .decrypting else {
            bytesPerSecond = 0
            speedSample = nil
            return
        }
        let now = Date()
        guard let sample = speedSample else { speedSample = (now, progress.completed); return }
        let elapsed = now.timeIntervalSince(sample.time)
        guard elapsed >= 1 else { return }
        let instant = Double(progress.completed - sample.bytes) / elapsed
        bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * 0.7 + instant * 0.3
        speedSample = (now, progress.completed)
    }

    var secondsRemaining: Double? {
        guard bytesPerSecond > 0, total > completed else { return nil }
        return Double(total - completed) / bytesPerSecond
    }
}
