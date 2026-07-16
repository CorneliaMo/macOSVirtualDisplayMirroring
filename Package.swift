// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtualDisplayStream",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VirtualDisplayCore", targets: ["VirtualDisplayCore"]),
        .executable(name: "virtual-display-stream", targets: ["VirtualDisplayStreamCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "150.0.0"),
        .package(
            url: "https://github.com/httpswift/swifter.git",
            revision: "1e4f51c92d7ca486242d8bf0722b99de2c3531aa"
        ),
    ],
    targets: [
        .target(name: "CVirtualDisplayPrivate", publicHeadersPath: "include"),
        .target(
            name: "VirtualDisplayCore",
            dependencies: [
                "CVirtualDisplayPrivate",
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "Swifter", package: "swifter"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(name: "VirtualDisplayStreamCLI", dependencies: ["VirtualDisplayCore"]),
        .testTarget(name: "VirtualDisplayCoreTests", dependencies: ["VirtualDisplayCore"]),
    ]
)
