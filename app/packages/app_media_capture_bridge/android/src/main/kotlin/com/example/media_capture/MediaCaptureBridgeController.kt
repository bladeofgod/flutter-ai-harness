package com.example.media_capture

import android.app.Activity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaPreview
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.ui.MediaCaptureFlowResult
import com.example.mediacapture.ui.MediaCaptureUiConfig
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal interface MediaCaptureBridgeResult {
    fun success(value: Any?)

    fun error(code: String, message: String, details: Any?)
}

internal interface MediaCaptureBridgeEventSink {
    fun success(value: Any?)

    fun error(code: String, message: String, details: Any?)

    fun endOfStream()
}

internal interface MediaCaptureBridgePresentationSession {
    suspend fun awaitResult(): MediaCaptureFlowResult

    fun dismiss()
}

internal fun interface MediaCaptureBridgePresenter {
    fun present(config: MediaCaptureUiConfig): MediaCaptureBridgePresentationSession
}

internal fun interface MediaCaptureBridgePermissionPreflight {
    suspend fun prepare(options: SessionOptions): FailureCode?
}

internal class MediaCaptureBridgeOwner(
    val generation: Long,
    val activity: Activity,
    val lifecycleOwner: LifecycleOwner,
    val mediaCapture: MediaCapture,
    val presenter: MediaCaptureBridgePresenter,
    val closeAction: () -> Unit,
    val retireAction: () -> Unit,
    val permissionPreflight: MediaCaptureBridgePermissionPreflight =
        MediaCaptureBridgePermissionPreflight { null },
    val permissionInvalidationAction: () -> Unit = {},
) {
    val sessions = mutableSetOf<String>()
    val previews = mutableMapOf<String, String>()
    val leases = mutableSetOf<String>()
    val settlingMedia = mutableSetOf<String>()
    val cleanupSessions = mutableSetOf<String>()
    val cleanupLeases = mutableSetOf<String>()
    var eventJob: Job? = null
    var cleanupJob: Job? = null
    var closed = false
    var boundaryCleanupInProgress = false
    var boundaryCompletionPending = false
    var presentationCleanupPending = false
    var engineClosing = false
    var closeActionRunning = false
    var closeActionComplete = false
    var permissionInvalidated = false
    var retiring = false
    var retired = false
    var inFlightOperations = 0
}

internal class MediaCaptureBridgeController(
    private val scope: CoroutineScope,
    private val mainDispatcher: CoroutineDispatcher,
    private val nowMillis: () -> Long,
    private val epochMillis: () -> Long = nowMillis,
    private val transferStore: MediaCaptureTransferStore? = null,
) {
    private val lock = Any()
    private val ownerGeneration = AtomicLong(0L)
    private val pending = linkedMapOf<String, PendingRequest>()
    private val completed = linkedMapOf<String, Long>()
    private val owners = linkedSetOf<MediaCaptureBridgeOwner>()
    private val sessionOwners = mutableMapOf<String, MediaCaptureBridgeOwner>()
    private val previewOwners = mutableMapOf<String, PreviewOwnership>()
    private val leaseOwners = mutableMapOf<String, MediaCaptureBridgeOwner>()
    private val leaseMetadata = mutableMapOf<String, MediaMetadata>()
    private val settlingOwners = mutableMapOf<String, MediaCaptureBridgeOwner>()
    private val transfers = mutableMapOf<String, TransferRecord>()
    private val releaseTombstones = linkedMapOf<String, Long>()
    private val releaseClaims = mutableMapOf<String, CompletableDeferred<Boolean>>()

    private var engineOpen = true
    private var transferGenerationOpen = transferStore?.isAvailable == true
    private var activeTransferBytes = 0L
    private var currentOwner: MediaCaptureBridgeOwner? = null
    private var activePresentation: ActivePresentation? = null
    private var presentationCleanupInProgress = false
    private var eventListener: ActiveEventListener? = null
    private var listenerGeneration = 0L
    private var engineCallbacksCompleted = false
    private var queuedCallbacks = 0

    fun nextOwnerGeneration(): Long = ownerGeneration.incrementAndGet()

    fun attachOwner(owner: MediaCaptureBridgeOwner) {
        val accepted =
            synchronized(lock) {
                if (!engineOpen) {
                    false
                } else {
                    currentOwner?.closed = true
                    currentOwner = owner
                    owners += owner
                    true
                }
            }
        if (!accepted) {
            synchronized(lock) { invalidateOwnerPermissionLocked(owner) }
            scope.launch { closeOwner(owner, releaseLeases = true) }
            return
        }
        val eventJob =
            scope.launch(start = CoroutineStart.LAZY) {
                owner.mediaCapture.events.collect { event -> emitNativeEvent(owner, event) }
            }
        val startCollector =
            synchronized(lock) {
                if (owner.retired || !engineOpen) {
                    false
                } else {
                    owner.eventJob = eventJob
                    true
                }
            }
        if (startCollector) {
            eventJob.start()
        } else {
            eventJob.cancel()
        }
    }

    fun handleMethod(
        operation: String,
        arguments: Any?,
        result: MediaCaptureBridgeResult,
    ) {
        val request =
            try {
                MediaCaptureWireCodec.decodeRequest(operation, arguments)
            } catch (failure: MediaCaptureWireFailure) {
                deliverError(result, failure)
                return
            } catch (_: Exception) {
                deliverError(
                    result,
                    MediaCaptureWireCodec.invalidPayload(operation, "payload", "type_mismatch"),
                )
                return
            }
        val reservation = reserve(request, result)
        if (reservation is ReservationRejected) {
            deliverError(result, reservation.failure)
            return
        }
        val pendingRequest = (reservation as ReservationAccepted).pending
        scope.launch { execute(pendingRequest, request) }
    }

    fun onListen(arguments: Any?, sink: MediaCaptureBridgeEventSink) {
        try {
            MediaCaptureWireCodec.decodeListenArguments(arguments)
        } catch (failure: MediaCaptureWireFailure) {
            deliverEventError(sink, failure)
            return
        } catch (_: Exception) {
            deliverEventError(
                sink,
                MediaCaptureWireCodec.invalidPayload(
                    "unknown_operation",
                    "payload",
                    "type_mismatch",
                ),
            )
            return
        }
        val failure =
            synchronized(lock) {
                when {
                    !engineOpen ->
                        MediaCaptureWireCodec.bridgeUnavailable(
                            "unknown_operation",
                            "engine_detached",
                        )
                    eventListener != null -> MediaCaptureWireCodec.listenerAlreadyActive()
                    else -> {
                        listenerGeneration += 1L
                        eventListener = ActiveEventListener(listenerGeneration, sink)
                        null
                    }
                }
            }
        if (failure != null) deliverEventError(sink, failure)
    }

    fun onCancel() {
        synchronized(lock) { eventListener = null }
    }

    fun detachOwner(generation: Long, reason: String = "activity_destroyed") {
        val boundary =
            synchronized(lock) {
                val owner = owners.firstOrNull { it.generation == generation } ?: return
                if (owner.closed) return
                owner.closed = true
                if (currentOwner === owner) currentOwner = null
                invalidateOwnerPermissionLocked(owner)
                closeOwnerBoundaryLocked(owner, reason)
            }
        scope.launch { finishOwnerBoundary(boundary) }
    }

    fun detachEngine() {
        val boundary =
            synchronized(lock) {
                if (!engineOpen) return
                engineOpen = false
                currentOwner = null
                owners.forEach {
                    it.closed = true
                    it.engineClosing = true
                    invalidateOwnerPermissionLocked(it)
                }
                transferGenerationOpen = false
                transferStore?.closeGeneration()
                val transferRecords = transfers.values.toList()
                transferRecords.forEach {
                    it.expired = true
                    it.cleanupPending = true
                    it.ttlJob?.cancel()
                }
                releaseClaims.values.forEach { it.complete(false) }
                val presentation = activePresentation.also { activePresentation = null }
                val requests = pending.values.toList()
                pending.clear()
                requests.forEach(::completeTombstoneLocked)
                val listener = eventListener.also { eventListener = null }
                EngineBoundary(owners.toList(), presentation, requests, listener, transferRecords)
            }
        scope.launch {
            withContext(mainDispatcher) { boundary.presentation?.session?.dismiss() }
            boundary.owners.forEach { owner -> closeOwner(owner, releaseLeases = true) }
            cleanupTransferRecords(boundary.transfers)
            withContext(mainDispatcher) {
                boundary.requests.forEach { request ->
                    val failure =
                        MediaCaptureWireCodec.bridgeUnavailable(
                            request.operation,
                            "engine_detached",
                        )
                    request.result.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
                }
                boundary.listener?.sink?.endOfStream()
            }
            synchronized(lock) {
                engineCallbacksCompleted = true
            }
            maybeCancelEngineScope()
        }
    }

    private suspend fun execute(
        pendingRequest: PendingRequest,
        request: MediaCaptureWireRequest,
    ) {
        try {
            when (val payload = request.payload) {
                is MediaCaptureWirePayload.StartSession ->
                    if (request.operation == "present_capture_flow") {
                        executePresentation(pendingRequest, payload.options)
                    } else {
                        executeStartSession(pendingRequest, payload.options)
                    }
                is MediaCaptureWirePayload.SessionAction ->
                    executeSessionAction(pendingRequest, payload.sessionHandle)
                is MediaCaptureWirePayload.Flash ->
                    executeFlash(pendingRequest, payload.sessionHandle, payload.flashMode)
                is MediaCaptureWirePayload.Focus ->
                    executeFocus(pendingRequest, payload)
                is MediaCaptureWirePayload.Zoom ->
                    executeZoom(pendingRequest, payload)
                is MediaCaptureWirePayload.MediaAction ->
                    executeMediaAction(pendingRequest, payload.mediaHandle)
                is MediaCaptureWirePayload.Thumbnail ->
                    executeThumbnail(pendingRequest, payload)
                is MediaCaptureWirePayload.Materialize ->
                    executeMaterialize(pendingRequest, payload.mediaHandle)
                is MediaCaptureWirePayload.ReleaseMaterialized ->
                    executeReleaseMaterialized(pendingRequest, payload.exportHandle)
                is MediaCaptureWirePayload.DismissPresentation ->
                    executeDismissPresentation(pendingRequest, payload.presentationRequestId)
            }
        } catch (failure: MediaCaptureWireFailure) {
            completeFailure(pendingRequest, failure)
        } catch (exception: MediaCaptureException) {
            completeFailure(pendingRequest, mapCapabilityFailure(pendingRequest.operation, exception.failure.code))
        } catch (exception: CancellationException) {
            val failure =
                synchronized(lock) {
                    if (engineOpen) {
                        mapCapabilityFailure(pendingRequest.operation, FailureCode.SYSTEM_INTERRUPTED)
                    } else {
                        MediaCaptureWireCodec.bridgeUnavailable(
                            pendingRequest.operation,
                            "engine_detached",
                        )
                    }
                }
            completeFailure(pendingRequest, failure)
        } catch (_: Exception) {
            completeFailure(
                pendingRequest,
                mapCapabilityFailure(pendingRequest.operation, FailureCode.SYSTEM_INTERRUPTED),
            )
        } finally {
            releaseRequestOwners(pendingRequest)
        }
    }

    private suspend fun executeStartSession(
        request: PendingRequest,
        options: SessionOptions,
    ) {
        val owner = request.owner ?: throw MediaCaptureWireCodec.bridgeUnavailable(
            request.operation,
            "activity_destroyed",
        )
        val created = owner.mediaCapture.startSession(options)
        if (!canAdoptNewSession(owner, created.sessionHandle)) {
            withContext(NonCancellable) { interruptSession(owner, created.sessionHandle) }
            throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
        }
        val encoded =
            try {
                encodeOutput(request.operation) {
                    MediaCaptureWireCodec.sessionCreated(request.requestId, created.sessionHandle)
                }
            } catch (failure: MediaCaptureWireFailure) {
                withContext(NonCancellable) { interruptSession(owner, created.sessionHandle) }
                throw failure
            }
        completeSuccess(
            request,
            value = encoded,
            adopt = {
                owner.sessions += created.sessionHandle.value
                sessionOwners[created.sessionHandle.value] = owner
            },
            lateCleanup = { interruptSession(owner, created.sessionHandle) },
        )
    }

    private suspend fun executeSessionAction(request: PendingRequest, handle: SessionHandle) {
        val owner = sessionOwner(handle)
        when (request.operation) {
            "take_photo" -> {
                val preview = owner.mediaCapture.takePhoto(handle)
                completePreview(request, owner, handle, preview)
            }
            "start_recording" -> {
                val started = owner.mediaCapture.startRecording(handle)
                if (started.sessionHandle != handle) {
                    withContext(NonCancellable) {
                        interruptSession(owner, handle)
                        interruptSession(owner, started.sessionHandle)
                    }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                completeSuccess(
                    request,
                    encodeOutput(request.operation) {
                        MediaCaptureWireCodec.recordingStarted(
                            request.requestId,
                            started.sessionHandle,
                            started.audioIncluded,
                        )
                    },
                    lateCleanup = { interruptSession(owner, handle) },
                )
            }
            "stop_recording" -> {
                val preview = owner.mediaCapture.stopRecording(handle)
                completePreview(request, owner, handle, preview)
            }
            "switch_camera" -> {
                owner.mediaCapture.switchCamera(handle)
                completeSuccess(
                    request,
                    MediaCaptureWireCodec.controlApplied(request.requestId, handle),
                    lateCleanup = { interruptSession(owner, handle) },
                )
            }
            "cancel" -> {
                val cancelled = owner.mediaCapture.cancel(handle)
                if (cancelled.sessionHandle != handle) {
                    withContext(NonCancellable) {
                        interruptSession(owner, handle)
                        interruptSession(owner, cancelled.sessionHandle)
                    }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                completeSuccess(
                    request,
                    encodeOutput(request.operation) {
                        MediaCaptureWireCodec.sessionCancelled(request.requestId, cancelled.sessionHandle)
                    },
                    adopt = { removeSessionLocked(owner, handle.value) },
                )
            }
            else -> throw MediaCaptureWireCodec.invalidPayload(request.operation, "payload", "invalid_enum")
        }
    }

    private suspend fun executeFlash(
        request: PendingRequest,
        handle: SessionHandle,
        flashMode: com.example.mediacapture.api.FlashMode,
    ) {
        val owner = sessionOwner(handle)
        owner.mediaCapture.setFlashMode(handle, flashMode)
        completeSuccess(
            request,
            MediaCaptureWireCodec.controlApplied(request.requestId, handle),
            lateCleanup = { interruptSession(owner, handle) },
        )
    }

    private suspend fun executeFocus(
        request: PendingRequest,
        payload: MediaCaptureWirePayload.Focus,
    ) {
        val owner = sessionOwner(payload.sessionHandle)
        owner.mediaCapture.setFocusPoint(
            payload.sessionHandle,
            payload.normalizedX,
            payload.normalizedY,
        )
        completeSuccess(
            request,
            MediaCaptureWireCodec.controlApplied(request.requestId, payload.sessionHandle),
            lateCleanup = { interruptSession(owner, payload.sessionHandle) },
        )
    }

    private suspend fun executeZoom(
        request: PendingRequest,
        payload: MediaCaptureWirePayload.Zoom,
    ) {
        val owner = sessionOwner(payload.sessionHandle)
        owner.mediaCapture.setZoom(payload.sessionHandle, payload.zoomFactor)
        completeSuccess(
            request,
            MediaCaptureWireCodec.controlApplied(request.requestId, payload.sessionHandle),
            lateCleanup = { interruptSession(owner, payload.sessionHandle) },
        )
    }

    private suspend fun executeMediaAction(request: PendingRequest, handle: MediaHandle) {
        when (request.operation) {
            "retake" -> {
                val ownership = previewOwner(handle)
                val session = ownership.owner.mediaCapture.retake(handle)
                if (session.value != ownership.sessionHandle) {
                    withContext(NonCancellable) {
                        interruptSession(ownership.owner, SessionHandle(ownership.sessionHandle))
                        interruptSession(ownership.owner, session)
                    }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                completeSuccess(
                    request,
                    encodeOutput(request.operation) {
                        MediaCaptureWireCodec.retakeReady(request.requestId, session)
                    },
                    adopt = {
                        previewOwners.remove(handle.value)
                        ownership.owner.previews.remove(handle.value)
                        ownership.owner.sessions += session.value
                        sessionOwners[session.value] = ownership.owner
                    },
                    lateCleanup = { interruptSession(ownership.owner, session) },
                )
            }
            "confirm" -> {
                val ownership = previewOwner(handle)
                val media = ownership.owner.mediaCapture.confirm(handle)
                if (media.mediaHandle != handle) {
                    withContext(NonCancellable) {
                        releaseLease(ownership.owner, media.mediaHandle)
                        interruptSession(ownership.owner, SessionHandle(ownership.sessionHandle))
                    }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                if (
                    synchronized(lock) {
                        leaseOwners[handle.value] != null || settlingOwners[handle.value] != null
                    }
                ) {
                    withContext(NonCancellable) {
                        releaseLease(ownership.owner, media.mediaHandle)
                        interruptSession(ownership.owner, SessionHandle(ownership.sessionHandle))
                    }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                val encoded =
                    try {
                        encodeOutput(request.operation) {
                            MediaCaptureWireCodec.confirmedMedia(request.requestId, media)
                        }
                    } catch (failure: MediaCaptureWireFailure) {
                        withContext(NonCancellable) {
                            releaseLease(ownership.owner, media.mediaHandle)
                            interruptSession(ownership.owner, SessionHandle(ownership.sessionHandle))
                        }
                        throw failure
                    }
                completeSuccess(
                    request,
                    encoded,
                    adopt = { adoptLeaseLocked(ownership, media) },
                    lateCleanup = { releaseLease(ownership.owner, media.mediaHandle) },
                )
            }
            "release_media" -> {
                val owner = leaseOwner(handle)
                if (!trackRuntimeOwner(request, owner)) {
                    throw MediaCaptureWireCodec.bridgeUnavailable(request.operation, "engine_detached")
                }
                val released = owner.mediaCapture.releaseMedia(handle)
                if (released.mediaHandle != handle) {
                    withContext(NonCancellable) { releaseLease(owner, handle) }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                completeSuccess(
                    request,
                    encodeOutput(request.operation) {
                        MediaCaptureWireCodec.mediaReleased(request.requestId, released.mediaHandle)
                    },
                    adopt = { removeLeaseLocked(owner, handle.value) },
                )
                retireOwnerIfPossible(owner)
            }
            else -> throw MediaCaptureWireCodec.invalidPayload(request.operation, "payload", "invalid_enum")
        }
    }

    private suspend fun executeThumbnail(
        request: PendingRequest,
        payload: MediaCaptureWirePayload.Thumbnail,
    ) {
        val owner = leaseOwner(payload.mediaHandle)
        if (!trackRuntimeOwner(request, owner)) {
            throw MediaCaptureWireCodec.bridgeUnavailable(request.operation, "engine_detached")
        }
        val read = owner.mediaCapture.readMediaThumbnail(payload.mediaHandle, payload.maxPixelEdge)
        val thumbnail =
            try {
                read.await()
            } catch (exception: CancellationException) {
                withContext(NonCancellable) { runCatching { read.cancel() } }
                throw exception
            }
        if (thumbnail.mediaHandle != payload.mediaHandle) {
            thumbnail.copy.fill(0)
            throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
        }
        val encoded =
            try {
                encodeOutput(request.operation) {
                    MediaCaptureWireCodec.thumbnail(request.requestId, thumbnail, payload.maxPixelEdge)
                }
            } finally {
                thumbnail.copy.fill(0)
            }
        val encodedBytes = ((encoded["payload"] as Map<*, *>)["thumbnailCopy"] as ByteArray)
        completeSuccess(
            request,
            encoded,
            lateCleanup = { encodedBytes.fill(0) },
            afterDelivery = { encodedBytes.fill(0) },
        )
    }

    private suspend fun executeMaterialize(request: PendingRequest, handle: MediaHandle) {
        val ownership =
            synchronized(lock) {
                val owner = leaseOwners[handle.value]
                    ?: throw MediaCaptureException(MediaCaptureFailure(FailureCode.MEDIA_INVALID))
                val metadata = leaseMetadata[handle.value]
                    ?: throw MediaCaptureException(MediaCaptureFailure(FailureCode.MEDIA_INVALID))
                owner to metadata
            }
        if (!trackRuntimeOwner(request, ownership.first)) {
            throw MediaCaptureWireCodec.bridgeUnavailable(request.operation, "engine_detached")
        }
        retryRetainedTransferCleanup()
        val record = reserveTransfer(request.operation, ownership.second)
        var delivered = false
        try {
            val exported =
                ownership.first.mediaCapture.copyConfirmedMediaToSink(
                    mediaHandle = handle,
                    sink = record.reservation.mediaSink,
                    maxLength = MAX_TRANSFER_FILE_BYTES,
                )
            if (
                exported.mediaHandle != handle || exported.mediaType != ownership.second.mediaType ||
                exported.contentType != ownership.second.contentType ||
                exported.byteLength != ownership.second.byteLength || !record.reservation.committed
            ) {
                throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
            }
            val store = transferStore ?: throw MediaCaptureWireCodec.transferStoreUnavailable(request.operation)
            val nowEpochMillis = epochMillis()
            if (nowEpochMillis < 0L || nowEpochMillis > Long.MAX_VALUE - TRANSFER_TTL_MILLIS) {
                throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
            }
            val expiresAt = nowEpochMillis + TRANSFER_TTL_MILLIS
            val encoded =
                encodeOutput(request.operation) {
                    MediaCaptureWireCodec.materializedMedia(
                        requestId = request.requestId,
                        exportHandle = record.reservation.exportHandle,
                        fileUri = store.fileUri(record.reservation),
                        metadata = ownership.second,
                        expiresAtEpochMillis = expiresAt,
                    )
                }
            delivered = completeTransferSuccess(request, record, expiresAt, encoded)
        } finally {
            if (!delivered) cleanupTransferRecord(record)
        }
    }

    private suspend fun executeReleaseMaterialized(request: PendingRequest, exportHandle: String) {
        val decision = claimTransferRelease(exportHandle)
        val released =
            when (decision) {
                TransferReleaseDecision.AlreadyReleased -> true
                is TransferReleaseDecision.Rejected -> throw decision.failure
                is TransferReleaseDecision.Join -> decision.completion.await()
                is TransferReleaseDecision.Claim -> {
                    val deleted = deleteTransferFiles(decision.record)
                    finishTransferRelease(decision.record, decision.completion, deleted)
                    deleted
                }
            }
        if (!released) throw MediaCaptureWireCodec.transferStoreUnavailable(request.operation)
        completeSuccess(
            request,
            MediaCaptureWireCodec.materializedMediaReleased(request.requestId),
        )
    }

    private suspend fun executeDismissPresentation(
        request: PendingRequest,
        presentationRequestId: String,
    ) {
        val dismissal =
            synchronized(lock) {
                val presentation =
                    activePresentation?.takeIf { it.requestId == presentationRequestId }
                        ?: return@synchronized null
                val target = pending[presentationRequestId]
                if (target == null || target.operation != "present_capture_flow") {
                    return@synchronized null
                }
                activePresentation = null
                presentationCleanupInProgress = true
                pending.remove(target.requestId)
                completeTombstoneLocked(target)
                PresentationDismissal(presentation, target)
            }
        if (dismissal != null) {
            withContext(mainDispatcher) {
                try {
                    dismissal.presentation.session?.dismiss()
                    dismissal.target.result.success(
                        MediaCaptureWireCodec.flowCancelled(dismissal.target.requestId),
                    )
                } finally {
                    synchronized(lock) { presentationCleanupInProgress = false }
                }
            }
        }
        completeSuccess(request, MediaCaptureWireCodec.captureFlowDismissed(request.requestId))
    }

    private fun reserveTransfer(operation: String, metadata: MediaMetadata): TransferRecord =
        synchronized(lock) {
            val store = transferStore
            if (!transferGenerationOpen || store == null || !store.isAvailable) {
                throw MediaCaptureWireCodec.transferStoreUnavailable(operation)
            }
            if (transfers.size >= MAX_ACTIVE_TRANSFERS) {
                throw MediaCaptureWireCodec.transferStoreOverloaded(operation, "active_exports")
            }
            if (
                metadata.byteLength <= 0L ||
                metadata.byteLength > MAX_ACTIVE_TRANSFER_BYTES - activeTransferBytes
            ) {
                throw MediaCaptureWireCodec.transferStoreOverloaded(operation, "active_export_bytes")
            }
            repeat(TRANSFER_HANDLE_ATTEMPTS) {
                val reservation =
                    runCatching { store.createReservation(metadata) }
                        .getOrElse { throw MediaCaptureWireCodec.transferStoreUnavailable(operation) }
                if (
                    reservation.exportHandle in transfers ||
                    reservation.exportHandle in releaseTombstones
                ) {
                    store.delete(reservation)
                    return@repeat
                }
                return TransferRecord(reservation).also { record ->
                    transfers[reservation.exportHandle] = record
                    activeTransferBytes += metadata.byteLength
                }
            }
            throw MediaCaptureWireCodec.transferStoreUnavailable(operation)
        }

    private suspend fun completeTransferSuccess(
        request: PendingRequest,
        record: TransferRecord,
        expiresAtEpochMillis: Long,
        value: Map<String, Any?>,
    ): Boolean {
        val delivered =
            withContext(mainDispatcher) {
                synchronized(lock) {
                    if (
                        !isRequestOpenLocked(request) ||
                        transfers[record.reservation.exportHandle] !== record ||
                        record.cleanupPending || !record.reservation.committed
                    ) {
                        false
                    } else {
                        record.active = true
                        record.expiresAtEpochMillis = expiresAtEpochMillis
                        pending.remove(request.requestId)
                        completeTombstoneLocked(request)
                        try {
                            request.result.success(value)
                            true
                        } catch (_: Exception) {
                            record.cleanupPending = true
                            false
                        }
                    }
                }
            }
        if (delivered) {
            val ttlJob = scope.launch {
                delay(TRANSFER_TTL_MILLIS)
                expireTransfer(record.reservation.exportHandle)
            }
            synchronized(lock) {
                if (
                    transfers[record.reservation.exportHandle] === record &&
                    record.active && !record.cleanupPending
                ) {
                    record.ttlJob = ttlJob
                } else {
                    ttlJob.cancel()
                }
            }
        }
        return delivered
    }

    private fun claimTransferRelease(exportHandle: String): TransferReleaseDecision =
        synchronized(lock) {
            pruneReleaseTombstonesLocked()
            if (!engineOpen) {
                return TransferReleaseDecision.Rejected(
                    MediaCaptureWireCodec.bridgeUnavailable(
                        "release_materialized_media",
                        "engine_detached",
                    ),
                )
            }
            if (exportHandle in releaseTombstones) return TransferReleaseDecision.AlreadyReleased
            val record = transfers[exportHandle]
                ?: return TransferReleaseDecision.Rejected(MediaCaptureWireCodec.materializedMediaInvalid())
            if (record.cleanupJob != null) {
                return TransferReleaseDecision.Rejected(
                    MediaCaptureWireCodec.transferStoreUnavailable("release_materialized_media"),
                )
            }
            releaseClaims[exportHandle]?.let { return TransferReleaseDecision.Join(it) }
            if (
                !record.releaseTombstoneReserved &&
                releaseTombstones.size + transfers.values.count { it.releaseTombstoneReserved } >=
                MAX_RELEASE_TOMBSTONES
            ) {
                return TransferReleaseDecision.Rejected(
                    MediaCaptureWireCodec.transferStoreOverloaded(
                        "release_materialized_media",
                        "release_tombstones",
                    ),
                )
            }
            record.cleanupPending = true
            record.releaseTombstoneReserved = true
            record.ttlJob?.cancel()
            val completion = CompletableDeferred<Boolean>()
            releaseClaims[exportHandle] = completion
            TransferReleaseDecision.Claim(record, completion)
        }

    private fun finishTransferRelease(
        record: TransferRecord,
        completion: CompletableDeferred<Boolean>,
        deleted: Boolean,
    ) {
        synchronized(lock) {
            val handle = record.reservation.exportHandle
            if (releaseClaims[handle] === completion) releaseClaims.remove(handle)
            if (deleted && transfers[handle] === record) {
                removeTransferLocked(record)
                releaseTombstones[handle] = nowMillis()
            }
            completion.complete(deleted)
        }
        if (!deleted) scheduleTransferCleanup(record)
    }

    private suspend fun expireTransfer(exportHandle: String) {
        val record =
            synchronized(lock) {
                transfers[exportHandle]?.also {
                    it.expired = true
                    it.cleanupPending = true
                    it.ttlJob = null
                }
            } ?: return
        cleanupTransferRecord(record)
    }

    private suspend fun cleanupTransferRecord(record: TransferRecord) {
        synchronized(lock) {
            if (transfers[record.reservation.exportHandle] !== record) return
            record.cleanupPending = true
            record.ttlJob?.cancel()
        }
        if (deleteTransferFiles(record)) {
            synchronized(lock) {
                if (transfers[record.reservation.exportHandle] === record) {
                    settleTransferCleanupLocked(record)
                }
            }
        } else {
            scheduleTransferCleanup(record)
        }
    }

    private suspend fun cleanupTransferRecords(records: List<TransferRecord>) {
        records.forEach { cleanupTransferRecord(it) }
    }

    private suspend fun retryRetainedTransferCleanup() {
        val retained =
            synchronized(lock) {
                transfers.values.filter { it.cleanupPending && it.cleanupJob == null }
            }
        retained.forEach { cleanupTransferRecord(it) }
    }

    private fun scheduleTransferCleanup(record: TransferRecord) {
        val job =
            scope.launch(start = CoroutineStart.LAZY) {
                var retryDelay = CLEANUP_RETRY_MILLIS
                repeat(TRANSFER_RETAINED_CLEANUP_ATTEMPTS) {
                    delay(retryDelay)
                    if (deleteTransferFiles(record)) {
                        synchronized(lock) {
                            if (transfers[record.reservation.exportHandle] === record) {
                                settleTransferCleanupLocked(record)
                            }
                            record.cleanupJob = null
                        }
                        maybeCancelEngineScope()
                        return@launch
                    }
                    val retained =
                        synchronized(lock) {
                            transfers[record.reservation.exportHandle] === record
                        }
                    if (!retained) {
                        synchronized(lock) { record.cleanupJob = null }
                        maybeCancelEngineScope()
                        return@launch
                    }
                    retryDelay = (retryDelay * 2).coerceAtMost(MAX_CLEANUP_RETRY_MILLIS)
                }
                synchronized(lock) { record.cleanupJob = null }
                maybeCancelEngineScope()
            }
        val accepted =
            synchronized(lock) {
                if (transfers[record.reservation.exportHandle] !== record || record.cleanupJob != null) {
                    false
                } else {
                    record.cleanupJob = job
                    true
                }
            }
        if (accepted) job.start() else job.cancel()
    }

    private suspend fun deleteTransferFiles(record: TransferRecord): Boolean {
        val store = transferStore ?: return false
        repeat(TRANSFER_DELETE_ATTEMPTS) { attempt ->
            if (runCatching { store.delete(record.reservation) }.getOrDefault(false)) return true
            if (attempt + 1 < TRANSFER_DELETE_ATTEMPTS) delay(CLEANUP_RETRY_MILLIS)
        }
        return false
    }

    private fun removeTransferLocked(record: TransferRecord) {
        val handle = record.reservation.exportHandle
        if (transfers[handle] !== record) return
        transfers.remove(handle)
        activeTransferBytes =
            (activeTransferBytes - record.reservation.metadata.byteLength).coerceAtLeast(0L)
        record.ttlJob?.cancel()
        record.cleanupJob?.cancel()
        releaseClaims.remove(handle)?.complete(false)
    }

    private fun settleTransferCleanupLocked(record: TransferRecord) {
        val handle = record.reservation.exportHandle
        val addReleaseTombstone = record.releaseTombstoneReserved
        removeTransferLocked(record)
        if (addReleaseTombstone) releaseTombstones[handle] = nowMillis()
    }

    private fun pruneReleaseTombstonesLocked() {
        val now = nowMillis()
        releaseTombstones.entries.removeAll { now - it.value >= TRANSFER_TTL_MILLIS }
    }

    private suspend fun executePresentation(request: PendingRequest, options: SessionOptions) {
        val owner = request.owner ?: throw MediaCaptureWireCodec.bridgeUnavailable(
            request.operation,
            "activity_destroyed",
        )
        if (!isPlatformOwnerAlive(owner)) {
            throw MediaCaptureWireCodec.bridgeUnavailable(request.operation, "activity_destroyed")
        }
        val reserved =
            synchronized(lock) {
                if (
                    !isRequestOpenLocked(request) || activePresentation != null ||
                    presentationCleanupInProgress
                ) {
                    false
                } else {
                    activePresentation = ActivePresentation(owner, request.requestId, null)
                    true
                }
        }
        if (!reserved) throw MediaCaptureWireCodec.presentationConflict()
        val permissionFailure = owner.permissionPreflight.prepare(options)
        if (permissionFailure != null) {
            throw MediaCaptureException(MediaCaptureFailure(permissionFailure))
        }
        val session =
            withContext(mainDispatcher) {
                synchronized(lock) {
                    val presentation = activePresentation
                    if (
                        !isRequestOpenLocked(request) ||
                        presentation == null ||
                        presentation.requestId != request.requestId ||
                        presentation.owner !== owner ||
                        currentOwner !== owner ||
                        !isPlatformOwnerAliveOnMain(owner)
                    ) {
                        throw MediaCaptureWireCodec.bridgeUnavailable(
                            request.operation,
                            "activity_destroyed",
                        )
                    }
                    try {
                        owner.presenter.present(options.toUiConfig()).also { presented ->
                            if (
                                !isRequestOpenLocked(request) ||
                                activePresentation !== presentation ||
                                currentOwner !== owner ||
                                !isPlatformOwnerAliveOnMain(owner)
                            ) {
                                presented.dismiss()
                                throw MediaCaptureWireCodec.bridgeUnavailable(
                                    request.operation,
                                    "activity_destroyed",
                                )
                            }
                            presentation.session = presented
                        }
                    } catch (failure: MediaCaptureWireFailure) {
                        throw failure
                    } catch (_: IllegalStateException) {
                        if (activePresentation === presentation) activePresentation = null
                        throw if (!isPlatformOwnerAliveOnMain(owner) || owner.closed || currentOwner !== owner) {
                            MediaCaptureWireCodec.bridgeUnavailable(
                                request.operation,
                                "activity_destroyed",
                            )
                        } else {
                            MediaCaptureWireCodec.presentationConflict()
                        }
                    }
                }
            }
        when (val outcome = session.awaitResult()) {
            is MediaCaptureFlowResult.Confirmed -> {
                if (!canAdoptNewLease(outcome.media.mediaHandle)) {
                    clearPresentation(request.requestId)
                    withContext(NonCancellable) { releaseLease(owner, outcome.media.mediaHandle) }
                    throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
                }
                val encoded =
                    try {
                        encodeOutput(request.operation) {
                            MediaCaptureWireCodec.flowConfirmed(request.requestId, outcome.media)
                        }
                    } catch (failure: MediaCaptureWireFailure) {
                        clearPresentation(request.requestId)
                        withContext(NonCancellable) { releaseLease(owner, outcome.media.mediaHandle) }
                        throw failure
                    }
                completeSuccess(
                    request,
                    encoded,
                    adopt = {
                        clearPresentationLocked(request.requestId)
                        owner.leases += outcome.media.mediaHandle.value
                        leaseOwners[outcome.media.mediaHandle.value] = owner
                        leaseMetadata[outcome.media.mediaHandle.value] = outcome.media.metadata
                    },
                    lateCleanup = {
                        clearPresentation(request.requestId)
                        releaseLease(owner, outcome.media.mediaHandle)
                    },
                )
            }
            MediaCaptureFlowResult.Cancelled ->
                completeSuccess(
                    request,
                    encodeOutput(request.operation) {
                        MediaCaptureWireCodec.flowCancelled(request.requestId)
                    },
                    adopt = { clearPresentationLocked(request.requestId) },
                    lateCleanup = { clearPresentation(request.requestId) },
                )
            is MediaCaptureFlowResult.Failure -> {
                clearPresentation(request.requestId)
                throw MediaCaptureException(outcome.failure)
            }
        }
    }

    private suspend fun completePreview(
        request: PendingRequest,
        owner: MediaCaptureBridgeOwner,
        session: SessionHandle,
        preview: MediaPreview,
    ) {
        if (!canAdoptPreview(owner, session, preview.mediaHandle)) {
            withContext(NonCancellable) { interruptSession(owner, session) }
            throw MediaCaptureWireCodec.wireEncodingFailure(request.operation)
        }
        val encoded =
            try {
                encodeOutput(request.operation) {
                    MediaCaptureWireCodec.mediaPreview(request.requestId, preview)
                }
            } catch (failure: MediaCaptureWireFailure) {
                withContext(NonCancellable) { interruptSession(owner, session) }
                throw failure
            }
        completeSuccess(
            request,
            encoded,
            adopt = {
                owner.previews[preview.mediaHandle.value] = session.value
                previewOwners[preview.mediaHandle.value] = PreviewOwnership(owner, session.value)
            },
            lateCleanup = { interruptSession(owner, session) },
        )
    }

    private suspend fun completeSuccess(
        request: PendingRequest,
        value: Map<String, Any?>,
        adopt: () -> Unit = {},
        lateCleanup: suspend () -> Unit = {},
        afterDelivery: () -> Unit = {},
    ) {
        val won =
            withContext(mainDispatcher) {
                synchronized(lock) {
                    if (!isRequestOpenLocked(request)) {
                        false
                    } else {
                        adopt()
                        pending.remove(request.requestId)
                        completeTombstoneLocked(request)
                        try {
                            request.result.success(value)
                            true
                        } catch (_: Exception) {
                            false
                        }
                    }
                }
            }
        if (won) {
            afterDelivery()
        } else {
            withContext(NonCancellable) { lateCleanup() }
        }
    }

    private suspend fun completeFailure(request: PendingRequest, failure: MediaCaptureWireFailure) {
        withContext(mainDispatcher) {
            synchronized(lock) {
                if (isRequestOpenLocked(request)) {
                    pending.remove(request.requestId)
                    clearPresentationLocked(request.requestId)
                    completeTombstoneLocked(request)
                    request.result.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
                }
            }
        }
    }

    private fun reserve(
        request: MediaCaptureWireRequest,
        result: MediaCaptureBridgeResult,
    ): Reservation =
        synchronized(lock) {
            pruneTombstonesLocked()
            val owner = ownerForRequestLocked(request)
            val ownerUnavailable =
                when {
                    request.payload is MediaCaptureWirePayload.StartSession ->
                        owner == null || owner.closed || currentOwner !== owner ||
                            owners.any { it !== owner && it.boundaryCleanupInProgress }
                    owner != null -> owner.closed || owner.retired
                    else -> false
                }
            when {
                !engineOpen ->
                    ReservationRejected(
                        MediaCaptureWireCodec.bridgeUnavailable(
                            request.operation,
                            "engine_detached",
                        ),
                    )
                ownerUnavailable ->
                    ReservationRejected(
                        MediaCaptureWireCodec.bridgeUnavailable(
                            request.operation,
                            "activity_destroyed",
                        ),
                    )
                pending.containsKey(request.requestId) || completed.containsKey(request.requestId) ->
                    ReservationRejected(MediaCaptureWireCodec.duplicateRequest(request.operation))
                pending.size >= MAX_PENDING_REQUESTS ->
                    ReservationRejected(
                        MediaCaptureWireCodec.bridgeOverloaded(
                            request.operation,
                            "pending_requests",
                        ),
                    )
                pending.size + completed.size >= MAX_COMPLETED_TOMBSTONES ->
                    ReservationRejected(
                        MediaCaptureWireCodec.bridgeOverloaded(
                            request.operation,
                            "completed_request_tombstones",
                        ),
                    )
                else -> {
                    val pendingRequest =
                        PendingRequest(
                            request.requestId,
                            request.operation,
                            owner,
                            owner?.generation,
                            result,
                        )
                    if (owner != null) {
                        pendingRequest.trackedOwners += owner
                        owner.inFlightOperations += 1
                    }
                    pending[request.requestId] = pendingRequest
                    ReservationAccepted(pendingRequest)
                }
            }
        }

    private fun ownerForRequestLocked(request: MediaCaptureWireRequest): MediaCaptureBridgeOwner? =
        when (val payload = request.payload) {
            is MediaCaptureWirePayload.StartSession -> currentOwner
            is MediaCaptureWirePayload.SessionAction -> sessionOwners[payload.sessionHandle.value]
            is MediaCaptureWirePayload.Flash -> sessionOwners[payload.sessionHandle.value]
            is MediaCaptureWirePayload.Focus -> sessionOwners[payload.sessionHandle.value]
            is MediaCaptureWirePayload.Zoom -> sessionOwners[payload.sessionHandle.value]
            is MediaCaptureWirePayload.MediaAction ->
                if (request.operation == "release_media") {
                    null
                } else {
                    previewOwners[payload.mediaHandle.value]?.owner
                }
            is MediaCaptureWirePayload.Thumbnail -> null
            is MediaCaptureWirePayload.Materialize -> null
            is MediaCaptureWirePayload.ReleaseMaterialized -> null
            is MediaCaptureWirePayload.DismissPresentation ->
                activePresentation
                    ?.takeIf { it.requestId == payload.presentationRequestId }
                    ?.owner ?: currentOwner
        }

    private fun sessionOwner(handle: SessionHandle): MediaCaptureBridgeOwner =
        synchronized(lock) { sessionOwners[handle.value] }
            ?: throw MediaCaptureException(com.example.mediacapture.api.MediaCaptureFailure(FailureCode.SESSION_INVALID))

    private fun previewOwner(handle: MediaHandle): PreviewOwnership =
        synchronized(lock) { previewOwners[handle.value] }
            ?: throw MediaCaptureException(com.example.mediacapture.api.MediaCaptureFailure(FailureCode.MEDIA_INVALID))

    private fun leaseOwner(handle: MediaHandle): MediaCaptureBridgeOwner =
        synchronized(lock) { leaseOwners[handle.value] }
            ?: throw MediaCaptureException(com.example.mediacapture.api.MediaCaptureFailure(FailureCode.MEDIA_INVALID))

    private fun isRequestOpenLocked(request: PendingRequest): Boolean {
        if (!engineOpen || pending[request.requestId] !== request) return false
        val owner = request.owner ?: return true
        return !owner.closed && request.ownerGeneration == owner.generation
    }

    private fun closeOwnerBoundaryLocked(
        owner: MediaCaptureBridgeOwner,
        reason: String,
    ): OwnerBoundary {
        val presentation = activePresentation?.takeIf { it.owner === owner }
        owner.boundaryCleanupInProgress = true
        owner.boundaryCompletionPending = true
        owner.cleanupSessions += owner.sessions
        if (presentation != null) {
            activePresentation = null
            presentationCleanupInProgress = true
            owner.presentationCleanupPending = true
        }
        val requests =
            pending.values.filter { it.owner === owner }.also { claimed ->
                claimed.forEach { request ->
                    pending.remove(request.requestId)
                    completeTombstoneLocked(request)
                }
            }
        return OwnerBoundary(owner, presentation, requests, reason)
    }

    private suspend fun finishOwnerBoundary(boundary: OwnerBoundary) {
        withContext(mainDispatcher) { boundary.presentation?.session?.dismiss() }
        closeOwner(boundary.owner, releaseLeases = false)
        withContext(mainDispatcher) {
            synchronized(lock) {
                boundary.requests.forEach { request ->
                    val failure = MediaCaptureWireCodec.bridgeUnavailable(request.operation, boundary.reason)
                    request.result.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
                }
                boundary.owner.boundaryCompletionPending = false
                maybeFinishOwnerBoundaryLocked(boundary.owner)
            }
        }
        retireOwnerIfPossible(boundary.owner)
    }

    private suspend fun closeOwner(owner: MediaCaptureBridgeOwner, releaseLeases: Boolean) {
        synchronized(lock) {
            owner.closed = true
            if (releaseLeases) owner.engineClosing = true
        }
        runOwnerCloseAction(owner)
        val sessions = synchronized(lock) { owner.sessions.map(::SessionHandle) }
        sessions.forEach { session -> interruptSession(owner, session, scheduleRetry = false) }
        if (releaseLeases) {
            val leases = synchronized(lock) { owner.leases.map(::MediaHandle) }
            leases.forEach { handle ->
                releaseLease(
                    owner,
                    handle,
                    awaitRevocation = false,
                    scheduleRetry = false,
                )
            }
        }
        val needsRetry =
            synchronized(lock) {
                if (owner.engineClosing) {
                    owner.settlingMedia.toList().forEach { removeSettlingMediaLocked(owner, it) }
                }
                !owner.closeActionComplete || owner.cleanupSessions.isNotEmpty() ||
                    owner.cleanupLeases.isNotEmpty()
            }
        if (needsRetry) scheduleOwnerCleanup(owner)
        retireOwnerIfPossible(owner)
    }

    private suspend fun interruptSession(
        owner: MediaCaptureBridgeOwner,
        handle: SessionHandle,
        scheduleRetry: Boolean = true,
    ): Boolean {
        synchronized(lock) {
            if (!owner.retired) {
                owner.sessions += handle.value
                owner.cleanupSessions += handle.value
                if (sessionOwners[handle.value] == null || sessionOwners[handle.value] === owner) {
                    sessionOwners[handle.value] = owner
                }
            }
        }
        repeat(CLEANUP_ATTEMPTS) { attempt ->
            try {
                owner.mediaCapture.cancel(handle)
                synchronized(lock) { removeSessionLocked(owner, handle.value) }
                return true
            } catch (exception: MediaCaptureException) {
                if (exception.failure.code == FailureCode.SESSION_INVALID ||
                    exception.failure.code == FailureCode.INVALID_STATE
                ) {
                    synchronized(lock) { removeSessionLocked(owner, handle.value) }
                    return true
                }
            } catch (_: Exception) {
                // Retain ownership until the bounded retry completes.
            }
            if (attempt + 1 < CLEANUP_ATTEMPTS) delay(CLEANUP_RETRY_MILLIS)
        }
        if (scheduleRetry && synchronized(lock) { !owner.retired }) scheduleOwnerCleanup(owner)
        return false
    }

    private suspend fun releaseLease(
        owner: MediaCaptureBridgeOwner,
        handle: MediaHandle,
        awaitRevocation: Boolean? = null,
        scheduleRetry: Boolean = true,
    ): Boolean {
        val shouldAwaitRevocation = awaitRevocation ?: synchronized(lock) { !owner.engineClosing }
        synchronized(lock) {
            if (!owner.retired) {
                owner.leases += handle.value
                owner.cleanupLeases += handle.value
                if (leaseOwners[handle.value] == null || leaseOwners[handle.value] === owner) {
                    leaseOwners[handle.value] = owner
                }
            }
        }
        repeat(CLEANUP_ATTEMPTS) { attempt ->
            try {
                owner.mediaCapture.releaseMedia(handle)
                synchronized(lock) {
                    removeLeaseLocked(owner, handle.value, shouldAwaitRevocation)
                }
                retireOwnerIfPossible(owner)
                return true
            } catch (exception: MediaCaptureException) {
                if (exception.failure.code == FailureCode.MEDIA_INVALID) {
                    synchronized(lock) {
                        removeLeaseLocked(owner, handle.value, awaitRevocation = false)
                    }
                    retireOwnerIfPossible(owner)
                    return true
                }
            } catch (_: Exception) {
                // Retain ownership until the bounded retry completes.
            }
            if (attempt + 1 < CLEANUP_ATTEMPTS) delay(CLEANUP_RETRY_MILLIS)
        }
        if (scheduleRetry && synchronized(lock) { !owner.retired }) scheduleOwnerCleanup(owner)
        return false
    }

    private fun removeSessionLocked(owner: MediaCaptureBridgeOwner, sessionHandle: String) {
        if (sessionOwners[sessionHandle] === owner) sessionOwners.remove(sessionHandle)
        owner.sessions.remove(sessionHandle)
        owner.cleanupSessions.remove(sessionHandle)
        val previews = owner.previews.filterValues { it == sessionHandle }.keys.toList()
        previews.forEach { mediaHandle ->
            owner.previews.remove(mediaHandle)
            previewOwners.remove(mediaHandle)
        }
    }

    private fun adoptLeaseLocked(ownership: PreviewOwnership, media: ConfirmedMedia) {
        previewOwners.remove(media.mediaHandle.value)
        ownership.owner.previews.remove(media.mediaHandle.value)
        removeSessionLocked(ownership.owner, ownership.sessionHandle)
        ownership.owner.leases += media.mediaHandle.value
        leaseOwners[media.mediaHandle.value] = ownership.owner
        leaseMetadata[media.mediaHandle.value] = media.metadata
    }

    private fun removeLeaseLocked(
        owner: MediaCaptureBridgeOwner,
        mediaHandle: String,
        awaitRevocation: Boolean = true,
    ) {
        val wasOwned = leaseOwners[mediaHandle] === owner || mediaHandle in owner.leases
        if (leaseOwners[mediaHandle] === owner) leaseOwners.remove(mediaHandle)
        leaseMetadata.remove(mediaHandle)
        owner.leases.remove(mediaHandle)
        owner.cleanupLeases.remove(mediaHandle)
        if (awaitRevocation && wasOwned) {
            owner.settlingMedia += mediaHandle
            settlingOwners[mediaHandle] = owner
        }
    }

    private fun removeSettlingMediaLocked(owner: MediaCaptureBridgeOwner, mediaHandle: String) {
        if (settlingOwners[mediaHandle] === owner) settlingOwners.remove(mediaHandle)
        owner.settlingMedia.remove(mediaHandle)
    }

    private suspend fun retireOwnerIfPossible(owner: MediaCaptureBridgeOwner) {
        val shouldClose =
            synchronized(lock) {
                if (
                    owner.retired || owner.retiring || !owner.closed ||
                    !owner.closeActionComplete ||
                    owner.boundaryCleanupInProgress || owner.sessions.isNotEmpty() ||
                    owner.previews.isNotEmpty() || owner.leases.isNotEmpty() ||
                    owner.settlingMedia.isNotEmpty() ||
                    owner.inFlightOperations > 0 ||
                    pending.values.any { it.owner === owner } || activePresentation?.owner === owner
                ) {
                    false
                } else {
                    owner.retiring = true
                    true
                }
            }
        if (shouldClose) {
            val closed = runCatching { owner.mediaCapture.close() }.isSuccess
            if (closed) {
                val jobs =
                    synchronized(lock) {
                        owner.retiring = false
                        owner.retired = true
                        owners.remove(owner)
                        owner.eventJob to owner.cleanupJob
                    }
                jobs.first?.cancel()
                jobs.second?.cancel()
                runCatching(owner.retireAction)
                maybeCancelEngineScope()
            } else {
                synchronized(lock) { owner.retiring = false }
                scheduleOwnerCleanup(owner)
            }
        }
    }

    private fun scheduleOwnerCleanup(owner: MediaCaptureBridgeOwner) {
        val job =
            scope.launch(start = CoroutineStart.LAZY) {
                var retryDelay = CLEANUP_RETRY_MILLIS
                while (true) {
                    delay(retryDelay)
                    runOwnerCloseAction(owner)
                    val snapshot =
                        synchronized(lock) {
                            owner.cleanupSessions.map(::SessionHandle) to
                                owner.cleanupLeases.map(::MediaHandle)
                        }
                    snapshot.first.forEach { handle ->
                        interruptSession(owner, handle, scheduleRetry = false)
                    }
                    snapshot.second.forEach { handle ->
                        releaseLease(
                            owner,
                            handle,
                            awaitRevocation = !owner.engineClosing,
                            scheduleRetry = false,
                        )
                    }
                    val shouldExit =
                        synchronized(lock) {
                            if (
                                owner.closeActionComplete && owner.cleanupSessions.isEmpty() &&
                                owner.cleanupLeases.isEmpty()
                            ) {
                                owner.cleanupJob = null
                                maybeFinishOwnerBoundaryLocked(owner)
                                true
                            } else {
                                false
                            }
                        }
                    if (shouldExit) {
                        retireOwnerIfPossible(owner)
                        return@launch
                    }
                    retryDelay = (retryDelay * 2).coerceAtMost(MAX_CLEANUP_RETRY_MILLIS)
                }
            }
        val accepted =
            synchronized(lock) {
                if (owner.retired || owner.cleanupJob != null) {
                    false
                } else {
                    owner.cleanupJob = job
                    true
                }
            }
        if (accepted) {
            job.start()
        } else {
            job.cancel()
        }
    }

    private fun maybeCancelEngineScope() {
        val shouldCancel =
            synchronized(lock) {
                !engineOpen && engineCallbacksCompleted && owners.isEmpty() && queuedCallbacks == 0 &&
                    transfers.values.none { it.cleanupJob != null }
            }
        if (shouldCancel) scope.cancel()
    }

    private suspend fun runOwnerCloseAction(owner: MediaCaptureBridgeOwner): Boolean {
        val shouldRun =
            synchronized(lock) {
                if (owner.closeActionComplete || owner.closeActionRunning) {
                    false
                } else {
                    owner.closeActionRunning = true
                    true
                }
            }
        if (!shouldRun) return synchronized(lock) { owner.closeActionComplete }
        val succeeded = withContext(mainDispatcher) { runCatching(owner.closeAction).isSuccess }
        synchronized(lock) {
            owner.closeActionRunning = false
            if (succeeded) owner.closeActionComplete = true
        }
        return succeeded
    }

    private fun trackRuntimeOwner(request: PendingRequest, owner: MediaCaptureBridgeOwner): Boolean =
        synchronized(lock) {
            if (!engineOpen || owner.retired || owner.engineClosing) {
                false
            } else {
                if (request.trackedOwners.add(owner)) owner.inFlightOperations += 1
                true
            }
        }

    private suspend fun releaseRequestOwners(request: PendingRequest) {
        val tracked =
            synchronized(lock) {
                request.trackedOwners.toList().also { ownersForRequest ->
                    ownersForRequest.forEach { owner ->
                        owner.inFlightOperations = (owner.inFlightOperations - 1).coerceAtLeast(0)
                        maybeFinishOwnerBoundaryLocked(owner)
                    }
                    request.trackedOwners.clear()
                }
            }
        tracked.forEach { owner -> retireOwnerIfPossible(owner) }
    }

    private suspend fun isPlatformOwnerAlive(owner: MediaCaptureBridgeOwner): Boolean =
        withContext(mainDispatcher) { isPlatformOwnerAliveOnMain(owner) }

    private fun isPlatformOwnerAliveOnMain(owner: MediaCaptureBridgeOwner): Boolean =
        !owner.activity.isFinishing && !owner.activity.isDestroyed &&
            owner.lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.CREATED)

    private fun invalidateOwnerPermissionLocked(owner: MediaCaptureBridgeOwner) {
        if (owner.permissionInvalidated) return
        owner.permissionInvalidated = true
        owner.permissionInvalidationAction()
    }

    private fun maybeFinishOwnerBoundaryLocked(owner: MediaCaptureBridgeOwner) {
        if (
            owner.boundaryCleanupInProgress && !owner.boundaryCompletionPending &&
            owner.closeActionComplete &&
            owner.cleanupSessions.isEmpty() && owner.cleanupLeases.isEmpty() &&
            owner.inFlightOperations == 0
        ) {
            owner.boundaryCleanupInProgress = false
            if (owner.presentationCleanupPending) {
                owner.presentationCleanupPending = false
                presentationCleanupInProgress = false
            }
        }
    }

    private fun emitNativeEvent(owner: MediaCaptureBridgeOwner, event: MediaCaptureEvent) {
        val encodedEvent =
            try {
                Result.success(MediaCaptureWireCodec.event(event))
            } catch (exception: Exception) {
                Result.failure(exception)
            }
        var retireAfterEvent = false
        var sessionToClean: SessionHandle? = null
        var listenerToFail: ActiveEventListener? = null
        val delivery =
            synchronized(lock) {
                if (!engineOpen || owner.retired) return
                val shouldSend =
                    when (event) {
                        is MediaCaptureEvent.Ready ->
                            !owner.closed && event.value.sessionHandle.value in owner.sessions
                        is MediaCaptureEvent.PreviewReady ->
                            !owner.closed && event.sessionHandle.value in owner.sessions
                        is MediaCaptureEvent.SessionFailed ->
                            !owner.closed && event.sessionHandle.value in owner.sessions
                        is MediaCaptureEvent.LeaseExpired ->
                            event.mediaHandle.value in owner.leases
                        is MediaCaptureEvent.ReadRevoked ->
                            (event.mediaHandle.value in owner.settlingMedia ||
                                event.mediaHandle.value in owner.leases) &&
                                (leaseOwners[event.mediaHandle.value] == null ||
                                    leaseOwners[event.mediaHandle.value] === owner)
                        is MediaCaptureEvent.AttachmentRevoked -> false
                    }
                var outputValid = encodedEvent.isSuccess
                when (event) {
                    is MediaCaptureEvent.PreviewReady -> {
                        if (shouldSend) {
                            val existingPreview = previewOwners[event.preview.mediaHandle.value]
                            val handleAvailable =
                                leaseOwners[event.preview.mediaHandle.value] == null &&
                                    settlingOwners[event.preview.mediaHandle.value] == null &&
                                    (existingPreview == null ||
                                        existingPreview.owner === owner &&
                                        existingPreview.sessionHandle == event.sessionHandle.value)
                            if (outputValid && handleAvailable) {
                                owner.previews[event.preview.mediaHandle.value] = event.sessionHandle.value
                                previewOwners[event.preview.mediaHandle.value] =
                                    PreviewOwnership(owner, event.sessionHandle.value)
                            } else {
                                outputValid = false
                                sessionToClean = event.sessionHandle
                            }
                        }
                    }
                    is MediaCaptureEvent.SessionFailed -> removeSessionLocked(owner, event.sessionHandle.value)
                    is MediaCaptureEvent.LeaseExpired ->
                        removeLeaseLocked(owner, event.mediaHandle.value, awaitRevocation = true)
                    is MediaCaptureEvent.ReadRevoked -> {
                        removeLeaseLocked(owner, event.mediaHandle.value, awaitRevocation = false)
                        removeSettlingMediaLocked(owner, event.mediaHandle.value)
                        retireAfterEvent = true
                    }
                    else -> Unit
                }
                if (shouldSend && !outputValid) {
                    listenerToFail = eventListener
                    null
                } else {
                    val listener = eventListener.takeIf { shouldSend }
                    val envelope = encodedEvent.getOrNull()
                    if (listener != null && envelope != null) EventDelivery(listener, envelope) else null
                }
            }
        sessionToClean?.let { handle ->
            scope.launch { interruptSession(owner, handle) }
        }
        listenerToFail?.let { listener ->
            terminateEventListener(
                listener,
                MediaCaptureWireCodec.wireEncodingFailure("unknown_operation"),
            )
        }
        if (delivery != null) {
            scope.launch(mainDispatcher) {
                synchronized(lock) {
                    val current = eventListener
                    if (current === delivery.listener && current.generation == delivery.listener.generation) {
                        delivery.listener.sink.success(delivery.envelope)
                    }
                }
            }
        }
        if (retireAfterEvent) scope.launch { retireOwnerIfPossible(owner) }
    }

    private fun terminateEventListener(listener: ActiveEventListener, failure: MediaCaptureWireFailure) {
        val removed =
            synchronized(lock) {
                if (eventListener === listener) {
                    eventListener = null
                    true
                } else {
                    false
                }
            }
        if (removed) deliverEventError(listener.sink, failure)
    }

    private fun clearPresentation(requestId: String) {
        synchronized(lock) { clearPresentationLocked(requestId) }
    }

    private fun clearPresentationLocked(requestId: String) {
        if (activePresentation?.requestId == requestId) activePresentation = null
    }

    private fun completeTombstoneLocked(request: PendingRequest) {
        completed[request.requestId] = nowMillis()
    }

    private fun pruneTombstonesLocked() {
        val now = nowMillis()
        completed.entries.removeAll { now - it.value >= COMPLETED_TOMBSTONE_MILLIS }
    }

    private inline fun encodeOutput(
        operation: String,
        encode: () -> Map<String, Any?>,
    ): Map<String, Any?> =
        try {
            encode()
        } catch (failure: MediaCaptureWireFailure) {
            throw failure
        } catch (_: Exception) {
            throw MediaCaptureWireCodec.wireEncodingFailure(operation)
        }

    private fun canAdoptNewSession(owner: MediaCaptureBridgeOwner, handle: SessionHandle): Boolean =
        synchronized(lock) {
            sessionOwners[handle.value] == null && handle.value !in owner.sessions
        }

    private fun canAdoptPreview(
        owner: MediaCaptureBridgeOwner,
        session: SessionHandle,
        handle: MediaHandle,
    ): Boolean =
        synchronized(lock) {
            val preview = previewOwners[handle.value]
            leaseOwners[handle.value] == null && settlingOwners[handle.value] == null &&
                (preview == null || preview.owner === owner && preview.sessionHandle == session.value)
        }

    private fun canAdoptNewLease(handle: MediaHandle): Boolean =
        synchronized(lock) {
            leaseOwners[handle.value] == null && previewOwners[handle.value] == null &&
                settlingOwners[handle.value] == null
        }

    private fun mapCapabilityFailure(operation: String, code: FailureCode): MediaCaptureWireFailure {
        val allowed = allowedCapabilityFailures[operation].orEmpty()
        return if (code in allowed) {
            MediaCaptureWireCodec.capabilityFailure(operation, code)
        } else {
            MediaCaptureWireCodec.wireEncodingFailure(operation)
        }
    }

    private fun deliverError(result: MediaCaptureBridgeResult, failure: MediaCaptureWireFailure) {
        synchronized(lock) { queuedCallbacks += 1 }
        scope.launch(mainDispatcher) {
            try {
                result.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
            } finally {
                synchronized(lock) { queuedCallbacks = (queuedCallbacks - 1).coerceAtLeast(0) }
                maybeCancelEngineScope()
            }
        }
    }

    private fun deliverEventError(sink: MediaCaptureBridgeEventSink, failure: MediaCaptureWireFailure) {
        synchronized(lock) { queuedCallbacks += 1 }
        scope.launch(mainDispatcher) {
            try {
                sink.error(failure.code, REDACTED_ERROR_MESSAGE, failure.details)
            } finally {
                synchronized(lock) { queuedCallbacks = (queuedCallbacks - 1).coerceAtLeast(0) }
                maybeCancelEngineScope()
            }
        }
    }

    private data class PendingRequest(
        val requestId: String,
        val operation: String,
        val owner: MediaCaptureBridgeOwner?,
        val ownerGeneration: Long?,
        val result: MediaCaptureBridgeResult,
        val trackedOwners: MutableSet<MediaCaptureBridgeOwner> = linkedSetOf(),
    )

    private data class PreviewOwnership(
        val owner: MediaCaptureBridgeOwner,
        val sessionHandle: String,
    )

    private data class ActivePresentation(
        val owner: MediaCaptureBridgeOwner,
        val requestId: String,
        var session: MediaCaptureBridgePresentationSession?,
    )

    private data class PresentationDismissal(
        val presentation: ActivePresentation,
        val target: PendingRequest,
    )

    private data class ActiveEventListener(
        val generation: Long,
        val sink: MediaCaptureBridgeEventSink,
    )

    private data class EventDelivery(
        val listener: ActiveEventListener,
        val envelope: Map<String, Any?>,
    )

    private data class OwnerBoundary(
        val owner: MediaCaptureBridgeOwner,
        val presentation: ActivePresentation?,
        val requests: List<PendingRequest>,
        val reason: String,
    )

    private data class EngineBoundary(
        val owners: List<MediaCaptureBridgeOwner>,
        val presentation: ActivePresentation?,
        val requests: List<PendingRequest>,
        val listener: ActiveEventListener?,
        val transfers: List<TransferRecord>,
    )

    private data class TransferRecord(
        val reservation: MediaCaptureTransferStore.Reservation,
        var active: Boolean = false,
        var cleanupPending: Boolean = false,
        var expired: Boolean = false,
        var releaseTombstoneReserved: Boolean = false,
        var expiresAtEpochMillis: Long? = null,
        var ttlJob: Job? = null,
        var cleanupJob: Job? = null,
    )

    private sealed interface TransferReleaseDecision {
        data object AlreadyReleased : TransferReleaseDecision

        data class Claim(
            val record: TransferRecord,
            val completion: CompletableDeferred<Boolean>,
        ) : TransferReleaseDecision

        data class Join(val completion: CompletableDeferred<Boolean>) : TransferReleaseDecision

        data class Rejected(val failure: MediaCaptureWireFailure) : TransferReleaseDecision
    }

    private sealed interface Reservation

    private data class ReservationAccepted(val pending: PendingRequest) : Reservation

    private data class ReservationRejected(val failure: MediaCaptureWireFailure) : Reservation

    private companion object {
        const val MAX_PENDING_REQUESTS = 32
        const val MAX_COMPLETED_TOMBSTONES = 4096
        const val COMPLETED_TOMBSTONE_MILLIS = 300_000L
        const val MAX_ACTIVE_TRANSFERS = 4
        const val MAX_ACTIVE_TRANSFER_BYTES = 104_857_600L
        const val MAX_TRANSFER_FILE_BYTES = 52_428_800L
        const val MAX_RELEASE_TOMBSTONES = 4096
        const val TRANSFER_TTL_MILLIS = 300_000L
        const val TRANSFER_HANDLE_ATTEMPTS = 32
        const val TRANSFER_DELETE_ATTEMPTS = 3
        const val TRANSFER_RETAINED_CLEANUP_ATTEMPTS = 8
        const val CLEANUP_ATTEMPTS = 2
        const val CLEANUP_RETRY_MILLIS = 50L
        const val MAX_CLEANUP_RETRY_MILLIS = 5_000L
        const val REDACTED_ERROR_MESSAGE = "Media capture operation failed."

        val controlFailures =
            setOf(
                FailureCode.SESSION_INVALID,
                FailureCode.INVALID_STATE,
                FailureCode.INVALID_ARGUMENT,
                FailureCode.UNSUPPORTED_CAPABILITY,
                FailureCode.SYSTEM_INTERRUPTED,
            )
        val mediaTransitionFailures =
            setOf(
                FailureCode.SESSION_INVALID,
                FailureCode.MEDIA_INVALID,
                FailureCode.INVALID_STATE,
                FailureCode.INVALID_ARGUMENT,
            )
        val presentationFailures =
            setOf(
                FailureCode.PERMISSION_DENIED,
                FailureCode.PERMISSION_RESTRICTED,
                FailureCode.PERMISSION_PERMANENTLY_DENIED,
                FailureCode.RESOURCE_IN_USE,
                FailureCode.STORAGE_FULL,
                FailureCode.ENCODING_FAILED,
                FailureCode.MEDIA_INVALID,
                FailureCode.SESSION_INVALID,
                FailureCode.UNSUPPORTED_CAPABILITY,
                FailureCode.SYSTEM_INTERRUPTED,
                FailureCode.SESSION_CONFLICT,
                FailureCode.INVALID_STATE,
                FailureCode.INVALID_ARGUMENT,
                FailureCode.SESSION_TIMEOUT,
            )

        val allowedCapabilityFailures: Map<String, Set<FailureCode>> =
            mapOf(
                "start_session" to
                    setOf(
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.UNSUPPORTED_CAPABILITY,
                        FailureCode.SESSION_CONFLICT,
                    ),
                "take_photo" to
                    setOf(
                        FailureCode.SESSION_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.STORAGE_FULL,
                        FailureCode.ENCODING_FAILED,
                        FailureCode.UNSUPPORTED_CAPABILITY,
                        FailureCode.SYSTEM_INTERRUPTED,
                    ),
                "start_recording" to
                    setOf(
                        FailureCode.SESSION_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.PERMISSION_DENIED,
                        FailureCode.PERMISSION_RESTRICTED,
                        FailureCode.PERMISSION_PERMANENTLY_DENIED,
                        FailureCode.RESOURCE_IN_USE,
                        FailureCode.STORAGE_FULL,
                        FailureCode.ENCODING_FAILED,
                        FailureCode.UNSUPPORTED_CAPABILITY,
                        FailureCode.SYSTEM_INTERRUPTED,
                    ),
                "stop_recording" to
                    setOf(
                        FailureCode.SESSION_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.ENCODING_FAILED,
                        FailureCode.SYSTEM_INTERRUPTED,
                    ),
                "switch_camera" to
                    setOf(
                        FailureCode.SESSION_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.RESOURCE_IN_USE,
                        FailureCode.UNSUPPORTED_CAPABILITY,
                        FailureCode.SYSTEM_INTERRUPTED,
                    ),
                "set_flash_mode" to controlFailures,
                "set_focus_point" to controlFailures,
                "set_zoom" to controlFailures,
                "retake" to mediaTransitionFailures,
                "confirm" to mediaTransitionFailures,
                "cancel" to
                    setOf(
                        FailureCode.SESSION_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                    ),
                "release_media" to
                    setOf(
                        FailureCode.MEDIA_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                    ),
                "read_media_thumbnail" to
                    setOf(
                        FailureCode.MEDIA_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.THUMBNAIL_GENERATION_FAILED,
                        FailureCode.THUMBNAIL_GENERATION_CANCELLED,
                        FailureCode.THUMBNAIL_OVERLOADED,
                    ),
                "materialize_media_resource" to
                    setOf(
                        FailureCode.MEDIA_INVALID,
                        FailureCode.INVALID_STATE,
                        FailureCode.INVALID_ARGUMENT,
                        FailureCode.SYSTEM_INTERRUPTED,
                        FailureCode.MEDIA_EXPORT_CONFLICT,
                        FailureCode.MEDIA_EXPORT_OVERLOADED,
                        FailureCode.MEDIA_EXPORT_TOO_LARGE,
                        FailureCode.MEDIA_EXPORT_SINK_REJECTED,
                        FailureCode.MEDIA_EXPORT_READ_FAILED,
                        FailureCode.MEDIA_EXPORT_WRITE_FAILED,
                        FailureCode.MEDIA_EXPORT_CANCELLED,
                        FailureCode.MEDIA_EXPORT_TIMED_OUT,
                    ),
                "present_capture_flow" to presentationFailures,
                "dismiss_capture_flow" to emptySet(),
            )
    }
}

private fun SessionOptions.toUiConfig(): MediaCaptureUiConfig =
    MediaCaptureUiConfig(
        enabledMediaTypes = enabledMediaTypes,
        preferredCamera = preferredCamera,
        audioEnabled = audioEnabled,
        maxVideoDurationMillis = maxVideoDurationMillis,
    )
