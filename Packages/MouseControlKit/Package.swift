// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MouseControlKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "MouseControlKit", targets: ["MouseControlKit"]),
    ],
    targets: [
        .target(name: "MouseControlKit"),
        .testTarget(name: "MouseControlKitTests", dependencies: ["MouseControlKit"]),
    ],
    swiftLanguageModes: [.v6]
)
