// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tune",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Tune", targets: ["Tune"])
    ],
    targets: [
        .executableTarget(
            name: "Tune",
            path: "Sources/Tune"
        )
    ]
)
