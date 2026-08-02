// swift-tools-version: 5.9

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let mediaCapturePackage = packageDirectory
    .appendingPathComponent("../../../../native/ios/MediaCapture")
    .standardizedFileURL.path
let mediaCaptureUiPackage = packageDirectory
    .appendingPathComponent("../../../../native/ios/MediaCaptureUI")
    .standardizedFileURL.path

let package = Package(
    name: "app_media_capture_bridge_core_tests",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "MediaCaptureBridgeCore", targets: ["MediaCaptureBridgeCore"]),
    ],
    dependencies: [
        .package(path: mediaCapturePackage),
        .package(path: mediaCaptureUiPackage),
    ],
    targets: [
        .target(
            name: "MediaCaptureBridgeCore",
            dependencies: [
                .product(name: "MediaCapture", package: "MediaCapture"),
                .product(name: "MediaCaptureUI", package: "MediaCaptureUI"),
            ]
        ),
        .testTarget(
            name: "MediaCaptureBridgeCoreTests",
            dependencies: [
                "MediaCaptureBridgeCore",
                .product(name: "MediaCapture", package: "MediaCapture"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
