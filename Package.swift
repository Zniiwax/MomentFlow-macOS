// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MomentFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MomentFlow", targets: ["MomentFlow"]),
        .library(name: "MomentFlowCore", targets: ["MomentFlowCore"])
    ],
    targets: [
        .target(
            name: "MomentFlowCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "MomentFlow",
            dependencies: ["MomentFlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "MomentFlowCoreTests",
            dependencies: ["MomentFlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
