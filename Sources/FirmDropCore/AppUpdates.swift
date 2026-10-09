import Foundation

/// Versão do app no formato X.Y.Z ou X.Y.Z-(alpha|beta|rc).N, com ou sem "v" na frente.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let stage: String?
    public let stageNumber: Int

    public var isPrerelease: Bool { stage != nil }

    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        guard let stage else { return base }
        return "\(base)-\(stage).\(stageNumber)"
    }

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
        guard let base = parts.first else { return nil }
        let numbers = base.split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3, base.split(separator: ".").count == 3 else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]

        guard parts.count == 2 else {
            stage = nil
            stageNumber = 0
            return
        }
        let suffix = parts[1].split(separator: ".").map(String.init)
        guard suffix.count == 2, ["alpha", "beta", "rc"].contains(suffix[0]), let number = Int(suffix[1]) else {
            return nil
        }
        stage = suffix[0]
        stageNumber = number
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        return (lhs.stageRank, lhs.stageNumber) < (rhs.stageRank, rhs.stageNumber)
    }

    private var stageRank: Int {
        switch stage {
        case "alpha": 0
        case "beta": 1
        case "rc": 2
        default: 3
        }
    }

    /// Versão do app em execução (`FirmDropReleaseVersion` guarda o sufixo de pré-lançamento).
    public static var current: AppVersion? {
        let info = Bundle.main.infoDictionary
        let text = info?["FirmDropReleaseVersion"] as? String ?? info?["CFBundleShortVersionString"] as? String
        return text.flatMap(AppVersion.init)
    }
}

/// Release publicada no GitHub.
public struct AppRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let htmlURL: URL
    public let body: String?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// O .dmg da release ou, se não houver, a página dela.
    public var downloadURL: URL {
        assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }
}

public enum UpdateChecker {
    public static let releasesURL = URL(string: "https://api.github.com/repos/julianamarques/firmdrop/releases?per_page=20")!

    public static func fetchReleases(session: URLSession = .shared) async throws -> [AppRelease] {
        var request = URLRequest(url: releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FirmDrop", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FUSError.http(endpoint: "GitHub Releases", status: status) }
        return try JSONDecoder().decode([AppRelease].self, from: data)
    }

    /// Itens da seção "## Mudanças" das notas da release (gerada por scripts/release.sh).
    public static func summary(of notes: String?, limit: Int = 8) -> [String] {
        guard let notes else { return [] }
        var inChanges = false
        var items: [String] = []
        for line in notes.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("## ") {
                inChanges = line.lowercased().contains("mudanças")
            } else if inChanges, line.hasPrefix("- ") {
                items.append(String(line.dropFirst(2)))
            }
        }
        return Array(items.prefix(limit))
    }

    /// A release mais nova que `current`. Quem usa uma versão estável não recebe pré-lançamentos.
    public static func newestRelease(in releases: [AppRelease], newerThan current: AppVersion) -> AppRelease? {
        releases
            .filter { !$0.draft && (current.isPrerelease || !$0.prerelease) }
            .compactMap { release in release.version.map { (release, $0) } }
            .filter { $0.1 > current }
            .max { $0.1 < $1.1 }?
            .0
    }
}
