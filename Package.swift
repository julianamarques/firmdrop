// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SamFW",
    defaultLocalization: "pt",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SamFW", targets: ["SamFW"]),
    ],
    targets: [
        // Protocolo do servidor FUS, criptografia e download (sem dependência de UI).
        .target(name: "SamFWCore"),
        // Aplicativo SwiftUI.
        .executableTarget(name: "SamFW", dependencies: ["SamFWCore"]),
        .testTarget(name: "SamFWCoreTests", dependencies: ["SamFWCore"]),
    ]
)
