package com.example.media_capture

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.lang.reflect.Proxy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

class BoundedCommandHandlerTest {
    @Test
    fun rejectsOversizedMessageBeforeMethodCodecDecoding() {
        var invoked = false
        var encodedReply: ByteBuffer? = null
        val handler =
            BoundedCommandHandler { _, _ ->
                invoked = true
            }

        handler.onMessage(
            ByteBuffer.allocate(MAX_COMMAND_MESSAGE_BYTES + 1),
            BinaryMessenger.BinaryReply { encodedReply = it },
        )

        assertFalse(invoked)
        val failure =
            assertFailsWith<FlutterException> {
                StandardMethodCodec.INSTANCE.decodeEnvelope(assertNotNull(encodedReply).apply { flip() })
            }
        assertEquals("invalid_wire_payload", failure.code)
    }

    @Test
    fun decodesAndRepliesWithStandardMethodCodecInsideBound() {
        var encodedReply: ByteBuffer? = null
        val handler =
            BoundedCommandHandler { call, result ->
                assertEquals("cancel", call.method)
                result.success(mapOf("accepted" to true))
            }
        val message =
            StandardMethodCodec.INSTANCE.encodeMethodCall(
                MethodCall("cancel", envelope("bounded-request", sessionPayload())),
            ).apply { flip() }

        handler.onMessage(
            message,
            BinaryMessenger.BinaryReply { encodedReply = it },
        )

        assertEquals(
            mapOf("accepted" to true),
            StandardMethodCodec.INSTANCE.decodeEnvelope(assertNotNull(encodedReply).apply { flip() }),
        )
    }

    @Test
    fun repeatedEventListenDoesNotImplicitlyCancelExistingListener() {
        val messenger =
            Proxy.newProxyInstance(
                BinaryMessenger::class.java.classLoader,
                arrayOf(BinaryMessenger::class.java),
            ) { _, _, _ -> null } as BinaryMessenger
        var listenCount = 0
        var cancelCount = 0
        val handler =
            BoundedEventHandler(
                messenger = messenger,
                onListen = { _, _ -> listenCount += 1 },
                onCancel = { cancelCount += 1 },
            )

        repeat(2) {
            val message =
                StandardMethodCodec.INSTANCE.encodeMethodCall(
                    MethodCall("listen", mapOf("wireVersion" to 3)),
                ).apply { flip() }
            handler.onMessage(message, BinaryMessenger.BinaryReply {})
        }

        assertEquals(2, listenCount)
        assertEquals(0, cancelCount)
    }
}
