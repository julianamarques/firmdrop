import Foundation

public struct BinaryInfo: Sendable, Equatable, Codable {
    public var model: String
    public var region: String
    public var version: String
    public var filename: String
    public var path: String
    public var size: Int64
    public var crc32: UInt32?
    public var key: Data?
    public var modelType: String?
    public var displayName: String?

    public var remoteFile: String { path + filename }

    public var localName: String {
        let tag = Versions.compact(version).replacingOccurrences(of: "/", with: "_")
        guard let range = filename.range(of: ".zip") else { return filename }
        return filename.replacingCharacters(in: range, with: "_\(tag)_\(region).zip")
    }

    public var decryptedName: String {
        for ext in [".enc4", ".enc2"] where localName.hasSuffix(ext) {
            return String(localName.dropLast(ext.count))
        }
        return localName
    }

    public var isEncrypted: Bool { key != nil }
}

public actor FUSClient {
    static let baseURL = "https://neofussvr.sslcs.cdngc.net/"
    static let downloadURL = "https://cloud-neofussvr.samsungmobile.com/NF_SmartDownloadBinaryForMass.do"
    static let userAgent = "SMART 2.0"
    static let success: Set<String> = ["200", "S00"]

    private let authenticator: Authenticator
    private(set) var session: URLSession
    private(set) var nonce = ""
    private var signature = ""

    public init(authenticator: Authenticator) async throws {
        self.authenticator = authenticator
        session = Self.makeSession()
        try await reset()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    var authorization: String {
        "FUS nonce=\"\(nonce)\", signature=\"\(signature)\", nc=\"\", type=\"\", realm=\"\""
    }

    public func reset() async throws {
        session.invalidateAndCancel()
        session = Self.makeSession()
        nonce = ""
        signature = ""
        _ = try await post("NF_SmartDownloadGenerateNonce.do", body: Data())
        guard !nonce.isEmpty else { throw FUSError.badResponse("o servidor não enviou um nonce") }
    }

    private func post(_ endpoint: String, body: Data) async throws -> XMLDocument? {
        var request = URLRequest(url: URL(string: Self.baseURL + endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FUSError.badResponse(endpoint) }
        if let newNonce = http.value(forHTTPHeaderField: "NONCE"), !newNonce.isEmpty {
            nonce = newNonce
            signature = authenticator.sign(nonce: newNonce)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FUSError.http(endpoint: endpoint, status: http.statusCode)
        }
        guard !body.isEmpty else { return nil }
        do {
            return try XMLDocument(data: data)
        } catch {
            throw FUSError.badResponse("\(endpoint) não retornou XML (bloqueio do CDN?)")
        }
    }

    public func binaryInform(model: String, region: String, version: String) async throws -> BinaryInfo {
        let model = model.uppercased(), region = region.uppercased()
        let lang = XMLElement(name: "CLIENT_LANGUAGE")
        lang.addChild(XMLElement(name: "Type", stringValue: "String"))
        lang.addChild(XMLElement(name: "Type", stringValue: "ISO 3166-1-alpha-3"))
        lang.addChild(XMLElement(name: "Data", stringValue: "1033"))

        let body = Self.message(put: [
            XMLElement(name: "CmdID", stringValue: "1"),
            Self.data("REQUEST_TYPE", "2"),
            Self.data("BINARY_SW_VERSION", version),
            Self.data("DEVICE_SN_NUMBER", ""),
            Self.data("BINARY_LOCAL_CODE", region),
            Self.data("BINARY_MODEL_NAME", model),
            Self.data("ACCESS_MODE", "1"),
            Self.data("BINARY_NATURE", "1"),
            Self.data("LOGIC_CHECK", FirmwareCrypto.logicCheck(version, nonce: nonce)),
            lang,
        ], get: "BINARY_SW_VERSION")

        guard let doc = try await post("NF_SmartDownloadBinaryInform.do", body: body) else {
            throw FUSError.badResponse("BinaryInform vazio")
        }
        let status = Self.text(doc, "/FUSMsg/FUSBody/Results/Status") ?? "?"
        guard Self.success.contains(status) else { throw FUSError.status(code: status) }

        func put(_ name: String) -> String? { Self.text(doc, "/FUSMsg/FUSBody/Put/\(name)/Data") }
        guard let filename = put("BINARY_NAME"), let size = put("BINARY_BYTE_SIZE").flatMap(Int64.init) else {
            throw FUSError.noBinary(model: model, region: region, version: version)
        }
        let served = Self.text(doc, "/FUSMsg/FUSBody/Results/BINARY_SW_VERSION/Data")
            ?? put("BINARY_SW_VERSION") ?? version

        var key: Data?
        if filename.hasSuffix(".enc4") {
            guard let logic = put("LOGIC_VALUE_FACTORY") ?? put("LOGIC_VALUE_HOME") else { throw FUSError.missingKey }
            key = FirmwareCrypto.v4Key(version: served, logicValue: logic)
        } else if filename.hasSuffix(".enc2") {
            key = FirmwareCrypto.v2Key(version: version, model: model, region: region)
        }

        return BinaryInfo(
            model: model,
            region: region,
            version: served,
            filename: filename,
            path: put("MODEL_PATH") ?? "",
            size: size,
            crc32: put("BINARY_CRC").flatMap(UInt32.init),
            key: key,
            modelType: put("DEVICE_MODEL_TYPE"),
            displayName: put("BINARY_MODEL_DISPLAYNAME")
        )
    }

    public func binaryInit(_ info: BinaryInfo) async throws {
        let name = Array(info.filename)
        let stem = name.count >= 25 ? String(name[(name.count - 25)..<(name.count - 9)]) : ""
        var put = [
            Self.data("BINARY_NAME", info.filename),
            Self.data("BINARY_SW_VERSION", info.version),
            Self.data("DEVICE_LOCAL_CODE", info.region),
        ]
        if let modelType = info.modelType { put.append(Self.data("DEVICE_MODEL_TYPE", modelType)) }
        put.append(Self.data("LOGIC_CHECK", FirmwareCrypto.logicCheck(stem, nonce: nonce)))

        let doc = try await post("NF_SmartDownloadBinaryInitForMass.do", body: Self.message(put: put))
        if let doc, let status = Self.text(doc, "/FUSMsg/FUSBody/Results/Status"), !Self.success.contains(status) {
            throw FUSError.status(code: status)
        }
    }

    public func downloadRequest(for info: BinaryInfo, offset: Int64) -> (URLSession, URLRequest) {
        var request = URLRequest(url: URL(string: "\(Self.downloadURL)?file=\(info.remoteFile)")!)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        request.timeoutInterval = 120
        return (session, request)
    }

    private static func data(_ name: String, _ value: String) -> XMLElement {
        let element = XMLElement(name: name)
        element.addChild(XMLElement(name: "Data", stringValue: value))
        return element
    }

    private static func message(put: [XMLElement], get: String? = nil) -> Data {
        let root = XMLElement(name: "FUSMsg")
        let header = XMLElement(name: "FUSHdr")
        header.addChild(XMLElement(name: "ProtoVer", stringValue: "1"))
        header.addChild(XMLElement(name: "SessionID", stringValue: "0"))
        header.addChild(XMLElement(name: "MsgID", stringValue: "1"))
        root.addChild(header)
        let body = XMLElement(name: "FUSBody")
        let putElement = XMLElement(name: "Put")
        put.forEach(putElement.addChild)
        body.addChild(putElement)
        if let get {
            let getElement = XMLElement(name: "Get")
            getElement.addChild(XMLElement(name: "CmdID", stringValue: "2"))
            getElement.addChild(XMLElement(name: get))
            body.addChild(getElement)
        }
        root.addChild(body)
        return Data(root.xmlString.utf8)
    }

    private static func text(_ doc: XMLDocument, _ xpath: String) -> String? {
        guard let value = (try? doc.nodes(forXPath: xpath))?.first?.stringValue, !value.isEmpty else { return nil }
        return value
    }
}
