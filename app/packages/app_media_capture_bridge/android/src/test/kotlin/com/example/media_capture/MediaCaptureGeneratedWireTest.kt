package com.example.media_capture

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MediaCaptureGeneratedWireTest {
    @Test
    fun generatedIdentifiersDriveTheRuntimeSurface() {
        assertEquals(17, GeneratedMediaCaptureWireMethod.entries.size)
        assertEquals(5, GeneratedMediaCaptureWireEvent.entries.size)
        assertEquals(
            GeneratedMediaCaptureWireMethod.entries.mapTo(linkedSetOf()) { it.wireValue },
            MediaCaptureWireCodec.methods,
        )
        assertEquals(
            GeneratedMediaCaptureWireError.entries.mapTo(linkedSetOf()) { it.wireValue },
            generatedErrorDescriptors.mapTo(linkedSetOf()) { it.code },
        )
    }

    @Test
    fun codecConsumesEveryGeneratedPayloadDescriptor() {
        val source =
            File("src/main/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt")
                .readText()

        generatedPayloadDescriptors.forEach { descriptor ->
            assertTrue(source.contains("\"${descriptor.id}\""), descriptor.id)
        }
        assertTrue(source.contains("generatedMatchesWireFieldPrimitive"))
        assertTrue(source.contains("generatedEnvelopeRequiredKeys"))
        assertTrue(source.contains("generatedErrorDescriptors"))
    }

    @Test
    fun generatedSourceHasStableProvenanceAndNoHostMetadata() {
        val source =
            File("src/main/kotlin/com/example/media_capture/MediaCaptureWire.g.kt")
                .readText()

        assertTrue(source.startsWith("// GENERATED CODE - DO NOT MODIFY BY HAND."))
        assertTrue(source.contains("// Generator: media_capture_wire/1"))
        assertTrue(source.contains("// Source digest (SHA-256):"))
        val userHome = System.getProperty("user.home")
        assertTrue(userHome.isNullOrEmpty() || !source.contains(userHome))
        assertFalse(source.contains("Generated at"))
    }

    @Test
    fun generatedDescriptorCoverageMatchesTheSharedNeutralGolden() {
        val source = File("src/main/kotlin/com/example/media_capture/MediaCaptureWire.g.kt").readText()
        val golden = repositoryFile(
            "app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json",
        ).readText()
        val digest = Regex("Source digest \\(SHA-256\\): ([0-9a-f]{64})").find(source)?.groupValues?.get(1)

        assertTrue(golden.contains("\"normalizedDescriptorDigest\": \"$digest\""))
        assertTrue(golden.contains("\"methodCount\": ${GeneratedMediaCaptureWireMethod.entries.size}"))
        assertTrue(golden.contains("\"eventCount\": ${GeneratedMediaCaptureWireEvent.entries.size}"))
        assertTrue(golden.contains("\"resultTypeCount\": ${GeneratedMediaCaptureWireResult.entries.size}"))
        assertTrue(golden.contains("\"failureTypeCount\": ${GeneratedMediaCaptureWireFailure.entries.size}"))
        assertTrue(golden.contains("\"errorCount\": ${GeneratedMediaCaptureWireError.entries.size}"))
        assertTrue(golden.contains("\"payloadDescriptorCount\": ${generatedPayloadDescriptors.size}"))
        assertTrue(golden.contains("\"fieldDescriptorCount\": ${generatedMediaCaptureWireFields.size}"))
    }

    private fun repositoryFile(relativePath: String): File {
        var directory = File("").absoluteFile
        while (true) {
            val candidate = File(directory, relativePath)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Repository root not found")
        }
    }
}
