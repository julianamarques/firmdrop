// Gera <saída>/<idioma>.lproj/Localizable.strings para o idioma original do catálogo, em que
// cada texto aponta para ele mesmo. O xcstringstool só compila as traduções e, sem essa tabela,
// o macOS cairia no idioma padrão (inglês) mesmo com o sistema em português.
//   swift scripts/make-source-strings.swift Resources/Localizable.xcstrings build/FirmDrop.app/Contents/Resources
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("uso: make-source-strings.swift <catálogo.xcstrings> <pasta de saída>\n".utf8))
    exit(1)
}
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: args[1]))) as! [String: Any]
let language = catalog["sourceLanguage"] as! String
let keys = (catalog["strings"] as! [String: Any]).keys
let table = Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) })

let folder = URL(filePath: args[2]).appending(path: "\(language).lproj")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try PropertyListSerialization.data(fromPropertyList: table, format: .xml, options: 0)
    .write(to: folder.appending(path: "Localizable.strings"))
print("Pronto: \(folder.path)/Localizable.strings (\(table.count) textos)")
