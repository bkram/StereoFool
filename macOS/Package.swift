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
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "StereoFool",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/StereoFool"
        ),
        .testTarget(
            name: "StereoFoolTests",
            dependencies: ["StereoFool"],
            path: "Tests/StereoFoolTests"
        )
    ]
)
