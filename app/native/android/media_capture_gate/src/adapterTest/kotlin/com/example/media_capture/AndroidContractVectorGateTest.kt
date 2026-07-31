package com.example.media_capture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionState
import com.example.mediacapture.rendering.MediaCaptureRenderView
import com.example.mediacapture.ui.MediaCaptureUiConfig
import java.nio.charset.StandardCharsets
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.json.JSONArray
import org.json.JSONObject

class AndroidContractVectorGateTest {
    @Test
    fun capabilityV4MatchesAndroidCoreAndNativeUiSurface() {
        val capability = contract("media-capture.capability.json")
        assertEquals("media_capture", capability.getString("contractId"))
        assertEquals(4, capability.getInt("capabilityVersion"))
        assertTrue(capability.getJSONObject("platform").getJSONArray("supported").strings().contains("android"))

        val capabilityOperations = capability.getJSONArray("operation").ids()
        assertEquals(operationMethods.keys, capabilityOperations)
        val publicMethods = MediaCapture::class.java.methods.map { it.name.substringBefore('-') }.toSet()
        operationMethods.forEach { (operation, method) ->
            assertTrue(method in publicMethods, "$operation must map to MediaCapture.$method")
        }

        assertEquals(
            FailureCode.entries.map { it.wireValue }.toSet(),
            capability.getJSONArray("failure").ids(),
        )
        val stateMachines = capability.getJSONArray("stateMachines")
        val sessionStates = stateMachines.machineItems("session") - "idle"
        val mediaStates = stateMachines.machineItems("media")
        assertEquals(SessionState.entries.map { it.name.lowercase() }.toSet(), sessionStates)
        assertEquals(MediaState.entries.map { it.name.lowercase() }.toSet(), mediaStates)

        assertEquals(60_000L, MediaCaptureUiConfig().toSessionOptions().maxVideoDurationMillis)
        assertTrue(
            MediaCapture::class.java.methods.any {
                it.returnType == MediaCaptureRenderView::class.java ||
                    it.parameterTypes.contains(MediaCaptureRenderView::class.java)
            },
        )
    }

    @Test
    fun wireV3MatchesAdapterMethodsEventsFailuresAndBounds() {
        val capability = contract("media-capture.capability.json")
        val wire = contract("media-capture.wire.json")
        assertEquals("media_capture_wire", wire.getString("contractId"))
        assertEquals(3, wire.getInt("wireVersion"))
        assertEquals(setOf(4), wire.getJSONObject("capability").getJSONArray("compatibleCapabilityVersions").ints())
        assertEquals(MediaCaptureWireCodec.methods, wire.getJSONArray("methods").ids())

        val wireEvents = wire.getJSONArray("events").ids()
        assertEquals(
            setOf("session_ready", "session_failed", "media_preview_ready", "media_lease_expired", "media_read_revoked"),
            wireEvents,
        )
        assertTrue(capability.getJSONArray("event").ids().containsAll(wireEvents))

        val capabilityErrors =
            wire.getJSONArray("errors").objects()
                .filter { it.getString("source") == "capability_failure" }
                .map { it.getString("code") }
                .toSet()
        val nativeOnlyFailures =
            setOf("attachment_generation_retired", "attachment_target_conflict")
        assertEquals(
            FailureCode.entries.map { it.wireValue }.toSet() - nativeOnlyFailures,
            capabilityErrors,
        )
        assertTrue(capability.getJSONArray("failure").ids().containsAll(nativeOnlyFailures))

        val channels = wire.getJSONArray("channels").objects().associate {
            it.getString("id") to it.getString("name")
        }
        assertEquals("com.example.media_capture.commands", channels.getValue("commands"))
        assertEquals("com.example.media_capture.events", channels.getValue("events"))

        val opaque = "x".repeat(128)
        val request = MediaCaptureWireCodec.decodeRequest("cancel", envelope("request-opaque", sessionPayload(opaque)))
        assertEquals(opaque, (request.payload as MediaCaptureWirePayload.SessionAction).sessionHandle.value)
        assertFails { SessionHandle("x".repeat(129)) }

        MediaCaptureWireCodec.decodeRequest(
            "read_media_thumbnail",
            envelope("request-min", mapOf("mediaHandle" to "media-1", "maxPixelEdge" to 64)),
        )
        MediaCaptureWireCodec.decodeRequest(
            "read_media_thumbnail",
            envelope("request-max", mapOf("mediaHandle" to "media-1", "maxPixelEdge" to 512)),
        )
        assertNotNull(MediaCaptureBridgePlugin())
    }

    @Test
    fun wireV3TransferVectorsMatchAndroidCodecAndLimits() {
        val wire = contract("media-capture.wire.json")
        val transfer = wire.getJSONObject("transferStore")
        val limits = transfer.getJSONObject("limits")
        assertEquals(52_428_800L, limits.getLong("maxFileBytes"))
        assertEquals(300, limits.getInt("ttlSeconds"))
        assertEquals(4, limits.getInt("maxActiveExportsPerEngineAttachment"))
        assertEquals(104_857_600L, limits.getLong("maxActiveBytesPerEngineAttachment"))

        transfer.getJSONArray("fileUriGoldenVectors").objects().forEach { vector ->
            val uri = vector.getString("uri")
            if (vector.getBoolean("valid")) {
                MediaCaptureWireCodec.requireCanonicalFileUri(uri)
            } else {
                assertFails { MediaCaptureWireCodec.requireCanonicalFileUri(uri) }
            }
        }
        val lengths = transfer.getJSONArray("fileUriLengthGoldenVectors").objects()
        val maximum = "file:///" + "a".repeat(lengths.single { it.getBoolean("valid") }.getInt("totalLength") - 8)
        MediaCaptureWireCodec.requireCanonicalFileUri(maximum)
        assertFails { MediaCaptureWireCodec.requireCanonicalFileUri("${maximum}a") }
    }

    private fun contract(name: String): JSONObject {
        val stream = assertNotNull(javaClass.classLoader?.getResourceAsStream(name), name)
        return stream.use {
            JSONObject(String(it.readBytes(), StandardCharsets.UTF_8))
        }
    }

    private companion object {
        val operationMethods =
            mapOf(
                "start_session" to "startSession",
                "take_photo" to "takePhoto",
                "start_recording" to "startRecording",
                "stop_recording" to "stopRecording",
                "switch_camera" to "switchCamera",
                "set_flash_mode" to "setFlashMode",
                "set_focus_point" to "setFocusPoint",
                "set_zoom" to "setZoom",
                "retake" to "retake",
                "confirm" to "confirm",
                "cancel" to "cancel",
                "open_media_read" to "withMediaRead",
                "release_media" to "releaseMedia",
                "attach_live_preview" to "attachLivePreview",
                "detach_live_preview" to "detachLivePreview",
                "attach_unconfirmed_preview_render" to "attachUnconfirmedPreview",
                "detach_unconfirmed_preview_render" to "detachUnconfirmedPreview",
                "read_media_thumbnail" to "readMediaThumbnail",
                "copy_confirmed_media_to_sink" to "copyConfirmedMediaToSink",
            )
    }
}

private fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).map(::getJSONObject)

private fun JSONArray.ids(): Set<String> = objects().map { it.getString("id") }.toSet()

private fun JSONArray.strings(): Set<String> =
    (0 until length()).map(::getString).toSet()

private fun JSONArray.ints(): Set<Int> =
    (0 until length()).map(::getInt).toSet()

private fun JSONArray.machineItems(machineId: String): Set<String> =
    objects().single { it.getString("id") == machineId }.getJSONArray("items").ids()
