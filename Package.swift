// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacOSTSKMGR",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MacOSTSKMGR", targets: ["MacOSTSKMGR"])
    ],
    targets: [
        .executableTarget(
            name: "MacOSTSKMGR"
        )
    ]
)
