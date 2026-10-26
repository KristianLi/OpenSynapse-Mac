// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSynapseMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenSynapseMac", targets: ["OpenSynapseMac"]),
        .library(name: "RazerCore", targets: ["RazerCore"]),
    ],
    targets: [
        // IOUSBDeviceInterface is a COM-style plug-in API, which is far simpler to drive from C.
        .target(
            name: "RazerUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "RazerCore",
            dependencies: ["RazerUSB"],
            resources: [.copy("Resources")],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "OpenSynapseMac",
            dependencies: ["RazerCore"]
        ),
        .testTarget(
            name: "RazerCoreTests",
            dependencies: ["RazerCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
