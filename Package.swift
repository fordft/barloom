// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barloom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Barloom", targets: ["Barloom"]),
        .library(name: "BarloomCore", targets: ["BarloomCore"])
    ],
    targets: [
        .target(name: "BarloomCore"),
        .target(name: "BarloomMenuBarNative", linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("ApplicationServices")]),
        .executableTarget(name: "Barloom", dependencies: ["BarloomCore", "BarloomMenuBarNative"]),
        .testTarget(name: "BarloomCoreTests", dependencies: ["BarloomCore"]),
        .testTarget(name: "BarloomMenuBarTests", dependencies: ["Barloom", "BarloomCore"])
    ],
    swiftLanguageModes: [.v6]
)
