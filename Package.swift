// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tabview",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tabview",
            path: "Sources/Tabview",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("QuickLookThumbnailing"),
            ]
        )
    ]
)
