// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UniFiLEDController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UniFiLEDControllerApp", targets: ["UniFiLEDControllerApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "UniFiLEDControllerApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/UniFiLEDControllerApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "UniFiLEDControllerAppTests",
            dependencies: ["UniFiLEDControllerApp"],
            path: "Tests/UniFiLEDControllerAppTests"
        )
    ]
)
