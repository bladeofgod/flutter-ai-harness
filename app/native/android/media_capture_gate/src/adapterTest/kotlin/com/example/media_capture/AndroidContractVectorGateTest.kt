package com.example.media_capture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaType
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
    fun wireV3CrossRuntimeGoldenMatchesAndroidCodecAndEverySection() {
        val wire = contract("media-capture.wire.json")
        val golden = contract("media-capture-v4-v3.golden.json")
        assertEquals(
            setOf(
                "schemaVersion",
                "contractId",
                "consumerBindings",
                "generation",
                "current",
                "history",
                "transfer",
                "lifecycle",
                "redaction",
            ),
            golden.keys().asSequence().toSet(),
        )
        val generation = golden.getJSONObject("generation")
        assertEquals(
            setOf(
                "generatorVersion",
                "normalizedDescriptorDigest",
                "wireVersion",
                "methodCount",
                "eventCount",
                "resultTypeCount",
                "failureTypeCount",
                "errorCount",
                "payloadDescriptorCount",
                "fieldDescriptorCount",
                "contractImplementationDigest",
                "outputImplementationDigests",
            ),
            generation.keys().asSequence().toSet(),
        )
        val generated = wire.getJSONObject("codeGeneration").getJSONObject("generated")
        assertEquals(1, generation.getInt("generatorVersion"))
        assertEquals(wire.getInt("wireVersion"), generation.getInt("wireVersion"))
        assertEquals(generated.getJSONArray("methodIds").length(), generation.getInt("methodCount"))
        assertEquals(generated.getJSONArray("eventIds").length(), generation.getInt("eventCount"))
        assertEquals(generated.getJSONArray("resultTypeIds").length(), generation.getInt("resultTypeCount"))
        assertEquals(generated.getJSONArray("failureTypeIds").length(), generation.getInt("failureTypeCount"))
        assertEquals(generated.getJSONArray("errorCodes").length(), generation.getInt("errorCount"))
        assertEquals(generated.getJSONArray("payloadIds").length(), generation.getInt("payloadDescriptorCount"))
        assertEquals(generated.getJSONArray("fieldIds").length(), generation.getInt("fieldDescriptorCount"))
        val current = golden.getJSONObject("current")
        assertEquals(4, current.getInt("capabilityVersion"))
        assertEquals(MEDIA_CAPTURE_WIRE_VERSION, current.getInt("wireVersion"))
        assertEquals(MediaCaptureWireCodec.methods, current.getJSONArray("methodIds").strings())
        assertEquals(
            setOf("session_ready", "session_failed", "media_preview_ready", "media_lease_expired", "media_read_revoked"),
            current.getJSONArray("eventIds").strings(),
        )
        assertEquals(operationMethods.keys, current.getJSONArray("capabilityOperationIds").strings())
        assertEquals(
            setOf(
                "session_ready",
                "session_failed",
                "media_preview_ready",
                "media_lease_expired",
                "media_read_revoked",
                "render_attachment_revoked",
            ),
            current.getJSONArray("capabilityEventIds").strings(),
        )
        val capabilityFailures = FailureCode.entries.map { it.wireValue }.toSet()
        val mappedCapabilityFailures = current.getJSONArray("mappedCapabilityFailureIds").strings()
        val wireProtocolFailures = current.getJSONArray("wireProtocolFailureIds").strings()
        val wireFailures = current.getJSONArray("failureIds").strings()
        assertEquals(capabilityFailures, current.getJSONArray("capabilityFailureIds").strings())
        assertEquals(
            capabilityFailures - setOf("attachment_generation_retired", "attachment_target_conflict"),
            mappedCapabilityFailures,
        )
        assertEquals(wireFailures - mappedCapabilityFailures, wireProtocolFailures)
        val contractFailures = wire.getJSONArray("errors").objects()
        assertEquals(contractFailures.map { it.getString("code") }.toSet(), wireFailures)
        assertEquals(
            contractFailures.filter { it.getString("source") == "capability_failure" }
                .map { it.getString("code") }.toSet(),
            mappedCapabilityFailures,
        )
        assertEquals(
            contractFailures.filter { it.getString("source") == "wire_protocol" }
                .map { it.getString("code") }.toSet(),
            wireProtocolFailures,
        )

        val history = golden.getJSONObject("history")
        assertEquals(
            listOf(
                "1|13|5|true|none|false",
                "2|18|6|true|callback_adapter|false",
                "3|18|6|true|module_concrete_surface|false",
                "4|19|6|true|module_concrete_surface|true",
            ),
            history.getJSONArray("capability").objects().map {
                listOf(
                    it.getInt("version"),
                    it.getInt("operationCount"),
                    it.getInt("eventCount"),
                    it.getBoolean("nativeReadScope"),
                    it.getString("nativeRenderScope"),
                    it.getBoolean("boundedExport"),
                ).joinToString("|")
            },
        )
        assertEquals(
            listOf(
                "1|1|12|5|false|false|false",
                "2|2,3|14|5|false|false|false",
                "3|4|17|5|false|false|true",
            ),
            history.getJSONArray("wire").objects().map {
                listOf(
                    it.getInt("version"),
                    it.getJSONArray("compatibleCapabilityVersions").ints().sorted().joinToString(","),
                    it.getInt("methodCount"),
                    it.getInt("eventCount"),
                    it.getBoolean("exposesNativeRead"),
                    it.getBoolean("exposesNativeRender"),
                    it.getBoolean("exposesTransfer"),
                ).joinToString("|")
            },
        )

        val transfer = wire.getJSONObject("transferStore")
        val limits = transfer.getJSONObject("limits")
        val goldenLimits = golden.getJSONObject("transfer").getJSONObject("limits")
        listOf(
            "maxFileBytes",
            "ttlSeconds",
            "maxActiveExportsPerEngineAttachment",
            "maxActiveBytesPerEngineAttachment",
            "releaseTombstoneSeconds",
            "maxReleaseTombstones",
        ).forEach { key -> assertEquals(limits.getLong(key), goldenLimits.getLong(key), key) }

        golden.getJSONObject("transfer").getJSONArray("mimeCases").objects().forEachIndexed { index, vector ->
            val mediaType = if (vector.getString("mediaType") == "photo") MediaType.PHOTO else MediaType.VIDEO
            val metadata =
                MediaMetadata(
                    mediaType = mediaType,
                    pixelWidth = 1,
                    pixelHeight = 1,
                    durationMillis = if (mediaType == MediaType.VIDEO) 1_000L else null,
                    orientationDegrees = 0,
                    byteLength = 1_024L,
                    contentType = vector.getString("contentType"),
                )
            val encode = {
                MediaCaptureWireCodec.materializedMedia(
                    requestId = "mime-$index",
                    exportHandle = "ABCDEFGHIJKLMNOPQRSTUV",
                    fileUri = "file:///data/user/0/app/cache/media-transfer/a.bin",
                    metadata = metadata,
                    expiresAtEpochMillis = 301_000L,
                )
            }
            if (vector.getBoolean("valid")) encode() else assertFails { encode() }
        }
        golden.getJSONObject("transfer").getJSONArray("signed64Cases").objects().forEach { vector ->
            assertEquals(vector.getBoolean("valid"), vector.getString("decimal").toLongOrNull() != null)
        }

        val contractVectors = transfer.getJSONArray("fileUriGoldenVectors").objects()
        val goldenVectors = golden.getJSONObject("transfer").getJSONArray("fileUriCases").objects()
        assertEquals(
            contractVectors.map { Triple(it.getString("id"), it.getString("uri"), it.getBoolean("valid")) },
            goldenVectors.map { Triple(it.getString("id"), it.getString("uri"), it.getBoolean("valid")) },
        )
        goldenVectors.forEach { vector ->
            val uri = vector.getString("uri")
            if (vector.getBoolean("valid")) {
                MediaCaptureWireCodec.requireCanonicalFileUri(uri)
            } else {
                assertFails { MediaCaptureWireCodec.requireCanonicalFileUri(uri) }
            }
        }
        val lengths = transfer.getJSONArray("fileUriLengthGoldenVectors").objects()
        assertEquals(
            lengths.map { it.getInt("totalLength") to it.getBoolean("valid") },
            golden.getJSONObject("transfer").getJSONArray("fileUriLengthCases").objects()
                .map { it.getInt("totalLength") to it.getBoolean("valid") },
        )
        val maximum = "file:///" + "a".repeat(lengths.single { it.getBoolean("valid") }.getInt("totalLength") - 8)
        MediaCaptureWireCodec.requireCanonicalFileUri(maximum)
        assertFails { MediaCaptureWireCodec.requireCanonicalFileUri("${maximum}a") }

        val lifecycle = golden.getJSONObject("lifecycle")
        assertEquals(
            listOf("import_store_commit", "release_transfer", "release_source_lease"),
            lifecycle.getJSONArray("cleanupOrder").stringsInOrder(),
        )
        assertEquals("cleanup_without_delivery", lifecycle.getString("lateCompletion"))
        assertEquals("delete_transfer_before_boundary_completion", lifecycle.getString("engineDetach"))
        assertEquals("idempotent_success", lifecycle.getString("releaseAfterTombstone"))
        val redaction = golden.getJSONObject("redaction")
        assertEquals(
            setOf("fileUri", "mediaHandle", "exportHandle", "absolutePath"),
            redaction.getJSONArray("forbiddenPersistentKeys").strings(),
        )
        assertEquals(false, redaction.getBoolean("failureDetailsMayContainLocator"))
        assertEquals(false, redaction.getBoolean("logsMayContainLocator"))
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

private fun JSONArray.stringsInOrder(): List<String> =
    (0 until length()).map(::getString)

private fun JSONArray.ints(): Set<Int> =
    (0 until length()).map(::getInt).toSet()

private fun JSONArray.machineItems(machineId: String): Set<String> =
    objects().single { it.getString("id") == machineId }.getJSONArray("items").ids()
