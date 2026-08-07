import Foundation
import MediaCapture
import UIKit
import XCTest
@testable import MediaCaptureBridgeCore

final class MediaCaptureWireCodecTests: XCTestCase {
    func testGeneratedWireDescriptorsDriveTheRuntimeSurface() throws {
        XCTAssertEqual(generatedMediaCaptureWireVersion, mediaCaptureWireVersion)
        XCTAssertEqual(generatedCommandsChannel, mediaCaptureCommandsChannel)
        XCTAssertEqual(generatedEventsChannel, mediaCaptureEventsChannel)
        XCTAssertEqual(GeneratedMediaCaptureWireMethod.allCases.count, 17)
        XCTAssertEqual(GeneratedMediaCaptureWireEvent.allCases.count, 5)
        XCTAssertEqual(
            Set(GeneratedMediaCaptureWireMethod.allCases.map(\.rawValue)),
            MediaCaptureWireCodec.methods
        )
        XCTAssertEqual(
            MediaCaptureWireCodec.generatedPayloadDescriptorCoverage,
            Set(generatedPayloadDescriptors.map(\.id))
        )
        XCTAssertEqual(
            Set(GeneratedMediaCaptureWireError.allCases.map(\.rawValue)),
            Set(generatedErrorDescriptors.map(\.code))
        )
        let boolField = try XCTUnwrap(
            generatedMediaCaptureWireFields.first { $0.id == "audio_enabled" }
        )
        XCTAssertTrue(generatedMatchesWireFieldPrimitive(NSNumber(value: true), field: boolField))
        XCTAssertFalse(generatedMatchesWireFieldPrimitive(NSNumber(value: 1), field: boolField))
    }

    func testOpaqueOutputHandleUsesWireLengthWithoutRequestIdAsciiPattern() {
        XCTAssertTrue(MediaCaptureWireCodec.isOpaqueHandle("媒体句柄_1"))
        XCTAssertTrue(MediaCaptureWireCodec.isOpaqueHandle(String(repeating: "a", count: 128)))
        XCTAssertFalse(MediaCaptureWireCodec.isOpaqueHandle(""))
        XCTAssertFalse(MediaCaptureWireCodec.isOpaqueHandle(String(repeating: "a", count: 129)))
    }

    func testOwnerResolverRejectsWrongEngineInvisibleAndAmbiguousWindows() {
        let first = NSObject()
        let second = NSObject()
        let firstIdentity = ObjectIdentifier(first)
        let secondIdentity = ObjectIdentifier(second)

        XCTAssertEqual(
            MediaCaptureOwnerResolver.uniqueForegroundOwner([
                MediaCaptureOwnerCandidate(
                    identity: firstIdentity,
                    isForeground: true,
                    isVisible: true,
                    belongsToCurrentEngine: true
                ),
                MediaCaptureOwnerCandidate(
                    identity: secondIdentity,
                    isForeground: true,
                    isVisible: true,
                    belongsToCurrentEngine: false
                ),
            ]),
            firstIdentity
        )
        XCTAssertNil(
            MediaCaptureOwnerResolver.uniqueForegroundOwner([
                MediaCaptureOwnerCandidate(
                    identity: firstIdentity,
                    isForeground: true,
                    isVisible: true,
                    belongsToCurrentEngine: true
                ),
                MediaCaptureOwnerCandidate(
                    identity: secondIdentity,
                    isForeground: true,
                    isVisible: true,
                    belongsToCurrentEngine: true
                ),
            ])
        )
        XCTAssertNil(
            MediaCaptureOwnerResolver.uniqueForegroundOwner([
                MediaCaptureOwnerCandidate(
                    identity: firstIdentity,
                    isForeground: true,
                    isVisible: false,
                    belongsToCurrentEngine: true
                ),
            ])
        )
        XCTAssertTrue(
            MediaCaptureOwnerResolver.isTrackedOwnerAlive(
                firstIdentity,
                candidates: [
                    MediaCaptureOwnerCandidate(
                        identity: firstIdentity,
                        isForeground: false,
                        isVisible: true,
                        belongsToCurrentEngine: true
                    ),
                ]
            )
        )
        XCTAssertFalse(
            MediaCaptureOwnerResolver.isTrackedOwnerAlive(
                firstIdentity,
                candidates: [
                    MediaCaptureOwnerCandidate(
                        identity: firstIdentity,
                        isForeground: true,
                        isVisible: false,
                        belongsToCurrentEngine: true
                    ),
                ]
            )
        )
    }

    @MainActor
    func testViewControllerHierarchyRejectsDetachedAndReplacedEngineOwner() {
        let root = UIViewController()
        let engineOwner = UIViewController()
        root.addChild(engineOwner)
        engineOwner.didMove(toParent: root)

        XCTAssertTrue(
            MediaCaptureViewControllerHierarchy.contains(root) { $0 === engineOwner }
        )

        engineOwner.willMove(toParent: nil)
        engineOwner.removeFromParent()
        XCTAssertFalse(
            MediaCaptureViewControllerHierarchy.contains(root) { $0 === engineOwner }
        )

        let replacementRoot = UIViewController()
        XCTAssertFalse(
            MediaCaptureViewControllerHierarchy.contains(replacementRoot) { $0 === engineOwner }
        )
    }

    func testDecodesEveryBaseOperation() throws {
        let values: [(String, [String: Any])] = [
            ("start_session", startPayload()),
            ("take_photo", sessionPayload("session_1")),
            ("start_recording", sessionPayload("session_1")),
            ("stop_recording", sessionPayload("session_1")),
            ("switch_camera", sessionPayload("session_1")),
            ("set_flash_mode", ["sessionHandle": "session_1", "flashMode": "auto"]),
            (
                "set_focus_point",
                ["sessionHandle": "session_1", "normalizedX": 0.25, "normalizedY": 0.75]
            ),
            ("set_zoom", ["sessionHandle": "session_1", "zoomFactor": 2.0]),
            ("retake", mediaPayload("media_1")),
            ("confirm", mediaPayload("media_1")),
            ("cancel", sessionPayload("session_1")),
            ("release_media", mediaPayload("media_1")),
            ("read_media_thumbnail", ["mediaHandle": "media_1", "maxPixelEdge": 128]),
            ("present_capture_flow", startPayload()),
            ("dismiss_capture_flow", ["presentationRequestId": "present_1"]),
            ("materialize_media_resource", mediaPayload("media_1")),
            ("release_materialized_media", ["exportHandle": "ABCDEFGHIJKLMNOPQRSTUV"]),
        ]

        for (index, value) in values.enumerated() {
            XCTAssertNoThrow(
                try MediaCaptureWireCodec.decodeRequest(
                    operation: value.0,
                    arguments: requestEnvelope(requestId: "request_\(index)", payload: value.1)
                ),
                value.0
            )
        }
    }

    func testMaterializedResultIsClosedAndUsesSignedWireValues() throws {
        let value = try MediaCaptureWireCodec.materializedMedia(
            requestId: "materialized_result",
            exportHandle: "ABCDEFGHIJKLMNOPQRSTUV",
            fileURI: "file:///var/mobile/Containers/Data/Application/app/Library/Caches/media/a.jpg",
            metadata: try media(handle: "media_1", type: .photo, durationMilliseconds: nil),
            expiresAtEpochMilliseconds: 301_000
        )
        let payload = try XCTUnwrap(value["payload"] as? [String: Any])

        XCTAssertEqual(Set(payload.keys), [
            "exportHandle", "fileUri", "mediaType", "contentType", "byteLength",
            "durationMillis", "expiresAt",
        ])
        XCTAssertEqual(payload["contentType"] as? String, "image/jpeg")
        XCTAssertEqual(payload["byteLength"] as? Int64, 4_096)
        XCTAssertEqual(payload["expiresAt"] as? Int64, 301_000)
        XCTAssertTrue(payload["durationMillis"] is NSNull)
        XCTAssertEqual(
            try MediaCaptureWireCodec.materializedMediaReleased(requestId: "released")["resultType"]
                as? String,
            "materialized_media_released"
        )
    }

    func testCanonicalFileURIMatchesSharedGoldenVectors() throws {
        let vectors: [(String, Bool)] = [
            ("file:///var/mobile/Containers/Data/Application/app/Library/Caches/media-transfer/a.bin", true),
            ("file://localhost/var/mobile/Containers/Data/Application/app/Library/Caches/media-transfer/a.bin", false),
            ("file:media-transfer/a.bin", false),
            ("file:/data/user/0/app/cache/media-transfer/a.bin", false),
            ("file://:123/data/user/0/app/cache/media-transfer/a.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/../a.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/%2E%2E/a.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/a.bin?x=1", false),
            ("file:///data/user/0/app/cache/media-transfer/a.bin#x", false),
            ("file://user@/data/user/0/app/cache/media-transfer/a.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/%C0%AF.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/%GG.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/a%2Fb.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/a%5Cb.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/a%00.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/a%0A.bin", false),
            ("file:///data/user/0/app/cache/media-transfer/照片.jpg", false),
            ("file:///data/user/0/app/cache/media-transfer/%E7%85%A7%E7%89%87.jpg", true),
        ]
        let golden = try crossRuntimeGolden()
        XCTAssertEqual(Set(golden.keys), [
            "schemaVersion", "contractId", "consumerBindings", "generation", "current", "history",
            "transfer", "lifecycle", "redaction",
        ])
        let generation = try XCTUnwrap(golden["generation"] as? [String: Any])
        XCTAssertEqual(Set(generation.keys), [
            "generatorVersion", "normalizedDescriptorDigest", "wireVersion", "methodCount", "eventCount",
            "resultTypeCount", "failureTypeCount", "errorCount", "payloadDescriptorCount",
            "fieldDescriptorCount", "contractImplementationDigest", "outputImplementationDigests",
        ])
        XCTAssertEqual(generation["generatorVersion"] as? Int, 1)
        XCTAssertEqual(generation["normalizedDescriptorDigest"] as? String,
                       "76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27")
        XCTAssertEqual(generation["wireVersion"] as? Int, generatedMediaCaptureWireVersion)
        XCTAssertEqual(generation["methodCount"] as? Int, GeneratedMediaCaptureWireMethod.allCases.count)
        XCTAssertEqual(generation["eventCount"] as? Int, GeneratedMediaCaptureWireEvent.allCases.count)
        XCTAssertEqual(generation["resultTypeCount"] as? Int, GeneratedMediaCaptureWireResult.allCases.count)
        XCTAssertEqual(generation["failureTypeCount"] as? Int, GeneratedMediaCaptureWireFailure.allCases.count)
        XCTAssertEqual(generation["errorCount"] as? Int, GeneratedMediaCaptureWireError.allCases.count)
        XCTAssertEqual(generation["payloadDescriptorCount"] as? Int, generatedPayloadDescriptors.count)
        XCTAssertEqual(generation["fieldDescriptorCount"] as? Int, generatedMediaCaptureWireFields.count)
        let current = try XCTUnwrap(golden["current"] as? [String: Any])
        XCTAssertEqual(current["capabilityVersion"] as? Int, 4)
        XCTAssertEqual(current["wireVersion"] as? Int, 3)
        XCTAssertEqual(
            Set(try XCTUnwrap(current["methodIds"] as? [String])),
            MediaCaptureWireCodec.methods
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(current["eventIds"] as? [String])),
            [
                "session_ready", "session_failed", "media_preview_ready", "media_lease_expired",
                "media_read_revoked",
            ]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(current["capabilityOperationIds"] as? [String])),
            [
                "start_session", "take_photo", "start_recording", "stop_recording",
                "switch_camera", "set_flash_mode", "set_focus_point", "set_zoom", "retake",
                "confirm", "cancel", "open_media_read", "release_media", "attach_live_preview",
                "detach_live_preview", "attach_unconfirmed_preview_render",
                "detach_unconfirmed_preview_render", "read_media_thumbnail",
                "copy_confirmed_media_to_sink",
            ]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(current["capabilityEventIds"] as? [String])),
            [
                "session_ready", "session_failed", "media_preview_ready", "media_lease_expired",
                "media_read_revoked", "render_attachment_revoked",
            ]
        )
        let capabilityFailures = Set([
            MediaCaptureFailure.ID.permissionDenied.rawValue,
            MediaCaptureFailure.ID.permissionRestricted.rawValue,
            MediaCaptureFailure.ID.permissionPermanentlyDenied.rawValue,
            MediaCaptureFailure.ID.resourceInUse.rawValue,
            MediaCaptureFailure.ID.storageFull.rawValue,
            MediaCaptureFailure.ID.encodingFailed.rawValue,
            MediaCaptureFailure.ID.mediaInvalid.rawValue,
            MediaCaptureFailure.ID.sessionInvalid.rawValue,
            MediaCaptureFailure.ID.unsupportedCapability.rawValue,
            MediaCaptureFailure.ID.systemInterrupted.rawValue,
            MediaCaptureFailure.ID.sessionConflict.rawValue,
            MediaCaptureFailure.ID.invalidState.rawValue,
            MediaCaptureFailure.ID.invalidArgument.rawValue,
            MediaCaptureFailure.ID.sessionTimeout.rawValue,
            MediaCaptureFailure.ID.thumbnailGenerationFailed.rawValue,
            MediaCaptureFailure.ID.thumbnailGenerationCancelled.rawValue,
            MediaCaptureFailure.ID.thumbnailOverloaded.rawValue,
            MediaCaptureFailure.ID.attachmentGenerationRetired.rawValue,
            MediaCaptureFailure.ID.attachmentTargetConflict.rawValue,
            MediaCaptureFailure.ID.mediaExportConflict.rawValue,
            MediaCaptureFailure.ID.mediaExportOverloaded.rawValue,
            MediaCaptureFailure.ID.mediaExportTooLarge.rawValue,
            MediaCaptureFailure.ID.mediaExportSinkRejected.rawValue,
            MediaCaptureFailure.ID.mediaExportReadFailed.rawValue,
            MediaCaptureFailure.ID.mediaExportWriteFailed.rawValue,
            MediaCaptureFailure.ID.mediaExportCancelled.rawValue,
            MediaCaptureFailure.ID.mediaExportTimedOut.rawValue,
        ])
        let mappedCapabilityFailures = Set(
            try XCTUnwrap(current["mappedCapabilityFailureIds"] as? [String])
        )
        let wireProtocolFailures = Set(
            try XCTUnwrap(current["wireProtocolFailureIds"] as? [String])
        )
        let wireFailures = Set(try XCTUnwrap(current["failureIds"] as? [String]))
        XCTAssertEqual(
            Set(try XCTUnwrap(current["capabilityFailureIds"] as? [String])),
            capabilityFailures
        )
        XCTAssertEqual(
            mappedCapabilityFailures,
            capabilityFailures.subtracting([
                MediaCaptureFailure.ID.attachmentGenerationRetired.rawValue,
                MediaCaptureFailure.ID.attachmentTargetConflict.rawValue,
            ])
        )
        XCTAssertEqual(wireProtocolFailures, wireFailures.subtracting(mappedCapabilityFailures))
        let transfer = try XCTUnwrap(golden["transfer"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(transfer["limits"] as? NSDictionary), [
            "maxFileBytes": 52_428_800,
            "ttlSeconds": 300,
            "maxActiveExportsPerEngineAttachment": 4,
            "maxActiveBytesPerEngineAttachment": 104_857_600,
            "releaseTombstoneSeconds": 300,
            "maxReleaseTombstones": 4_096,
        ])
        let mimeCases = try XCTUnwrap(transfer["mimeCases"] as? [[String: Any]])
        for (index, item) in mimeCases.enumerated() {
            let mediaType = try XCTUnwrap(item["mediaType"] as? String)
            let contentType = try XCTUnwrap(item["contentType"] as? String)
            let valid = try XCTUnwrap(item["valid"] as? Bool)
            let expectedContentType = mediaType == "photo" ? "image/jpeg" : "video/mp4"
            XCTAssertEqual(contentType == expectedContentType, valid, "mime case \(index)")
            if valid {
                let value = try MediaCaptureWireCodec.materializedMedia(
                    requestId: "mime_\(index)",
                    exportHandle: "ABCDEFGHIJKLMNOPQRSTUV",
                    fileURI: vectors[0].0,
                    metadata: try media(
                        handle: "media_\(index)",
                        type: mediaType == "photo" ? .photo : .video,
                        durationMilliseconds: mediaType == "photo" ? nil : 1_000
                    ),
                    expiresAtEpochMilliseconds: 301_000
                )
                let payload = try XCTUnwrap(value["payload"] as? [String: Any])
                XCTAssertEqual(payload["contentType"] as? String, contentType)
            }
        }
        for item in try XCTUnwrap(transfer["signed64Cases"] as? [[String: Any]]) {
            let decimal = try XCTUnwrap(item["decimal"] as? String)
            XCTAssertEqual(Int64(decimal) != nil, try XCTUnwrap(item["valid"] as? Bool), decimal)
        }
        let goldenCases = try XCTUnwrap(transfer["fileUriCases"] as? [[String: Any]])
        XCTAssertEqual(goldenCases.count, vectors.count)
        for (index, goldenCase) in goldenCases.enumerated() {
            XCTAssertEqual(goldenCase["uri"] as? String, vectors[index].0)
            XCTAssertEqual(goldenCase["valid"] as? Bool, vectors[index].1)
        }

        for (value, valid) in vectors {
            if valid {
                XCTAssertNoThrow(try MediaCaptureWireCodec.requireCanonicalFileURI(value), value)
            } else {
                XCTAssertThrowsError(try MediaCaptureWireCodec.requireCanonicalFileURI(value), value)
            }
        }
        let maximum = "file:///" + String(repeating: "a", count: 4_088)
        XCTAssertEqual(maximum.utf8.count, 4_096)
        XCTAssertNoThrow(try MediaCaptureWireCodec.requireCanonicalFileURI(maximum))
        XCTAssertThrowsError(try MediaCaptureWireCodec.requireCanonicalFileURI(maximum + "a"))
        XCTAssertEqual(
            try XCTUnwrap(transfer["fileUriLengthCases"] as? NSArray),
            [
                ["totalLength": 4_096, "valid": true],
                ["totalLength": 4_097, "valid": false],
            ]
        )

        let history = try XCTUnwrap(golden["history"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(history["capability"] as? NSArray), [
            [
                "version": 1, "operationCount": 13, "eventCount": 5,
                "nativeReadScope": true, "nativeRenderScope": "none", "boundedExport": false,
            ],
            [
                "version": 2, "operationCount": 18, "eventCount": 6,
                "nativeReadScope": true, "nativeRenderScope": "callback_adapter",
                "boundedExport": false,
            ],
            [
                "version": 3, "operationCount": 18, "eventCount": 6,
                "nativeReadScope": true, "nativeRenderScope": "module_concrete_surface",
                "boundedExport": false,
            ],
            [
                "version": 4, "operationCount": 19, "eventCount": 6,
                "nativeReadScope": true, "nativeRenderScope": "module_concrete_surface",
                "boundedExport": true,
            ],
        ])
        XCTAssertEqual(try XCTUnwrap(history["wire"] as? NSArray), [
            [
                "version": 1, "compatibleCapabilityVersions": [1], "methodCount": 12,
                "eventCount": 5, "exposesNativeRead": false, "exposesNativeRender": false,
                "exposesTransfer": false,
            ],
            [
                "version": 2, "compatibleCapabilityVersions": [2, 3], "methodCount": 14,
                "eventCount": 5, "exposesNativeRead": false, "exposesNativeRender": false,
                "exposesTransfer": false,
            ],
            [
                "version": 3, "compatibleCapabilityVersions": [4], "methodCount": 17,
                "eventCount": 5, "exposesNativeRead": false, "exposesNativeRender": false,
                "exposesTransfer": true,
            ],
        ])
        let lifecycle = try XCTUnwrap(golden["lifecycle"] as? [String: Any])
        XCTAssertEqual(
            try XCTUnwrap(lifecycle["cleanupOrder"] as? [String]),
            ["import_store_commit", "release_transfer", "release_source_lease"]
        )
        XCTAssertEqual(lifecycle["lateCompletion"] as? String, "cleanup_without_delivery")
        XCTAssertEqual(
            lifecycle["engineDetach"] as? String,
            "delete_transfer_before_boundary_completion"
        )
        XCTAssertEqual(lifecycle["releaseAfterTombstone"] as? String, "idempotent_success")
        let redaction = try XCTUnwrap(golden["redaction"] as? [String: Any])
        XCTAssertEqual(
            Set(try XCTUnwrap(redaction["forbiddenPersistentKeys"] as? [String])),
            Set(["fileUri", "mediaHandle", "exportHandle", "absolutePath"])
        )
        XCTAssertEqual(redaction["failureDetailsMayContainLocator"] as? Bool, false)
        XCTAssertEqual(redaction["logsMayContainLocator"] as? Bool, false)
    }

    func testRejectsMalformedAndMaliciousDictionariesWithoutEchoingValues() throws {
        let secret = "/private/user/photo.jpg"
        let cases: [(Any?, String)] = [
            (
                [
                    "wireVersion": 3,
                    "requestId": "request_1",
                    "payload": startPayload(),
                    "unexpected": secret,
                ],
                "unknown_field"
            ),
            ([1: secret], "type_mismatch"),
            (
                requestEnvelope(
                    requestId: "request_2",
                    payload: [
                        "enabledMediaTypes": ["photo", "photo"],
                        "preferredCamera": "rear",
                        "audioEnabled": true,
                        "maxVideoDurationMillis": 15_000,
                    ]
                ),
                "invalid_format"
            ),
            (
                requestEnvelope(
                    requestId: "request_3",
                    payload: ["sessionHandle": "session_1", "normalizedX": Double.nan, "normalizedY": 0.5]
                ),
                "non_finite"
            ),
        ]

        for value in cases {
            do {
                _ = try MediaCaptureWireCodec.decodeRequest(
                    operation: value.1 == "non_finite" ? "set_focus_point" : "start_session",
                    arguments: value.0
                )
                XCTFail("Expected malformed payload to fail")
            } catch let failure as MediaCaptureWireFailure {
                XCTAssertEqual(failure.code, "invalid_wire_payload")
                XCTAssertFalse(failure.details.values.contains(secret))
                XCTAssertTrue(failure.details.values.contains(value.1))
            }
        }
    }

    func testEncodesEveryEventAndRedactsUnsupportedFailure() throws {
        let session = try SessionHandle(rawValue: "session_1")
        let photo = try media(handle: "photo_1", type: .photo, durationMilliseconds: nil)
        let events: [(MediaCaptureEvent, String)] = [
            (
                .sessionReady(
                    SessionReadySnapshot(
                        sessionHandle: session,
                        activeCamera: .rear,
                        availableCameras: [.rear, .front],
                        switchCameraSupported: true,
                        supportedFlashModes: [.off, .auto],
                        focusPointSupported: true,
                        minimumZoomFactor: 1,
                        maximumZoomFactor: 4
                    )
                ),
                "session_ready"
            ),
            (.sessionFailed(sessionHandle: session, failure: MediaCaptureFailure(.permissionDenied)), "session_failed"),
            (.sessionFailed(sessionHandle: session, failure: MediaCaptureFailure(.sessionTimeout)), "session_timeout"),
            (.mediaPreviewReady(sessionHandle: session, metadata: photo), "media_preview_ready"),
            (.mediaLeaseExpired(photo.mediaHandle), "media_lease_expired"),
            (.mediaReadRevoked(photo.mediaHandle), "media_read_revoked"),
        ]

        for value in events {
            let encoded = try XCTUnwrap(MediaCaptureWireCodec.event(value.0))
            XCTAssertEqual(encoded["eventType"] as? String ?? encoded["failureType"] as? String, value.1)
        }
        let failure = MediaCaptureWireCodec.capabilityFailure(
            operation: "take_photo",
            failure: MediaCaptureFailure(.mediaExportReadFailed)
        )
        XCTAssertEqual(failure.code, "wire_encoding_failed")
        XCTAssertEqual(Set(failure.details.keys), ["operation", "field", "reason"])
    }

    func testThumbnailRequiresBoundedSanitizedJpeg() throws {
        let handle = try MediaHandle(rawValue: "photo_1")
        let valid = MediaCaptureThumbnailValue(
            mediaHandle: handle,
            data: sanitizedJpeg(),
            pixelWidth: 2,
            pixelHeight: 2,
            mediaType: .photo,
            posterFrameMilliseconds: nil,
            contentType: "image/jpeg",
            orientationDegrees: 0
        )
        let encoded = try MediaCaptureWireCodec.thumbnail(
            requestId: "thumbnail_1",
            value: valid,
            maxPixelEdge: 64
        )
        let payload = try XCTUnwrap(encoded["payload"] as? [String: Any])
        XCTAssertEqual(
            (payload["thumbnailCopy"] as? MediaCaptureWireBytes)?.copyData(),
            sanitizedJpeg()
        )

        let invalid = MediaCaptureThumbnailValue(
            mediaHandle: handle,
            data: Data(repeating: 0, count: 524_289),
            pixelWidth: 2,
            pixelHeight: 2,
            mediaType: .photo,
            posterFrameMilliseconds: nil,
            contentType: "image/jpeg",
            orientationDegrees: 0
        )
        XCTAssertThrowsError(
            try MediaCaptureWireCodec.thumbnail(
                requestId: "thumbnail_2",
                value: invalid,
                maxPixelEdge: 64
            )
        ) { error in
            XCTAssertEqual((error as? MediaCaptureWireFailure)?.code, "wire_encoding_failed")
        }
    }

    private func crossRuntimeGolden() throws -> [String: Any] {
        let pluginRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = pluginRoot
            .appendingPathComponent("test", isDirectory: true)
            .appendingPathComponent("contracts", isDirectory: true)
            .appendingPathComponent("media-capture-v4-v3.golden.json")
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        return try XCTUnwrap(value as? [String: Any])
    }
}
