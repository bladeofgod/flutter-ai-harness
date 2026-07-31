package com.example.media_capture

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.AndroidMediaCaptureFactory
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.framework.AndroidPermissionDelegate
import com.example.mediacapture.ui.MediaCaptureUiPresenter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class MediaCaptureBridgePlugin private constructor(
    private val dependencies: Dependencies,
) : FlutterPlugin,
    ActivityAware {
    constructor() : this(Dependencies.production())

    internal constructor(
        coreFactory: MediaCaptureCoreFactory,
        mainDispatcher: CoroutineDispatcher,
        workerDispatcher: CoroutineDispatcher,
        ioDispatcher: CoroutineDispatcher,
        nowMillis: () -> Long,
        epochMillis: () -> Long = nowMillis,
    ) : this(
        Dependencies(
            coreFactory = coreFactory,
            mainDispatcher = mainDispatcher,
            workerDispatcher = workerDispatcher,
            ioDispatcher = ioDispatcher,
            nowMillis = nowMillis,
            epochMillis = epochMillis,
        ),
    )

    private var commandMessenger: BinaryMessenger? = null
    private var eventMessenger: BinaryMessenger? = null
    private var controller: MediaCaptureBridgeController? = null
    private var attachedOwner: MediaCaptureBridgeOwner? = null
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        val scope = CoroutineScope(SupervisorJob() + dependencies.workerDispatcher)
        controller =
            MediaCaptureBridgeController(
                scope = scope,
                mainDispatcher = dependencies.mainDispatcher,
                nowMillis = dependencies.nowMillis,
                epochMillis = dependencies.epochMillis,
                transferStore = MediaCaptureTransferStore(binding.applicationContext.cacheDir),
            )
        commandMessenger = binding.binaryMessenger
        binding.binaryMessenger.setMessageHandler(
            MEDIA_CAPTURE_COMMANDS_CHANNEL,
            BoundedCommandHandler(::handleMethodCall),
        )
        eventMessenger = binding.binaryMessenger
        binding.binaryMessenger.setMessageHandler(
            MEDIA_CAPTURE_EVENTS_CHANNEL,
            BoundedEventHandler(
                messenger = binding.binaryMessenger,
                onListen = ::handleEventListen,
                onCancel = ::handleEventCancel,
            ),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        commandMessenger?.setMessageHandler(MEDIA_CAPTURE_COMMANDS_CHANNEL, null)
        eventMessenger?.setMessageHandler(MEDIA_CAPTURE_EVENTS_CHANNEL, null)
        commandMessenger = null
        eventMessenger = null
        controller?.detachEngine()
        controller = null
        attachedOwner = null
        applicationContext = null
    }

    private fun handleMethodCall(call: MethodCall, result: MediaCaptureBridgeResult) {
        val current = controller
        if (current == null) {
            val failure =
                MediaCaptureWireCodec.bridgeUnavailable(
                    call.method,
                    "engine_detached",
                )
            result.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
            return
        }
        current.handleMethod(call.method, call.arguments, result)
    }

    private fun handleEventListen(arguments: Any?, events: MediaCaptureBridgeEventSink) {
        val current = controller
        if (current == null) {
            val failure =
                MediaCaptureWireCodec.bridgeUnavailable(
                    "unknown_operation",
                    "engine_detached",
                )
            events.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
            return
        }
        current.onListen(arguments, events)
    }

    private fun handleEventCancel() {
        controller?.onCancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachCurrentOwner("activity_destroyed")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachCurrentOwner("activity_destroyed")
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        detachCurrentOwner("activity_destroyed")
        val bridgeController = controller ?: return
        val appContext = applicationContext ?: return
        val lifecycleOwner = binding.activity as? LifecycleOwner ?: return
        val ownerScope = CoroutineScope(SupervisorJob() + dependencies.workerDispatcher)
        val permissionDelegate =
            MediaCapturePermissionDelegate(
                activity = binding.activity,
                binding = binding,
                mainDispatcher = dependencies.mainDispatcher,
            )
        val mediaCapture =
            dependencies.coreFactory.create(
                context = appContext,
                activity = binding.activity,
                lifecycleOwner = lifecycleOwner,
                permissionDelegate = permissionDelegate,
                parentScope = ownerScope,
                mainDispatcher = dependencies.mainDispatcher,
                ioDispatcher = dependencies.ioDispatcher,
                workerDispatcher = dependencies.workerDispatcher,
            )
        val owner =
            MediaCaptureBridgeOwner(
                generation = bridgeController.nextOwnerGeneration(),
                activity = binding.activity,
                lifecycleOwner = lifecycleOwner,
                mediaCapture = mediaCapture,
                presenter =
                    MediaCaptureBridgePresenter { config ->
                        val session =
                            MediaCaptureUiPresenter(
                                binding.activity,
                                lifecycleOwner,
                                mediaCapture,
                            ).present(config)
                        object : MediaCaptureBridgePresentationSession {
                            override suspend fun awaitResult() = session.awaitResult()

                            override fun dismiss() = session.dismiss()
                        }
                    },
                closeAction = permissionDelegate::close,
                retireAction = ownerScope::cancel,
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight { options ->
                        permissionDelegate.prepareForCapture(options)
                    },
                permissionInvalidationAction = permissionDelegate::invalidate,
            )
        attachedOwner = owner
        bridgeController.attachOwner(owner)
    }

    private fun detachCurrentOwner(reason: String) {
        val owner = attachedOwner ?: return
        attachedOwner = null
        controller?.detachOwner(owner.generation, reason)
    }

    private data class Dependencies(
        val coreFactory: MediaCaptureCoreFactory,
        val mainDispatcher: CoroutineDispatcher,
        val workerDispatcher: CoroutineDispatcher,
        val ioDispatcher: CoroutineDispatcher,
        val nowMillis: () -> Long,
        val epochMillis: () -> Long,
    ) {
        companion object {
            fun production(): Dependencies =
                Dependencies(
                    coreFactory = ProductionMediaCaptureCoreFactory,
                    mainDispatcher = Dispatchers.Main.immediate,
                    workerDispatcher = Dispatchers.Default,
                    ioDispatcher = Dispatchers.IO,
                    nowMillis = SystemClock::elapsedRealtime,
                    epochMillis = System::currentTimeMillis,
                )
        }
    }

    private companion object {
        const val REDACTED_ERROR_MESSAGE = "Media capture operation failed."
    }
}

internal class BoundedCommandHandler(
    private val onMethodCall: (MethodCall, MediaCaptureBridgeResult) -> Unit,
) : BinaryMessenger.BinaryMessageHandler {
    override fun onMessage(message: ByteBuffer?, reply: BinaryMessenger.BinaryReply) {
        if (message == null || message.remaining() > MAX_COMMAND_MESSAGE_BYTES) {
            val failure =
                MediaCaptureWireCodec.invalidPayload(
                    "unknown_operation",
                    "payload",
                    "out_of_range",
                )
            reply.reply(
                StandardMethodCodec.INSTANCE.encodeErrorEnvelope(
                    failure.code,
                    REDACTED_COMMAND_ERROR_MESSAGE,
                    failure.details,
                ),
            )
            return
        }
        val call =
            try {
                StandardMethodCodec.INSTANCE.decodeMethodCall(message)
            } catch (_: Exception) {
                val failure =
                    MediaCaptureWireCodec.invalidPayload(
                        "unknown_operation",
                        "payload",
                        "type_mismatch",
                    )
                reply.reply(
                    StandardMethodCodec.INSTANCE.encodeErrorEnvelope(
                        failure.code,
                        REDACTED_COMMAND_ERROR_MESSAGE,
                        failure.details,
                    ),
                )
                return
            }
        onMethodCall(call, RawFlutterResult(reply))
    }
}

internal class BoundedEventHandler(
    private val messenger: BinaryMessenger,
    private val onListen: (Any?, MediaCaptureBridgeEventSink) -> Unit,
    private val onCancel: () -> Unit,
) : BinaryMessenger.BinaryMessageHandler {
    override fun onMessage(message: ByteBuffer?, reply: BinaryMessenger.BinaryReply) {
        if (message == null || message.remaining() > MAX_EVENT_CONTROL_MESSAGE_BYTES) {
            reply.errorEnvelope(
                MediaCaptureWireCodec.invalidPayload(
                    "unknown_operation",
                    "payload",
                    "out_of_range",
                ),
            )
            return
        }
        val call =
            try {
                StandardMethodCodec.INSTANCE.decodeMethodCall(message)
            } catch (_: Exception) {
                reply.errorEnvelope(
                    MediaCaptureWireCodec.invalidPayload(
                        "unknown_operation",
                        "payload",
                        "type_mismatch",
                    ),
                )
                return
            }
        when (call.method) {
            "listen" -> {
                onListen(
                    call.arguments,
                    RawFlutterEventSink(messenger, MEDIA_CAPTURE_EVENTS_CHANNEL),
                )
                reply.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null))
            }
            "cancel" -> {
                onCancel()
                reply.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null))
            }
            else ->
                reply.errorEnvelope(
                    MediaCaptureWireCodec.invalidPayload(
                        "unknown_operation",
                        "payload",
                        "invalid_enum",
                    ),
                )
        }
    }
}

private class RawFlutterEventSink(
    private val messenger: BinaryMessenger,
    private val channel: String,
) : MediaCaptureBridgeEventSink {
    private val terminal = AtomicBoolean(false)

    override fun success(value: Any?) {
        if (!terminal.get()) {
            messenger.send(channel, StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value))
        }
    }

    override fun error(code: String, message: String, details: Any?) {
        if (terminal.compareAndSet(false, true)) {
            messenger.send(
                channel,
                StandardMethodCodec.INSTANCE.encodeErrorEnvelope(code, message, details),
            )
        }
    }

    override fun endOfStream() {
        if (terminal.compareAndSet(false, true)) messenger.send(channel, null)
    }
}

private fun BinaryMessenger.BinaryReply.errorEnvelope(failure: MediaCaptureWireFailure) {
    reply(
        StandardMethodCodec.INSTANCE.encodeErrorEnvelope(
            failure.code,
            REDACTED_COMMAND_ERROR_MESSAGE,
            failure.details,
        ),
    )
}

private class RawFlutterResult(
    private val reply: BinaryMessenger.BinaryReply,
) : MediaCaptureBridgeResult {
    private val completed = AtomicBoolean(false)

    override fun success(value: Any?) {
        if (completed.compareAndSet(false, true)) {
            reply.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value))
        }
    }

    override fun error(code: String, message: String, details: Any?) {
        if (completed.compareAndSet(false, true)) {
            reply.reply(StandardMethodCodec.INSTANCE.encodeErrorEnvelope(code, message, details))
        }
    }
}

internal const val MAX_COMMAND_MESSAGE_BYTES = 65_536
internal const val MAX_EVENT_CONTROL_MESSAGE_BYTES = 4_096
private const val REDACTED_COMMAND_ERROR_MESSAGE = "Media capture operation failed."

internal fun interface MediaCaptureCoreFactory {
    fun create(
        context: Context,
        activity: Activity,
        lifecycleOwner: LifecycleOwner,
        permissionDelegate: AndroidPermissionDelegate,
        parentScope: CoroutineScope,
        mainDispatcher: CoroutineDispatcher,
        ioDispatcher: CoroutineDispatcher,
        workerDispatcher: CoroutineDispatcher,
    ): MediaCapture
}

private object ProductionMediaCaptureCoreFactory : MediaCaptureCoreFactory {
    override fun create(
        context: Context,
        activity: Activity,
        lifecycleOwner: LifecycleOwner,
        permissionDelegate: AndroidPermissionDelegate,
        parentScope: CoroutineScope,
        mainDispatcher: CoroutineDispatcher,
        ioDispatcher: CoroutineDispatcher,
        workerDispatcher: CoroutineDispatcher,
    ): MediaCapture =
        AndroidMediaCaptureFactory.create(
            context = context,
            lifecycleOwner = lifecycleOwner,
            permissionDelegate = permissionDelegate,
            parentScope = parentScope,
            mainDispatcher = mainDispatcher,
            ioDispatcher = ioDispatcher,
            workerDispatcher = workerDispatcher,
        )
}
