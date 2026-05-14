// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PresenterMode",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PresenterMode", targets: ["PresenterMode"])
    ],
    targets: [
        .executableTarget(
            name: "PresenterMode",
            path: "Sources/PresenterMode"
        )
    ]
)
