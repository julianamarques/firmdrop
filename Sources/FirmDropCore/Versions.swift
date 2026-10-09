import Foundation

/// Versões publicadas no servidor público de FOTA (`version.xml`).
public struct FirmwareVersions: Sendable, Equatable {
    public var model: String
    public var region: String
    public var latest: String?
    public var android: String?
    /// Versões anteriores conhecidas (as que têm atualização OTA), da mais nova para a mais antiga.
    public var previous: [String]
}

public enum Versions {
    static let urlTemplate = "https://fota-cloud-dn.ospserver.net/firmware/%@/%@/version.xml"
    /// O CDN bloqueia User-Agents genéricos (curl, navegadores); este é aceito.
    static let userAgent = "Kies2.0_FUS"

    /// Converte PDA/CSC/MODEM para PDA/CSC/MODEM/PHONE, o formato que o FUS espera.
    public static func normalize(_ version: String) throws -> String {
        var parts = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        if parts.count == 3 { parts.append(parts[0]) }
        guard parts.count == 4, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw FUSError.invalidVersion(version)
        }
        if parts[2].isEmpty { parts[2] = parts[0] } // aparelhos Wi-Fi não têm modem
        return parts.joined(separator: "/")
    }

    /// Chave cronológica: os 3 últimos caracteres do PDA são ano, mês e build (ex.: …DZI1 → Z, I, 1).
    public static func sortKey(_ version: String) -> String {
        String(version.split(separator: "/").first?.suffix(3) ?? "")
    }

    /// Mês e ano de compilação codificados no PDA (…DZI1 → Z = 2026, I = setembro).
    public static func buildDate(_ version: String) -> DateComponents? {
        let key = Array(sortKey(version).utf8)
        guard key.count == 3,
              (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(key[0]),
              (UInt8(ascii: "A")...UInt8(ascii: "L")).contains(key[1]) else { return nil }
        // A = 2001 … Z = 2026; depois disso o ciclo recomeça em A.
        var year = 2001 + Int(key[0] - UInt8(ascii: "A"))
        if year < 2010 { year += 26 }
        return DateComponents(year: year, month: Int(key[1] - UInt8(ascii: "A")) + 1)
    }

    /// Versão exibida de forma compacta: remove partes repetidas (PDA costuma ser igual a PHONE).
    public static func compact(_ version: String) -> String {
        var seen = Set<Substring>()
        return version.split(separator: "/").filter { seen.insert($0).inserted }.joined(separator: "/")
    }

    public static func parse(_ data: Data, model: String, region: String) throws -> FirmwareVersions {
        let doc: XMLDocument
        do { doc = try XMLDocument(data: data) } catch {
            throw FUSError.badResponse("version.xml inválido")
        }
        let latestNode = try doc.nodes(forXPath: "/versioninfo/firmware/version/latest").first as? XMLElement
        let latestText = latestNode?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let latest = latestText.isEmpty ? nil : try normalize(latestText)

        let values = try doc.nodes(forXPath: "/versioninfo/firmware/version/upgrade/value")
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let previous = Set(try values.map(normalize)).subtracting([latest].compactMap { $0 })
            .sorted { sortKey($0) > sortKey($1) }

        return FirmwareVersions(
            model: model,
            region: region,
            latest: latest,
            android: latestNode?.attribute(forName: "o")?.stringValue,
            previous: previous
        )
    }

    public static func fetch(model: String, region: String, session: URLSession = .shared) async throws -> FirmwareVersions {
        let model = model.uppercased(), region = region.uppercased()
        guard let url = URL(string: String(format: urlTemplate, region, model)) else {
            throw FUSError.modelNotFound(model: model, region: region)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // O CDN responde 403 (e não 404) quando a combinação modelo/região não existe.
        if status == 403 || status == 404 { throw FUSError.modelNotFound(model: model, region: region) }
        guard status == 200 else { throw FUSError.http(endpoint: "version.xml", status: status) }
        return try parse(data, model: model, region: region)
    }
}
