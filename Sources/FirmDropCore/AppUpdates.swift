import Foundation

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
        let components = base.split(separator: ".")
        let numbers = components.compactMap { Int($0) }
        guard components.count == 3, numbers.count == 3 else { return nil }
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
        (lhs.major, lhs.minor, lhs.patch, lhs.stageRank, lhs.stageNumber)
            < (rhs.major, rhs.minor, rhs.patch, rhs.stageRank, rhs.stageNumber)
    }

    private var stageRank: Int {
        switch stage {
        case "alpha": 0
        case "beta": 1
        case "rc": 2
        default: 3
        }
    }

    public static var current: AppVersion? {
        let info = Bundle.main.infoDictionary
        let text = info?["FirmDropReleaseVersion"] as? String ?? info?["CFBundleShortVersionString"] as? String
        return text.flatMap(AppVersion.init)
    }
}

public struct AppRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
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

    public var downloadURL: URL {
        [assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL, htmlURL]
            .compactMap { $0 }
            .first(where: UpdateChecker.isTrusted) ?? UpdateChecker.releasesPage
    }
}

public enum UpdateChecker {
    static let releasesURL = URL(string: "https://api.github.com/repos/julianamarques/firmdrop/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/julianamarques/firmdrop/releases")!
    static let summaryLimit = 8

    static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host() == "github.com" && url.port == nil && url.user() == nil
            && url.path().hasPrefix("/julianamarques/firmdrop/releases/")
    }

    public static func fetchReleases(session: URLSession = .shared) async throws -> [AppRelease] {
        var request = URLRequest(url: releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FirmDrop", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FUSError.http(endpoint: "GitHub Releases", status: status) }
        return try JSONDecoder().decode([AppRelease].self, from: data)
    }

    public static func summary(of notes: String?) -> [String] {
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
        return Array(items.prefix(summaryLimit))
    }

    public static func newestRelease(in releases: [AppRelease], newerThan current: AppVersion) -> AppRelease? {
        releases
            .filter { !$0.draft && (current.isPrerelease || !$0.prerelease) }
            .compactMap { release in release.version.map { (release, $0) } }
            .filter { $0.1 > current }
            .max { $0.1 < $1.1 }?
            .0
    }
}
