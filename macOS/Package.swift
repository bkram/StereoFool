// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StereoFool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "StereoFool", targets: ["StereoFool"])
    ],
    targets: [
        .executableTarget(
            name: "StereoFool",
            path: "Sources/StereoFool"
        )
    ]
)
