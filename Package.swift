// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MenuTuck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuTuck",
            path: "Sources/MenuTuck"
        )
    ]
)
