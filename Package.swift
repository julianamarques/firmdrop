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
        .target(name: "FirmDropCore"),
        .executableTarget(name: "FirmDrop", dependencies: ["FirmDropCore"]),
        .testTarget(name: "FirmDropCoreTests", dependencies: ["FirmDropCore"]),
    ]
)
