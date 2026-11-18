// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dictado",
    platforms: [.macOS("26.0")],
    targets: [
        // Lógica pura (sin SwiftUI ni AppKit): se prueba con `swift test`.
        .target(
            name: "DictadoKit",
            path: "Sources/DictadoKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Dictado",
            dependencies: ["DictadoKit"],
            path: "Sources/Dictado",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DictadoKitTests",
            dependencies: ["DictadoKit"],
            path: "Tests/DictadoKitTests"
        )
    ]
)
