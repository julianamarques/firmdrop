import Foundation
import Testing

@Suite struct LocalizationTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    let state: String
                    let value: String
                }
                let stringUnit: Unit?
            }
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        let url = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func placeholders(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(?:lld|ld|d|@|f|x)/).map { String($0.output) }
    }

    @Test func sourceIsPortuguese() throws {
        #expect(try catalog().sourceLanguage == "pt-BR")
    }

    @Test func everyStringHasAnEnglishTranslation() throws {
        let missing = try catalog().strings.filter { $0.value.localizations?["en"]?.stringUnit?.state != "translated" }
        #expect(missing.isEmpty, "Sem tradução para inglês: \(missing.keys.sorted())")
    }

    @Test func translationsKeepThePlaceholders() throws {
        for (key, entry) in try catalog().strings {
            let value = entry.localizations?["en"]?.stringUnit?.value ?? key
            #expect(placeholders(value) == placeholders(key), "Marcadores diferentes em: \(key)")
        }
    }
}
