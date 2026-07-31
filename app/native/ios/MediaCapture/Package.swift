// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MediaCapture",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "MediaCapture", targets: ["MediaCapture"]),
        .library(
            name: "MediaCaptureAppleRendering",
            targets: ["MediaCaptureAppleRendering"]
        ),
    ],
    targets: [
        .target(
            name: "MediaCapture",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "MediaCaptureAppleRendering",
            dependencies: ["MediaCapture"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("UIKit"),
            ]
        ),
        .testTarget(
            name: "MediaCaptureTests",
            dependencies: ["MediaCapture", "MediaCaptureAppleRendering"]
        ),
        .testTarget(
            name: "MediaCaptureAppleRenderingTests",
            dependencies: ["MediaCapture", "MediaCaptureAppleRendering"]
        ),
        .testTarget(
            name: "MediaCapturePublicConsumerTests",
            dependencies: ["MediaCapture", "MediaCaptureAppleRendering"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
