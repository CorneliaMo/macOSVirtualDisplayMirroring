// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtualDisplayStream",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VirtualDisplayCore", targets: ["VirtualDisplayCore"]),
        .executable(name: "virtual-display-stream", targets: ["VirtualDisplayStreamCLI"]),
    ],
    targets: [
        .target(name: "CVirtualDisplayPrivate", publicHeadersPath: "include"),
        .target(
            name: "VirtualDisplayCore",
            dependencies: ["CVirtualDisplayPrivate"],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"), .linkedFramework("Network"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
            ]
        ),
        .executableTarget(name: "VirtualDisplayStreamCLI", dependencies: ["VirtualDisplayCore"]),
        .testTarget(name: "VirtualDisplayCoreTests", dependencies: ["VirtualDisplayCore"]),
    ]
)
