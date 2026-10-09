import Foundation
import SamFWCore

enum SettingsKey {
    static let downloadFolder = "downloadFolder"
    static let keepEncrypted = "keepEncrypted"
    static let defaultRegion = "defaultRegion"
    static let recentModels = "recentModels"
}

enum AppDefaults {
    static var downloadFolder: URL {
        if let path = UserDefaults.standard.string(forKey: SettingsKey.downloadFolder), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}

/// Códigos CSC (região/operadora) do Brasil. Todos servem o mesmo firmware multi-CSC "OWO".
struct Region: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let brazil = [
        Region(code: "ZTO", name: "Brasil (desbloqueado)"),
        Region(code: "ZTA", name: "Claro"),
        Region(code: "ZTM", name: "TIM"),
        Region(code: "ZVV", name: "Vivo"),
    ]
    static let defaultCode = "ZTO"
}

/// Carrega o `auth_param.dat` uma vez e compartilha entre buscas e downloads.
actor AuthProvider {
    static let shared = AuthProvider()
    private var cached: Authenticator?

    func authenticator() async throws -> Authenticator {
        if let cached { return cached }
        let auth = try await Authenticator.load()
        cached = auth
        return auth
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }

    static func remaining(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        return f.string(from: seconds).map { "falta \($0)" }
    }

    static func buildDate(_ version: String) -> String? {
        guard let components = Versions.buildDate(version), let date = Calendar.current.date(from: components) else {
            return nil
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Aceita "SM-A556E/DS", " sm-a556e " etc. e devolve "SM-A556E".
    static func cleanModel(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return String(trimmed.split(separator: "/").first ?? "")
    }
}
