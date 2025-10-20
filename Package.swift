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
    ],
    targets: [
        .executableTarget(
            name: "UniFiLEDControllerApp",
            dependencies: [],
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
