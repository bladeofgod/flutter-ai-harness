package com.example.media_capture

import com.example.mediacapture.api.SessionHandle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class MediaCaptureWireCodecTest {
    @Test
    fun decodesAllDeclaredMethodPayloads() {
        val cases =
            mapOf(
                "start_session" to startPayload(),
                "present_capture_flow" to startPayload(),
                "dismiss_capture_flow" to
                    mapOf("presentationRequestId" to "presentation-request-1"),
                "take_photo" to sessionPayload(),
                "start_recording" to sessionPayload(),
                "stop_recording" to sessionPayload(),
                "switch_camera" to sessionPayload(),
                "cancel" to sessionPayload(),
                "set_flash_mode" to mapOf("sessionHandle" to "session-1", "flashMode" to "auto"),
                "set_focus_point" to
                    mapOf("sessionHandle" to "session-1", "normalizedX" to 0.25, "normalizedY" to 0.75),
                "set_zoom" to mapOf("sessionHandle" to "session-1", "zoomFactor" to 2.0),
                "retake" to mediaPayload(),
                "confirm" to mediaPayload(),
                "release_media" to mediaPayload(),
                "read_media_thumbnail" to mapOf("mediaHandle" to "media-1", "maxPixelEdge" to 128),
                "materialize_media_resource" to mediaPayload(),
                "release_materialized_media" to
                    mapOf("exportHandle" to "abcdefghijklmnopqrstuv"),
            )

        cases.forEach { (method, payload) ->
            val request = MediaCaptureWireCodec.decodeRequest(method, envelope("request-$method", payload))
            assertEquals(method, request.operation)
            assertEquals("request-$method", request.requestId)
        }
        assertEquals(MediaCaptureWireCodec.methods, cases.keys)
    }

    @Test
    fun rejectsMalformedAndHostileInputWithClosedDetails() {
        val malformed =
            listOf(
                envelope("request-1", startPayload()) + ("unknown" to true),
                mapOf("wireVersion" to 3, "requestId" to "request-1"),
                envelope("bad id", startPayload()),
                envelope("request-1", startPayload() + ("unknown" to true)),
                envelope("request-1", startPayload() + ("maxVideoDurationMillis" to 60_001)),
                envelope("request-1", startPayload() + ("enabledMediaTypes" to listOf("photo", "photo"))),
            )

        malformed.forEach { value ->
            val failure =
                assertFailsWith<MediaCaptureWireFailure> {
                    MediaCaptureWireCodec.decodeRequest("start_session", value)
                }
            assertEquals("invalid_wire_payload", failure.code)
            assertEquals(
                setOf("operation", "field", "reason"),
                failure.details.keys,
            )
            assertEquals(false, failure.details.values.any { it.toString().contains("bad id") })
        }
    }

    @Test
    fun rejectsWrongVersionAndStrictDoublesWhileKeepingHandlesOpaque() {
        val wrongVersion =
            assertFailsWith<MediaCaptureWireFailure> {
                MediaCaptureWireCodec.decodeRequest(
                    "start_session",
                    envelope("request-1", startPayload(), version = 1),
                )
            }
        assertEquals("incompatible_wire_version", wrongVersion.code)

        val integerFocus =
            assertFailsWith<MediaCaptureWireFailure> {
                MediaCaptureWireCodec.decodeRequest(
                    "set_focus_point",
                    envelope(
                        "request-2",
                        mapOf("sessionHandle" to "session-1", "normalizedX" to 0, "normalizedY" to 1.0),
                    ),
                )
            }
        assertEquals("type_mismatch", integerFocus.details["reason"])

        val opaque =
            MediaCaptureWireCodec.decodeRequest(
                "cancel",
                envelope("request-3", mapOf("sessionHandle" to "provider://camera/session.1")),
            )
        assertEquals("provider://camera/session.1", (opaque.payload as MediaCaptureWirePayload.SessionAction).sessionHandle.value)
        assertEquals(
            "provider://camera/session.1",
            (MediaCaptureWireCodec.sessionCreated(
                "request-output",
                SessionHandle("provider://camera/session.1"),
            )["payload"] as Map<*, *>)["sessionHandle"],
        )

        listOf("", "x".repeat(129)).forEach { handle ->
            val invalidHandle =
                assertFailsWith<MediaCaptureWireFailure> {
                    MediaCaptureWireCodec.decodeRequest(
                        "cancel",
                        envelope("request-4", mapOf("sessionHandle" to handle)),
                    )
                }
            assertEquals("out_of_range", invalidHandle.details["reason"])
        }
    }

    @Test
    fun listenEnvelopeIsStrictAndVersioned() {
        MediaCaptureWireCodec.decodeListenArguments(mapOf("wireVersion" to 3))

        assertEquals(
            "invalid_wire_payload",
            assertFailsWith<MediaCaptureWireFailure> {
                MediaCaptureWireCodec.decodeListenArguments(
                    mapOf("wireVersion" to 3, "unknown" to true),
                )
            }.code,
        )
        assertEquals(
            "incompatible_wire_version",
            assertFailsWith<MediaCaptureWireFailure> {
                MediaCaptureWireCodec.decodeListenArguments(mapOf("wireVersion" to 1))
            }.code,
        )
    }

    @Test
    fun decodedPayloadTypesAreNativeModelsNotMaps() {
        assertIs<MediaCaptureWirePayload.StartSession>(
            MediaCaptureWireCodec.decodeRequest(
                "start_session",
                envelope("request-1", startPayload()),
            ).payload,
        )
        assertIs<MediaCaptureWirePayload.Thumbnail>(
            MediaCaptureWireCodec.decodeRequest(
                "read_media_thumbnail",
                envelope(
                    "request-2",
                    mapOf("mediaHandle" to "media-1", "maxPixelEdge" to 128),
                ),
            ).payload,
        )
    }
}

internal fun envelope(
    requestId: String,
    payload: Map<String, Any?>,
    version: Int = MEDIA_CAPTURE_WIRE_VERSION,
): Map<String, Any?> =
    mapOf("wireVersion" to version, "requestId" to requestId, "payload" to payload)

internal fun startPayload(): Map<String, Any?> =
    mapOf(
        "enabledMediaTypes" to listOf("photo", "video"),
        "preferredCamera" to "rear",
        "audioEnabled" to true,
        "maxVideoDurationMillis" to 60_000,
    )

internal fun sessionPayload(handle: String = "session-1"): Map<String, Any?> =
    mapOf("sessionHandle" to handle)

internal fun mediaPayload(handle: String = "media-1"): Map<String, Any?> =
    mapOf("mediaHandle" to handle)
