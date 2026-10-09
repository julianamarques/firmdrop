import Foundation
import FirmDropCore

enum SettingsKey {
    static let downloadFolder = "downloadFolder"
    static let keepEncrypted = "keepEncrypted"
    static let defaultRegion = "defaultRegion"
    static let recentModels = "recentModels"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let skippedUpdateVersion = "skippedUpdateVersion"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [autoCheckUpdates: true])
    }
}

enum AppDefaults {
    static var downloadFolder: URL {
        if let path = UserDefaults.standard.string(forKey: SettingsKey.downloadFolder), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}

struct Region: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
    var title: String { "\(code) — \(name)" }

    static let brazil = [
        Region(code: "ZTO", name: String(localized: "Brasil (desbloqueado)")),
        Region(code: "ZTA", name: "Claro"),
        Region(code: "ZTM", name: "TIM"),
        Region(code: "ZVV", name: "Vivo"),
    ]
    static let defaultCode = "ZTO"

    static func brazil(_ code: String) -> Region? {
        brazil.first { $0.code == code }
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }

    @MainActor private static let hoursAndMinutes = remainingFormatter([.hour, .minute])
    @MainActor private static let minutesAndSeconds = remainingFormatter([.minute, .second])

    private static func remainingFormatter(_ units: NSCalendar.Unit) -> DateComponentsFormatter {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = units
        return f
    }

    @MainActor static func remaining(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let f = seconds >= 3600 ? hoursAndMinutes : minutesAndSeconds
        return f.string(from: seconds).map { String(localized: "falta \($0)") }
    }

    static func buildDate(_ version: String) -> String? {
        guard let components = Versions.buildDate(version), let date = Calendar.current.date(from: components) else {
            return nil
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    static func cleanModel(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return String(trimmed.split(separator: "/").first ?? "")
    }
}
