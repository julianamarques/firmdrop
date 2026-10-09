import Foundation

extension XMLDocument {
    static func untrusted(_ data: Data) throws -> XMLDocument {
        try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
    }
}
