import Foundation

enum Identifiers {
    static func isValidModel(_ model: String) -> Bool {
        model.wholeMatch(of: /[A-Z0-9][A-Z0-9-]{0,31}/) != nil
    }

    static func isValidRegion(_ region: String) -> Bool {
        region.wholeMatch(of: /[A-Z0-9]{2,5}/) != nil
    }

    static func isValidVersion(_ version: String) -> Bool {
        version.wholeMatch(of: /[A-Z0-9]{1,32}(\/[A-Z0-9]{1,32}){0,3}/) != nil
    }

    static func isValidModelPath(_ path: String) -> Bool {
        path.wholeMatch(of: /(\/[A-Za-z0-9_-]{1,64}){1,8}\//) != nil
    }

    static func isPlainFileName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9_][A-Za-z0-9._-]{0,254}/) != nil
    }

    static func validated(model: String, region: String) throws -> (model: String, region: String) {
        let model = model.uppercased(), region = region.uppercased()
        guard isValidModel(model) else { throw FUSError.invalidModel(model) }
        guard isValidRegion(region) else { throw FUSError.invalidRegion(region) }
        return (model, region)
    }
}
