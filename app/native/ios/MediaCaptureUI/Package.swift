// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MediaCaptureUI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "MediaCaptureUI", targets: ["MediaCaptureUI"]),
    ],
    dependencies: [
        .package(path: "../MediaCapture"),
    ],
    targets: [
        .target(
            name: "MediaCaptureUI",
            dependencies: [
                .product(name: "MediaCapture", package: "MediaCapture"),
                .product(name: "MediaCaptureAppleRendering", package: "MediaCapture"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("UIKit")]
        ),
        .testTarget(
            name: "MediaCaptureUITests",
            dependencies: ["MediaCaptureUI"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
