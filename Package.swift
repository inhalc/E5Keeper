// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "E5Keeper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "E5Keeper",
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ],
    swiftLanguageVersions: [.v5]
)
