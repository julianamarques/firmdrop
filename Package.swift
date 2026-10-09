// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FirmDrop",
    defaultLocalization: "pt",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FirmDrop", targets: ["FirmDrop"]),
    ],
    targets: [
        // Protocolo do servidor FUS, criptografia e download (sem dependência de UI).
        .target(name: "FirmDropCore"),
        // Aplicativo SwiftUI.
        .executableTarget(name: "FirmDrop", dependencies: ["FirmDropCore"]),
        .testTarget(name: "FirmDropCoreTests", dependencies: ["FirmDropCore"]),
    ]
)
