package com.example.mediacapture.core

import com.example.mediacapture.api.AttachmentKind
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaCopySink
import com.example.mediacapture.api.MediaExportResult
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaPreview
import com.example.mediacapture.api.MediaReleased
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaThumbnail
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.RecordingStarted
import com.example.mediacapture.api.RenderAttachmentResult
import com.example.mediacapture.api.ScopedMediaRead
import com.example.mediacapture.api.SessionCancelled
import com.example.mediacapture.api.SessionCreated
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionObservation
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.api.SessionState
import com.example.mediacapture.api.ThumbnailRead
import com.example.mediacapture.framework.CaptureFramework
import com.example.mediacapture.framework.CapturedMedia
import com.example.mediacapture.framework.FrameworkException
import com.example.mediacapture.framework.MediaCaptureClock
import com.example.mediacapture.framework.MediaFileStore
import com.example.mediacapture.framework.OpaqueHandleGenerator
import com.example.mediacapture.framework.PermissionGateway
import com.example.mediacapture.framework.PreparedCapture
import com.example.mediacapture.framework.StoredMediaReference
import com.example.mediacapture.framework.StreamingMediaRead
import com.example.mediacapture.framework.ThumbnailArtifact
import com.example.mediacapture.framework.ThumbnailGenerationRequest
import com.example.mediacapture.framework.ThumbnailGenerationWork
import com.example.mediacapture.framework.ThumbnailGenerator
import com.example.mediacapture.rendering.AndroidRenderSource
import com.example.mediacapture.rendering.AndroidRenderSurfaceFactory
import com.example.mediacapture.rendering.AndroidRenderTargetAdapter
import com.example.mediacapture.rendering.MediaCaptureRenderBinding
import com.example.mediacapture.rendering.MediaCaptureRenderModuleOwner
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

internal class MediaCaptureCore(
    private val captureFramework: CaptureFramework,
    private val permissionGateway: PermissionGateway,
    private val fileStore: MediaFileStore,
    private val thumbnailGenerator: ThumbnailGenerator,
    private val clock: MediaCaptureClock,
    private val handleGenerator: OpaqueHandleGenerator,
    parentScope: CoroutineScope,
    workerDispatcher: CoroutineDispatcher,
    private val ioDispatcher: CoroutineDispatcher,
    private val renderSurfaceFactory: AndroidRenderSurfaceFactory? = null,
) : MediaCapture {
    private val mutex = Mutex()
    private val frameworkMutex = Mutex()
    private val residueMutex = Mutex()
    private val ownedJob = SupervisorJob(parentScope.coroutineContext[Job])
    private val scope = CoroutineScope(parentScope.coroutineContext + ownedJob + workerDispatcher)
    private val mutableEvents = MutableSharedFlow<MediaCaptureEvent>(extraBufferCapacity = 64)
    private val sessions = mutableMapOf<SessionHandle, SessionRecord>()
    private val media = mutableMapOf<MediaHandle, MediaRecord>()
    private val usedHandleValues = mutableSetOf<String>()
    private val thumbnailJobs = mutableMapOf<MediaHandle, ManagedThumbnailJob>()
    private val exportJobs = mutableMapOf<MediaHandle, ManagedExportJob>()
    private val pendingDeletes = mutableSetOf<StoredMediaReference>()
    private val scheduledDeleteRetries = mutableSetOf<StoredMediaReference>()
    private var restartResidueCleaned = false
    private var frameworkState: FrameworkState = FrameworkState.Available
    private var renderModuleOwner = MediaCaptureRenderModuleOwner()
    private var closed = false

    internal var thumbnailCopyBeforeClaimForTest: (suspend (ByteArray) -> Unit)? = null
    internal var renderViewBeforeRegistrationForTest: (suspend () -> Unit)? = null
    internal var attachmentBeforeCommitForTest: (suspend () -> Unit)? = null
    internal var exportCommitAfterSinkForTest: (suspend () -> Unit)? = null
    internal var exportReservationInsideMutexForTest: (suspend (MediaHandle) -> Unit)? = null
    internal var exportBufferAllocationChangedForTest: ((Int) -> Unit)? = null

    override val events: SharedFlow<MediaCaptureEvent> = mutableEvents.asSharedFlow()

    override suspend fun permissionState(resource: PermissionResource): PermissionState =
        permissionGateway.currentState(resource)

    override suspend fun startSession(options: SessionOptions): SessionCreated {
        val optionsSnapshot = options.snapshot()
        validateOptions(optionsSnapshot)
        cleanupRestartResidueOnce()
        val record =
            mutex.withLock {
                ensureOpenLocked()
                pruneExpiredTombstonesLocked()
                if (frameworkState !is FrameworkState.Available ||
                    sessions.values.any { !it.state.isTerminal }
                ) {
                    fail(FailureCode.SESSION_CONFLICT)
                }
                val handle = SessionHandle(newUniqueHandleLocked(FailureCode.RESOURCE_IN_USE))
                SessionRecord(handle, optionsSnapshot).also {
                    sessions[handle] = it
                    frameworkState = FrameworkState.Owned(it)
                }
            }
        val job =
            scope.launch(start = CoroutineStart.LAZY) {
                initialize(record.handle, record.epoch)
            }
        mutex.withLock {
            sessions[record.handle]?.takeIf { it.epoch == record.epoch }?.initializeJob = job
        }
        job.start()
        return SessionCreated(record.handle)
    }

    private suspend fun initialize(handle: SessionHandle, epoch: Long) {
        var frameworkTouched = false
        try {
            val permission = resolvePermission(PermissionResource.CAMERA)
            if (permission != PermissionState.GRANTED) {
                failSession(handle, epoch, permission.toFailureCode())
                return
            }
            val options =
                mutex.withLock {
                    val record = sessions[handle]
                    if (record == null || record.epoch != epoch ||
                        record.state != SessionState.REQUESTING_PERMISSION
                    ) {
                        return
                    }
                    record.updateState(SessionState.PREPARING)
                    record.options
                }
            frameworkTouched = true
            val prepared = frameworkMutex.withLock { captureFramework.prepare(options) }.snapshot()
            validatePrepared(prepared)
            val committed =
                mutex.withLock {
                    val record = sessions[handle]
                    if (record == null || record.epoch != epoch || record.state != SessionState.PREPARING) {
                        false
                    } else {
                        record.prepared = prepared
                        val ready = prepared.toReady(handle)
                        record.updateState(SessionState.READY, ready = ready)
                        true
                    }
                }
            if (committed) {
                mutableEvents.emit(MediaCaptureEvent.Ready(prepared.toReady(handle)))
            } else {
                closeFrameworkForStaleSession(handle)
            }
        } catch (exception: kotlinx.coroutines.CancellationException) {
            if (frameworkTouched) closeFrameworkForStaleSession(handle)
            throw exception
        } catch (exception: FrameworkException) {
            failSession(handle, epoch, exception.failureCode)
        } catch (exception: MediaCaptureException) {
            failSession(handle, epoch, exception.failure.code)
        } finally {
            mutex.withLock {
                sessions[handle]?.takeIf { it.epoch == epoch }?.initializeJob = null
            }
        }
    }

    override suspend fun takePhoto(sessionHandle: SessionHandle): MediaPreview {
        val start =
            beginFrameworkOperation(
                sessionHandle,
                expectedStates = setOf(SessionState.READY),
                takeLiveAttachment = true,
            ) { session ->
                if (MediaType.PHOTO !in session.options.enabledMediaTypes) {
                    fail(FailureCode.UNSUPPORTED_CAPABILITY)
                }
            }
        var captured: CapturedMedia? = null
        var committed = false
        var result: MediaPreview? = null
        var cancellation: kotlinx.coroutines.CancellationException? = null
        var failure: FailureCode? = null
        try {
            cleanupAttachment(start.attachment)
            captured =
                withOwnedFrameworkOperation(start.operation) { captureFramework.takePhoto() }
            coroutineContext.ensureActive()
            validateMetadata(captured.metadata, MediaType.PHOTO)
            val preview =
                commitCapturedPreview(
                    start.operation,
                    captured,
                    expectedRecordingGeneration = null,
                )
            committed = true
            result = preview
        } catch (exception: kotlinx.coroutines.CancellationException) {
            cancellation = exception
        } catch (exception: FrameworkException) {
            failure = exception.failureCode
        } catch (exception: MediaCaptureException) {
            failure = exception.failure.code
        } finally {
            if (!committed && captured != null) cleanupUncommittedCapture(captured.reference)
            withContext(NonCancellable) { adoptFrameworkPendingCleanup() }
            finishFrameworkOperation(start.operation)
        }
        cancellation?.let { throw it }
        failure?.let {
            handleOperationFailure(start.operation.sessionHandle, start.operation.epoch, it)
        }
        return requireNotNull(result)
    }

    override suspend fun startRecording(sessionHandle: SessionHandle): RecordingStarted {
        val start =
            beginFrameworkOperation(
                sessionHandle,
                expectedStates = setOf(SessionState.READY),
            ) { session ->
                if (MediaType.VIDEO !in session.options.enabledMediaTypes) {
                    fail(FailureCode.UNSUPPORTED_CAPABILITY)
                }
            }
        val options = start.operation.options
        var recordingStartedInFramework = false
        var committed = false
        var result: RecordingStarted? = null
        var cancellation: kotlinx.coroutines.CancellationException? = null
        var failure: FailureCode? = null
        try {
            if (options.audioEnabled) {
                val microphone = resolvePermission(PermissionResource.MICROPHONE)
                if (microphone != PermissionState.GRANTED) {
                    throw MediaCaptureException(MediaCaptureFailure(microphone.toFailureCode()))
                }
            }
            withOwnedFrameworkOperation(start.operation) {
                captureFramework.startRecording(
                    audioEnabled = options.audioEnabled,
                    maxDurationMillis = options.maxVideoDurationMillis,
                )
            }
            recordingStartedInFramework = true
            val recordingGeneration =
                mutex.withLock {
                    val session = requireOperationSessionLocked(start.operation, SessionState.READY)
                    session.recordingGeneration++
                    session.recordingStop = RecordingStop(session.recordingGeneration)
                    session.updateState(SessionState.RECORDING)
                    session.recordingGeneration
                }
            committed = true
            scheduleAutomaticRecordingStop(start.operation.sessionHandle, recordingGeneration)
            result = RecordingStarted(start.operation.sessionHandle, options.audioEnabled)
        } catch (exception: kotlinx.coroutines.CancellationException) {
            cancellation = exception
        } catch (exception: FrameworkException) {
            failure = exception.failureCode
        } catch (exception: MediaCaptureException) {
            failure = exception.failure.code
        } finally {
            if (!committed && recordingStartedInFramework) {
                withContext(NonCancellable) {
                    frameworkMutex.withLock { bestEffortSuspend { captureFramework.cancelRecording() } }
                }
            }
            withContext(NonCancellable) { adoptFrameworkPendingCleanup() }
            finishFrameworkOperation(start.operation)
        }
        cancellation?.let { throw it }
        failure?.let {
            handleOperationFailure(start.operation.sessionHandle, start.operation.epoch, it)
        }
        return requireNotNull(result)
    }

    override suspend fun stopRecording(sessionHandle: SessionHandle): MediaPreview =
        stopRecordingInternal(sessionHandle, expectedGeneration = null, emitAsEvent = false)

    private suspend fun stopRecordingInternal(
        sessionHandle: SessionHandle,
        expectedGeneration: Long?,
        emitAsEvent: Boolean,
    ): MediaPreview {
        val claim = claimRecordingStop(sessionHandle, expectedGeneration)
        if (claim is RecordingStopClaim.Preview) return claim.preview
        if (claim is RecordingStopClaim.Await) return claim.outcome.await()
        claim as RecordingStopClaim.Execute
        if (!emitAsEvent) claim.timer?.cancel()
        var captured: CapturedMedia? = null
        var committed = false
        var result: MediaPreview? = null
        var cancellation: kotlinx.coroutines.CancellationException? = null
        var failure: FailureCode? = null
        try {
            cleanupAttachment(claim.attachment)
            captured =
                withOwnedFrameworkOperation(claim.operation) { captureFramework.stopRecording() }
            coroutineContext.ensureActive()
            validateMetadata(captured.metadata, MediaType.VIDEO)
            val preview =
                commitCapturedPreview(
                    claim.operation,
                    captured,
                    expectedRecordingGeneration = claim.generation,
                )
            committed = true
            result = preview
        } catch (exception: kotlinx.coroutines.CancellationException) {
            cancellation = exception
        } catch (exception: FrameworkException) {
            failure = exception.failureCode
        } catch (exception: MediaCaptureException) {
            failure = exception.failure.code
        } finally {
            if (!committed && captured != null) cleanupUncommittedCapture(captured.reference)
            withContext(NonCancellable) { adoptFrameworkPendingCleanup() }
            finishFrameworkOperation(claim.operation)
        }
        result?.let { preview ->
            claim.stop.outcome.complete(preview)
            if (emitAsEvent) {
                mutableEvents.emit(
                    MediaCaptureEvent.PreviewReady(claim.operation.sessionHandle, preview),
                )
            }
            return preview
        }
        cancellation?.let {
            claim.stop.outcome.completeExceptionally(it)
            throw it
        }
        val failureCode = requireNotNull(failure)
        claim.stop.outcome.completeExceptionally(
            MediaCaptureException(MediaCaptureFailure(failureCode)),
        )
        handleOperationFailure(
            claim.operation.sessionHandle,
            claim.operation.epoch,
            failureCode,
        )
    }

    override suspend fun switchCamera(sessionHandle: SessionHandle) {
        val operation =
            beginFrameworkOperation(
                sessionHandle,
                expectedStates = setOf(SessionState.READY),
            ) { session ->
                if (session.prepared?.availableCameras?.size != 2) {
                    fail(FailureCode.UNSUPPORTED_CAPABILITY)
                }
            }
        var failure: FailureCode? = null
        try {
            val prepared =
                withOwnedFrameworkOperation(operation.operation) {
                    captureFramework.switchCamera()
                }.snapshot()
            validatePrepared(prepared)
            mutex.withLock {
                val session = requireOperationSessionLocked(operation.operation, SessionState.READY)
                session.prepared = prepared
                session.updateState(SessionState.READY, ready = prepared.toReady(session.handle))
            }
        } catch (exception: FrameworkException) {
            failure = exception.failureCode
        } catch (exception: MediaCaptureException) {
            failure = exception.failure.code
        } finally {
            withContext(NonCancellable) { adoptFrameworkPendingCleanup() }
            finishFrameworkOperation(operation.operation)
        }
        failure?.let {
            handleOperationFailure(operation.operation.sessionHandle, operation.operation.epoch, it)
        }
    }

    override suspend fun setFlashMode(sessionHandle: SessionHandle, flashMode: FlashMode) {
        val operation = controlOperation(sessionHandle) { session ->
            if (flashMode !in requireNotNull(session.prepared).supportedFlashModes) {
                fail(FailureCode.UNSUPPORTED_CAPABILITY)
            }
        }
        applyControl(operation) { captureFramework.setFlashMode(flashMode) }
    }

    override suspend fun setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double,
    ) {
        if (!normalizedX.isFinite() || normalizedX !in 0.0..1.0 ||
            !normalizedY.isFinite() || normalizedY !in 0.0..1.0
        ) {
            fail(FailureCode.INVALID_ARGUMENT)
        }
        val operation = controlOperation(sessionHandle) { session ->
            if (session.prepared?.focusPointSupported != true) {
                fail(FailureCode.UNSUPPORTED_CAPABILITY)
            }
        }
        applyControl(operation) { captureFramework.setFocusPoint(normalizedX, normalizedY) }
    }

    override suspend fun setZoom(sessionHandle: SessionHandle, zoomFactor: Double) {
        if (!zoomFactor.isFinite()) fail(FailureCode.INVALID_ARGUMENT)
        val operation = controlOperation(sessionHandle) { session ->
            val prepared = requireNotNull(session.prepared)
            if (zoomFactor !in prepared.minZoomFactor..prepared.maxZoomFactor) {
                fail(FailureCode.INVALID_ARGUMENT)
            }
        }
        applyControl(operation) { captureFramework.setZoom(zoomFactor) }
    }

    private suspend fun controlOperation(
        handle: SessionHandle,
        validation: (SessionRecord) -> Unit,
    ): FrameworkOperationStart =
        beginFrameworkOperation(
            handle,
            expectedStates = setOf(SessionState.READY, SessionState.RECORDING),
            validation = validation,
        )

    private suspend fun applyControl(
        operation: FrameworkOperationStart,
        action: suspend () -> Unit,
    ) {
        var failure: FailureCode? = null
        try {
            withOwnedFrameworkOperation(operation.operation) { action() }
            mutex.withLock {
                requireOperationSessionLocked(
                    operation.operation,
                    SessionState.READY,
                    SessionState.RECORDING,
                )
            }
        } catch (exception: FrameworkException) {
            failure = exception.failureCode
        } catch (exception: MediaCaptureException) {
            failure = exception.failure.code
        } finally {
            withContext(NonCancellable) { adoptFrameworkPendingCleanup() }
            finishFrameworkOperation(operation.operation)
        }
        failure?.let {
            handleOperationFailure(operation.operation.sessionHandle, operation.operation.epoch, it)
        }
    }

    private suspend fun beginFrameworkOperation(
        handle: SessionHandle,
        expectedStates: Set<SessionState>,
        takeLiveAttachment: Boolean = false,
        validation: (SessionRecord) -> Unit = {},
    ): FrameworkOperationStart {
        val callerJob = coroutineContext[Job]
        while (true) {
            val acquisition =
                mutex.withLock {
                    val session = requireSessionLocked(handle)
                    requireSessionState(session, *expectedStates.toTypedArray())
                    validation(session)
                    val existing = session.activeOperation
                    if (existing != null) {
                        if (existing.job === callerJob) fail(FailureCode.RESOURCE_IN_USE)
                        OperationAcquisition.Wait(existing.settled)
                    } else {
                        requireFrameworkOwnedLocked(session)
                        val operation =
                            FrameworkOperation(
                                sessionHandle = session.handle,
                                epoch = session.epoch,
                                generation = ++session.operationGeneration,
                                options = session.options,
                                job = callerJob,
                            )
                        session.activeOperation = operation
                        OperationAcquisition.Acquired(
                            FrameworkOperationStart(
                                operation,
                                if (takeLiveAttachment) {
                                    takeAttachmentLocked(session.liveAttachment)
                                } else {
                                    null
                                },
                            ),
                        )
                    }
                }
            when (acquisition) {
                is OperationAcquisition.Acquired -> return acquisition.start
                is OperationAcquisition.Wait -> acquisition.settled.await()
            }
        }
    }

    private suspend fun claimRecordingStop(
        handle: SessionHandle,
        expectedGeneration: Long?,
    ): RecordingStopClaim {
        val callerJob = coroutineContext[Job]
        while (true) {
            val acquisition =
                mutex.withLock {
                    val session = requireSessionLocked(handle)
                    if (session.state == SessionState.PREVIEWING) {
                        return RecordingStopClaim.Preview(previewForSessionLocked(session))
                    }
                    requireSessionState(session, SessionState.RECORDING)
                    val generation = session.recordingGeneration
                    if (expectedGeneration != null && generation != expectedGeneration) {
                        fail(FailureCode.INVALID_STATE)
                    }
                    val stop = requireNotNull(session.recordingStop)
                    if (stop.claimed) return RecordingStopClaim.Await(stop.outcome)
                    val existing = session.activeOperation
                    if (existing != null) {
                        if (existing.job === callerJob) fail(FailureCode.RESOURCE_IN_USE)
                        OperationAcquisition.Wait(existing.settled)
                    } else {
                        requireFrameworkOwnedLocked(session)
                        val operation =
                            FrameworkOperation(
                                sessionHandle = session.handle,
                                epoch = session.epoch,
                                generation = ++session.operationGeneration,
                                options = session.options,
                                job = callerJob,
                            )
                        session.activeOperation = operation
                        stop.claimed = true
                        val timer = session.recordingTimerJob
                        session.recordingTimerJob = null
                        return RecordingStopClaim.Execute(
                            operation,
                            generation,
                            stop,
                            timer,
                            takeAttachmentLocked(session.liveAttachment),
                        )
                    }
                }
            acquisition as OperationAcquisition.Wait
            acquisition.settled.await()
        }
    }

    private suspend fun <T> withOwnedFrameworkOperation(
        operation: FrameworkOperation,
        action: suspend () -> T,
    ): T =
        frameworkMutex.withLock {
            operation.job?.ensureActive()
            val valid =
                mutex.withLock {
                    val session = sessions[operation.sessionHandle]
                    session != null && session.epoch == operation.epoch &&
                        session.activeOperation === operation && operation.active.get() &&
                        frameworkState.ownedBy(session)
                }
            operation.job?.ensureActive()
            if (!valid) fail(FailureCode.INVALID_STATE)
            action()
        }

    private suspend fun finishFrameworkOperation(operation: FrameworkOperation) {
        withContext(NonCancellable) {
            if (operation.finished.compareAndSet(false, true)) {
                operation.active.set(false)
                mutex.withLock {
                    sessions[operation.sessionHandle]
                        ?.takeIf { it.activeOperation === operation }
                        ?.activeOperation = null
                }
                operation.settled.complete(Unit)
            } else {
                operation.settled.await()
            }
        }
    }

    private fun requireOperationSessionLocked(
        operation: FrameworkOperation,
        vararg expectedStates: SessionState,
    ): SessionRecord {
        val session = sessions[operation.sessionHandle]
        if (session == null || session.epoch != operation.epoch ||
            session.activeOperation !== operation || !operation.active.get() ||
            !frameworkState.ownedBy(session)
        ) {
            fail(FailureCode.INVALID_STATE)
        }
        requireSessionState(session, *expectedStates)
        return session
    }

    private fun requireFrameworkOwnedLocked(session: SessionRecord) {
        if (!frameworkState.ownedBy(session)) fail(FailureCode.INVALID_STATE)
    }

    private fun invalidateFrameworkOperationLocked(session: SessionRecord): FrameworkOperation? {
        val operation = session.activeOperation ?: return null
        session.activeOperation = null
        operation.active.set(false)
        return operation
    }

    private suspend fun drainFrameworkOperation(operation: FrameworkOperation?): Boolean {
        operation ?: return true
        val callerJob = coroutineContext[Job]
        if (operation.job === callerJob) {
            finishFrameworkOperation(operation)
            return true
        }
        operation.job?.cancel()
        val settled =
            withContext(NonCancellable) {
                withTimeoutOrNull(FRAMEWORK_DRAIN_TIMEOUT_MILLIS) {
                    operation.settled.await()
                    true
                } ?: false
            }
        if (!settled) poisonFrameworkForTimedOutOperation(operation)
        return settled
    }

    private suspend fun poisonFrameworkForTimedOutOperation(operation: FrameworkOperation) {
        mutex.withLock {
            val state = frameworkState
            if (state is FrameworkState.Owned &&
                state.session.handle == operation.sessionHandle
            ) {
                frameworkState = FrameworkState.Poisoned(operation.sessionHandle)
            }
        }
    }

    override suspend fun retake(mediaHandle: MediaHandle): SessionHandle {
        val plan =
            mutex.withLock {
                val mediaRecord = requireMediaLocked(mediaHandle)
                requireMediaState(mediaRecord, MediaState.PREVIEW)
                val session = requireSessionLocked(mediaRecord.sessionHandle)
                requireSessionState(session, SessionState.PREVIEWING)
                mediaRecord.markDiscardedPendingCleanup(clock.nowEpochMillis())
                session.previewHandle = null
                session.updateState(
                    SessionState.READY,
                    ready = session.prepared?.toReady(session.handle),
                    preview = null,
                )
                MediaTransitionPlan(
                    mediaRecord,
                    session,
                    invalidateFrameworkOperationLocked(session),
                    takeAttachmentLocked(mediaRecord.previewAttachment),
                )
            }
        drainFrameworkOperation(plan.operation)
        cleanupAttachment(plan.attachment)
        deleteMedia(plan.media.reference)
        return plan.session.handle
    }

    override suspend fun confirm(mediaHandle: MediaHandle): ConfirmedMedia {
        val plan =
            mutex.withLock {
                val mediaRecord = requireMediaLocked(mediaHandle)
                requireMediaState(mediaRecord, MediaState.PREVIEW)
                val session = requireSessionLocked(mediaRecord.sessionHandle)
                requireSessionState(session, SessionState.PREVIEWING)
                val expiresAt = safeDeadline(clock.nowEpochMillis(), LEASE_TTL_MILLIS)
                mediaRecord.state = MediaState.LEASED
                mediaRecord.leaseExpiresAtMillis = expiresAt
                session.recordingTimerJob?.cancel()
                session.recordingTimerJob = null
                val operation = invalidateFrameworkOperationLocked(session)
                session.updateState(SessionState.COMPLETED, preview = null)
                session.terminalAtMillis = clock.nowEpochMillis()
                session.epoch++
                ConfirmPlan(
                    session,
                    mediaRecord,
                    expiresAt,
                    operation,
                    takeAttachmentLocked(mediaRecord.previewAttachment),
                )
            }
        drainFrameworkOperation(plan.operation)
        cleanupAttachment(plan.attachment)
        closeFrameworkForSession(plan.session, cancelRecording = false)
        scheduleLeaseExpiry(plan.media)
        return ConfirmedMedia(plan.media.handle, plan.media.metadata, plan.expiresAt)
    }

    override suspend fun cancel(sessionHandle: SessionHandle): SessionCancelled {
        val plan =
            mutex.withLock {
                val session = requireSessionLocked(sessionHandle)
                session.cancelledResult?.let { return it }
                requireSessionState(
                    session,
                    SessionState.REQUESTING_PERMISSION,
                    SessionState.PREPARING,
                    SessionState.READY,
                    SessionState.RECORDING,
                    SessionState.PREVIEWING,
                )
                val wasRecording = session.state == SessionState.RECORDING
                val operation = invalidateFrameworkOperationLocked(session)
                session.epoch++
                session.recordingTimerJob?.cancel()
                session.recordingTimerJob = null
                val result = SessionCancelled(session.handle)
                session.cancelledResult = result
                session.updateState(SessionState.CANCELLED, preview = null)
                session.terminalAtMillis = clock.nowEpochMillis()
                val preview = session.previewHandle?.let(media::get)
                preview?.markDiscardedPendingCleanup(clock.nowEpochMillis())
                session.previewHandle = null
                CancelPlan(
                    session,
                    result,
                    session.initializeJob,
                    operation,
                    wasRecording,
                    takeAttachmentLocked(session.liveAttachment),
                    preview,
                    preview?.let { takeAttachmentLocked(it.previewAttachment) },
                )
            }
        drainInitializationJob(plan.initializeJob, plan.session)
        drainFrameworkOperation(plan.operation)
        cleanupAttachment(plan.liveAttachment)
        cleanupAttachment(plan.previewAttachment)
        closeFrameworkForSession(plan.session, cancelRecording = plan.wasRecording)
        plan.preview?.let { deleteMedia(it.reference) }
        return plan.result
    }

    override suspend fun <T> withMediaRead(
        mediaHandle: MediaHandle,
        block: suspend (ScopedMediaRead) -> T,
    ): T {
        val lease = activeLeaseOrExpire(mediaHandle)
        val read = fileStore.openRead(lease.reference, lease.metadata.byteLength, lease.metadata.contentType)
        val stillActive =
            mutex.withLock {
                media[mediaHandle]?.let {
                    it === lease && it.state == MediaState.LEASED &&
                        clock.nowEpochMillis() < requireNotNull(it.leaseExpiresAtMillis)
                } == true
            }
        if (!stillActive) {
            withContext(NonCancellable) { bestEffortSuspend { read.close() } }
            fail(FailureCode.INVALID_STATE)
        }
        return try {
            block(read)
        } finally {
            withContext(NonCancellable) { bestEffortSuspend { read.close() } }
        }
    }

    override suspend fun releaseMedia(mediaHandle: MediaHandle): MediaReleased {
        val transition =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                record.releasedResult?.let { return it }
                requireMediaState(record, MediaState.LEASED, MediaState.RELEASE_GRACE, MediaState.RELEASED)
                val result = MediaReleased(record.handle)
                record.releasedResult = result
                if (record.state != MediaState.LEASED) {
                    ReleaseTransition(result, null, null, null)
                } else {
                    record.state = MediaState.RELEASE_GRACE
                    val deadline = safeDeadline(clock.nowEpochMillis(), READ_GRACE_MILLIS)
                    record.graceExpiresAtMillis = deadline
                    val thumbnailJob = thumbnailJobs[record.handle]
                    val thumbnailClaimed =
                        thumbnailJob?.claimFailureLocked(FailureCode.INVALID_STATE) == true
                    val exportJob = exportJobs[record.handle]
                    val exportClaimed =
                        exportJob?.claimFailureLocked(FailureCode.INVALID_STATE) == true
                    ReleaseTransition(
                        result,
                        if (thumbnailClaimed) thumbnailJob else null,
                        if (exportClaimed) exportJob else null,
                        deadline,
                    )
                }
            }
        transition.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
        transition.exportJob?.finishClaimedFailure(cancelWorker = true)
        transition.graceDeadline?.let { scheduleReadGrace(mediaHandle, MediaState.RELEASE_GRACE, it) }
        return transition.result
    }

    override suspend fun createRenderView(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView {
        coroutineContext.ensureActive()
        val moduleOwner =
            mutex.withLock {
                ensureOpenLocked()
                renderModuleOwner
        }
        if (owner.ownerGeneration <= 0) fail(FailureCode.INVALID_ARGUMENT)
        val factory = renderSurfaceFactory ?: fail(FailureCode.INVALID_STATE)
        var createdSurface: MediaCaptureRenderView? = null
        try {
            val surface =
                withContext(NonCancellable) {
                    factory.create(owner).also { createdSurface = it }.also {
                        renderViewBeforeRegistrationForTest?.invoke()
                    }
                }
            val registered =
                withContext(NonCancellable) {
                    mutex.withLock {
                        if (closed || renderModuleOwner !== moduleOwner) {
                            false
                        } else {
                            surface.registerModuleOwner(moduleOwner)
                            true
                        }
                    }
                }
            if (!registered) {
                withContext(NonCancellable) { surface.abandonFactoryOutput() }
                fail(FailureCode.INVALID_STATE)
            }
            val weakCore = WeakReference(this)
            val weakSurface = WeakReference(surface)
            withContext(NonCancellable) {
                surface.setOwnerDestroyedCallback {
                    val ownedSurface = weakSurface.get() ?: return@setOwnerDestroyedCallback
                    weakCore.get()?.scope?.launch {
                        weakCore.get()?.onSurfaceLifecycleDestroyed(ownedSurface)
                    }
                }
            }
            coroutineContext.ensureActive()
            return surface
        } catch (exception: Throwable) {
            withContext(NonCancellable) { createdSurface?.abandonFactoryOutput() }
            throw exception
        }
    }

    override suspend fun attachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        validateSurface(surface, ownerGeneration)
        return attachLivePreview(sessionHandle, surface.renderTarget, ownerGeneration)
    }

    internal suspend fun attachLivePreview(
        sessionHandle: SessionHandle,
        adapter: AndroidRenderTargetAdapter,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        val sourceAndScope =
            mutex.withLock {
                val session = requireSessionLocked(sessionHandle)
                requireSessionState(session, SessionState.READY, SessionState.RECORDING)
                AttachmentScope.Live(session, requireNotNull(session.prepared).liveRenderSource)
            }
        return attach(sourceAndScope, adapter, ownerGeneration)
    }

    override suspend fun detachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        validateSurfaceIdentity(surface, ownerGeneration)
        return detachLivePreview(sessionHandle, surface.renderTarget, ownerGeneration)
    }

    internal suspend fun detachLivePreview(
        sessionHandle: SessionHandle,
        adapter: AndroidRenderTargetAdapter,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        val cleanup =
            mutex.withLock {
                val session = requireSessionLocked(sessionHandle)
                detachAttachmentLocked(
                    session.liveAttachment,
                    adapter,
                    ownerGeneration,
                )
            }
        cleanupAttachment(cleanup)
        return RenderAttachmentResult(AttachmentKind.LIVE_PREVIEW, ownerGeneration)
    }

    override suspend fun attachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        validateSurface(surface, ownerGeneration)
        return attachUnconfirmedPreview(mediaHandle, surface.renderTarget, ownerGeneration)
    }

    internal suspend fun attachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        adapter: AndroidRenderTargetAdapter,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        val sourceInput =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                requireMediaState(record, MediaState.PREVIEW)
                record.reference to record.metadata
            }
        val source =
            frameworkMutex.withLock {
                captureFramework.previewRenderSource(sourceInput.first, sourceInput.second)
            }
        val scope =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                requireMediaState(record, MediaState.PREVIEW)
                AttachmentScope.Preview(record, source)
            }
        return attach(scope, adapter, ownerGeneration)
    }

    override suspend fun detachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        validateSurfaceIdentity(surface, ownerGeneration)
        return detachUnconfirmedPreview(mediaHandle, surface.renderTarget, ownerGeneration)
    }

    internal suspend fun detachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        adapter: AndroidRenderTargetAdapter,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        val cleanup =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                detachAttachmentLocked(record.previewAttachment, adapter, ownerGeneration)
            }
        cleanupAttachment(cleanup)
        return RenderAttachmentResult(AttachmentKind.UNCONFIRMED_PREVIEW, ownerGeneration)
    }

    private suspend fun attach(
        scopeTarget: AttachmentScope,
        adapter: AndroidRenderTargetAdapter,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        if (ownerGeneration <= 0) fail(FailureCode.INVALID_ARGUMENT)
        val phase =
            mutex.withLock {
                val slot = scopeTarget.currentSlotOrFail()
                val current = slot.binding
                if (current != null && current.generation == ownerGeneration) {
                    if (current.adapter === adapter && current.committed.get()) {
                        return RenderAttachmentResult(scopeTarget.kind, ownerGeneration)
                    }
                    fail(FailureCode.ATTACHMENT_TARGET_CONFLICT)
                }
                if (ownerGeneration <= slot.highWatermark) {
                    fail(FailureCode.ATTACHMENT_GENERATION_RETIRED)
                }
                slot.highWatermark = ownerGeneration
                val old = takeAttachmentLocked(slot)
                val binding = AttachmentBinding(ownerGeneration, adapter)
                slot.binding = binding
                AttachmentPhase(slot, binding, old)
            }
        phase.binding.renderBinding.setAsyncFailureHandler {
            scope.launch { handleRenderAsyncFailure(scopeTarget, phase) }
        }
        if (phase.binding.cleanupStarted.get()) {
            phase.binding.renderBinding.clearAsyncFailureHandler()
        }
        cleanupAttachment(phase.oldBinding)
        if (!phase.binding.attachClaimed.compareAndSet(false, true)) {
            fail(FailureCode.INVALID_STATE)
        }
        phase.binding.attachOwner.set(coroutineContext[Job])
        if (!phase.binding.active.get()) {
            phase.binding.attachSettled.complete(Unit)
            cleanupAttachment(phase.binding.toCleanup(scopeTarget.kind))
            fail(FailureCode.INVALID_STATE)
        }
        try {
            adapter.attach(
                phase.binding.renderBinding,
                scopeTarget.source,
                phase.binding.mutationGate,
            )
        } catch (exception: kotlinx.coroutines.CancellationException) {
            rollbackAttachment(scopeTarget, phase)
            throw exception
        } catch (exception: MediaCaptureException) {
            rollbackAttachment(scopeTarget, phase)
            fail(exception.failure.code)
        } catch (_: Exception) {
            rollbackAttachment(scopeTarget, phase)
            fail(FailureCode.SYSTEM_INTERRUPTED)
        } finally {
            phase.binding.attachSettled.complete(Unit)
        }
        val committed =
            try {
                attachmentBeforeCommitForTest?.invoke()
                mutex.withLock {
                    val currentSlot = scopeTarget.currentSlotOrNull()
                    if (currentSlot === phase.slot && currentSlot.binding === phase.binding &&
                        scopeTarget.isStillAttachable() && phase.binding.mutationGate.commit()
                    ) {
                        phase.binding.committed.set(true)
                        true
                    } else {
                        if (currentSlot === phase.slot && currentSlot.binding === phase.binding) {
                            currentSlot.binding = null
                            phase.binding.active.set(false)
                            phase.binding.mutationGate.invalidate()
                        }
                        false
                    }
                }
            } catch (exception: kotlinx.coroutines.CancellationException) {
                rollbackAttachment(scopeTarget, phase)
                throw exception
            }
        if (!committed) {
            cleanupAttachment(phase.binding.toCleanup(scopeTarget.kind))
            fail(FailureCode.INVALID_STATE)
        }
        try {
            coroutineContext.ensureActive()
            adapter.commitCallbacks(phase.binding.renderBinding)
            coroutineContext.ensureActive()
        } catch (exception: kotlinx.coroutines.CancellationException) {
            rollbackAttachment(scopeTarget, phase)
            throw exception
        } catch (_: Exception) {
            rollbackAttachment(scopeTarget, phase)
            fail(FailureCode.SYSTEM_INTERRUPTED)
        }
        return RenderAttachmentResult(scopeTarget.kind, ownerGeneration)
    }

    private suspend fun clearPendingAttachment(scope: AttachmentScope, phase: AttachmentPhase) {
        mutex.withLock {
            scope.currentSlotOrNull()?.takeIf { it.binding === phase.binding }?.binding = null
            phase.binding.active.set(false)
            phase.binding.mutationGate.invalidate()
        }
    }

    private suspend fun rollbackAttachment(scope: AttachmentScope, phase: AttachmentPhase) {
        withContext(NonCancellable) {
            phase.binding.attachSettled.complete(Unit)
            clearPendingAttachment(scope, phase)
            cleanupAttachment(phase.binding.toCleanup(scope.kind))
        }
    }

    private suspend fun handleRenderAsyncFailure(
        scopeTarget: AttachmentScope,
        phase: AttachmentPhase,
    ) {
        val cleanup =
            mutex.withLock {
                val slot = scopeTarget.currentSlotOrNull()
                if (slot === phase.slot && slot.binding === phase.binding) {
                    takeAttachmentLocked(slot)
                } else {
                    null
                }
            }
        cleanupAttachment(cleanup)
    }

    override suspend fun readMediaThumbnail(
        mediaHandle: MediaHandle,
        maxPixelEdge: Int,
    ): ThumbnailRead {
        if (maxPixelEdge !in MIN_THUMBNAIL_EDGE..MAX_THUMBNAIL_EDGE) {
            fail(FailureCode.INVALID_ARGUMENT)
        }
        val expiry = expireLeaseIfNeeded(mediaHandle)
        if (expiry != null) {
            expiry.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
            emitLeaseExpired(expiry.handle)
            fail(FailureCode.INVALID_STATE)
        }
        val job =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                requireMediaState(record, MediaState.LEASED)
                if (thumbnailJobs.containsKey(mediaHandle) || thumbnailJobs.size >= MAX_THUMBNAIL_JOBS) {
                    fail(FailureCode.THUMBNAIL_OVERLOADED)
                }
                ManagedThumbnailJob(record, maxPixelEdge).also { thumbnailJobs[mediaHandle] = it }
            }
        job.start()
        return job
    }

    override suspend fun copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: MediaCopySink,
        maxLength: Long,
    ): MediaExportResult {
        if (maxLength !in 1L..MAX_EXPORT_BYTES) fail(FailureCode.INVALID_ARGUMENT)
        var expiry: LeaseExpiry? = null
        val job =
            mutex.withLock {
                val record = requireMediaLocked(mediaHandle)
                if (record.state == MediaState.LEASED &&
                    clock.nowEpochMillis() >= requireNotNull(record.leaseExpiresAtMillis)
                ) {
                    expiry = expireLeaseLocked(record)
                    null
                } else {
                    requireMediaState(record, MediaState.LEASED)
                    validateExportSource(record, maxLength)
                    if (exportJobs.containsKey(mediaHandle)) fail(FailureCode.MEDIA_EXPORT_CONFLICT)
                    if (exportJobs.size >= MAX_EXPORT_JOBS) fail(FailureCode.MEDIA_EXPORT_OVERLOADED)
                    exportReservationInsideMutexForTest?.invoke(mediaHandle)
                    ManagedExportJob(record, sink).also {
                        exportJobs[mediaHandle] = it
                        it.startLocked()
                    }
                }
            }
        if (expiry != null) {
            expiry?.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
            expiry?.exportJob?.finishClaimedFailure(cancelWorker = true)
            emitLeaseExpired(requireNotNull(expiry).handle)
            fail(FailureCode.INVALID_STATE)
        }
        val activeJob = requireNotNull(job)
        return try {
            activeJob.await()
        } catch (exception: kotlinx.coroutines.CancellationException) {
            withContext(NonCancellable) {
                val claimed = mutex.withLock {
                    activeJob.claimFailureLocked(FailureCode.MEDIA_EXPORT_CANCELLED)
                }
                if (claimed) activeJob.finishClaimedFailure(cancelWorker = true)
                activeJob.awaitOutcome()
            }
        }
    }

    override suspend fun sessionState(sessionHandle: SessionHandle): SessionState =
        mutex.withLock { requireSessionLocked(sessionHandle).state }

    override suspend fun sessionObservation(sessionHandle: SessionHandle): StateFlow<SessionObservation> =
        mutex.withLock { requireSessionLocked(sessionHandle).observation }

    override suspend fun mediaState(mediaHandle: MediaHandle): MediaState =
        mutex.withLock { requireMediaLocked(mediaHandle).state }

    override suspend fun onDisplayRotationChanged() = revokeAllAttachments()

    override suspend fun onAppBackgrounded() = revokeAllAttachments()

    override suspend fun onPreviewOwnerDestroyed(surface: MediaCaptureRenderView) {
        validateSurfaceOwner(surface)
        onPreviewOwnerDestroyed(surface.renderTarget)
    }

    private suspend fun onSurfaceLifecycleDestroyed(surface: MediaCaptureRenderView) {
        val isCurrentOwner = mutex.withLock { surface.isOwnedBy(renderModuleOwner) }
        if (isCurrentOwner) onPreviewOwnerDestroyed(surface.renderTarget)
    }

    internal suspend fun onPreviewOwnerDestroyed(adapter: AndroidRenderTargetAdapter) {
        val cleanups =
            mutex.withLock {
                buildList {
                    sessions.values.forEach { record ->
                        record.liveAttachment.binding?.takeIf { it.adapter === adapter }?.let {
                            takeAttachmentLocked(record.liveAttachment)?.let(::add)
                        }
                    }
                    media.values.forEach { record ->
                        record.previewAttachment.binding?.takeIf { it.adapter === adapter }?.let {
                            takeAttachmentLocked(record.previewAttachment)?.let(::add)
                        }
                    }
                }
            }
        cleanups.forEach { cleanupAttachment(it) }
    }

    private suspend fun validateSurface(surface: MediaCaptureRenderView, ownerGeneration: Long) {
        validateSurfaceIdentity(surface, ownerGeneration)
    }

    private suspend fun validateSurfaceIdentity(surface: MediaCaptureRenderView, ownerGeneration: Long) {
        if (ownerGeneration <= 0 || surface.ownerGeneration != ownerGeneration) {
            fail(FailureCode.INVALID_ARGUMENT)
        }
        validateSurfaceOwner(surface)
    }

    private suspend fun validateSurfaceOwner(surface: MediaCaptureRenderView) {
        val owner = mutex.withLock { renderModuleOwner }
        if (!surface.isOwnedBy(owner)) fail(FailureCode.INVALID_ARGUMENT)
    }

    override suspend fun onAppRestarted() {
        val plan = shutdownPlan(markClosed = false)
        executeShutdown(plan)
        mutex.withLock {
            sessions.clear()
            media.clear()
            thumbnailJobs.clear()
            restartResidueCleaned = false
            renderModuleOwner = MediaCaptureRenderModuleOwner()
        }
    }

    override suspend fun close() {
        val plan = shutdownPlan(markClosed = true)
        executeShutdown(plan)
        mutex.withLock {
            sessions.clear()
            media.clear()
            thumbnailJobs.clear()
            renderModuleOwner = MediaCaptureRenderModuleOwner()
        }
        ownedJob.cancel()
        withContext(NonCancellable) {
            withTimeoutOrNull(FRAMEWORK_DRAIN_TIMEOUT_MILLIS) { ownedJob.join() }
        }
    }

    private suspend fun shutdownPlan(markClosed: Boolean): ShutdownPlan =
        mutex.withLock {
            if (markClosed && closed) return ShutdownPlan.EMPTY
            if (markClosed) closed = true
            val initializeJobs = mutableListOf<Job>()
            val timerJobs = mutableListOf<Job>()
            val operations = mutableListOf<FrameworkOperation>()
            val cleanups = mutableListOf<AttachmentCleanup>()
            sessions.values.forEach { session ->
                invalidateFrameworkOperationLocked(session)?.let(operations::add)
                session.epoch++
                session.initializeJob?.let(initializeJobs::add)
                session.recordingTimerJob?.let(timerJobs::add)
                session.recordingTimerJob = null
                takeAttachmentLocked(session.liveAttachment)?.let(cleanups::add)
                if (!session.state.isTerminal) {
                    session.updateState(
                        SessionState.FAILED,
                        preview = null,
                        failure = MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED),
                    )
                }
            }
            media.values.forEach { record ->
                takeAttachmentLocked(record.previewAttachment)?.let(cleanups::add)
                if (!record.state.isTerminal) {
                    record.markDiscardedPendingCleanup(clock.nowEpochMillis())
                }
            }
            val claimedThumbnails =
                thumbnailJobs.values.filter { it.claimFailureLocked(FailureCode.MEDIA_INVALID) }
            val claimedExports =
                exportJobs.values.filter { it.claimFailureLocked(FailureCode.SYSTEM_INTERRUPTED) }
            ShutdownPlan(
                initializeJobs,
                timerJobs,
                operations,
                cleanups,
                claimedThumbnails,
                claimedExports,
                media.values.toList(),
                pendingDeletes.toList(),
                frameworkState.ownerOrNull(),
            )
        }

    private suspend fun executeShutdown(plan: ShutdownPlan) {
        plan.timerJobs.forEach { it.cancel() }
        plan.initializeJobs.forEach { drainInitializationJob(it, plan.frameworkOwner) }
        plan.operations.forEach { drainFrameworkOperation(it) }
        plan.claimedThumbnails.forEach { it.finishClaimedFailure(cancelWorker = true) }
        plan.claimedExports.forEach { it.finishClaimedFailure(cancelWorker = true) }
        plan.attachments.forEach { cleanupAttachment(it) }
        plan.frameworkOwner?.let {
            closeFrameworkForSession(it, cancelRecording = true)
        }
        withContext(NonCancellable) {
            plan.media.forEach { record ->
                bestEffortSuspend { fileStore.revokeReads(record.reference) }
                deleteMedia(record.reference)
            }
            plan.pendingDeletes.forEach { deleteMedia(it) }
        }
    }

    private suspend fun failSession(handle: SessionHandle, epoch: Long, code: FailureCode) {
        val plan =
            mutex.withLock {
                val session = sessions[handle]
                if (session == null || session.epoch != epoch || session.state.isTerminal) return
                val wasRecording = session.state == SessionState.RECORDING
                val operation = invalidateFrameworkOperationLocked(session)
                session.epoch++
                session.recordingTimerJob?.cancel()
                session.recordingTimerJob = null
                session.updateState(
                    SessionState.FAILED,
                    preview = null,
                    failure = MediaCaptureFailure(code),
                )
                session.terminalAtMillis = clock.nowEpochMillis()
                val preview = session.previewHandle?.let(media::get)
                preview?.markDiscardedPendingCleanup(clock.nowEpochMillis())
                session.previewHandle = null
                FailurePlan(
                    session,
                    operation,
                    wasRecording,
                    takeAttachmentLocked(session.liveAttachment),
                    preview,
                    preview?.let { takeAttachmentLocked(it.previewAttachment) },
                )
            }
        drainFrameworkOperation(plan.operation)
        cleanupAttachment(plan.liveAttachment)
        cleanupAttachment(plan.previewAttachment)
        closeFrameworkForSession(plan.session, cancelRecording = plan.wasRecording)
        plan.preview?.let { deleteMedia(it.reference) }
        mutableEvents.emit(MediaCaptureEvent.SessionFailed(handle, MediaCaptureFailure(code)))
    }

    private suspend fun drainInitializationJob(job: Job?, session: SessionRecord?): Boolean {
        job ?: return true
        job.cancel()
        val settled =
            withContext(NonCancellable) {
                withTimeoutOrNull(FRAMEWORK_DRAIN_TIMEOUT_MILLIS) {
                    job.join()
                    true
                } ?: false
            }
        if (!settled && session != null) {
            mutex.withLock {
                val state = frameworkState
                if ((state is FrameworkState.Owned && state.session === session) ||
                    (state is FrameworkState.Closing && state.session === session)
                ) {
                    frameworkState = FrameworkState.Poisoned(session.handle)
                }
            }
        }
        return settled
    }

    private suspend fun handleOperationFailure(handle: SessionHandle, epoch: Long, code: FailureCode): Nothing {
        if (code.terminal) failSession(handle, epoch, code)
        fail(code)
    }

    private suspend fun commitCapturedPreview(
        operation: FrameworkOperation,
        captured: CapturedMedia,
        expectedRecordingGeneration: Long?,
    ): MediaPreview =
        mutex.withLock {
            val expectedState =
                if (expectedRecordingGeneration == null) {
                    SessionState.READY
                } else {
                    SessionState.RECORDING
                }
            val session = requireOperationSessionLocked(operation, expectedState)
            if (expectedRecordingGeneration != null &&
                session.recordingGeneration != expectedRecordingGeneration
            ) {
                fail(FailureCode.INVALID_STATE)
            }
            val handle =
                try {
                    MediaHandle(newUniqueHandleLocked(FailureCode.ENCODING_FAILED))
                } catch (_: MediaCaptureException) {
                    fail(FailureCode.ENCODING_FAILED)
                }
            val record = MediaRecord(handle, session.handle, captured.reference, captured.metadata)
            media[handle] = record
            session.previewHandle = handle
            session.recordingStop = null
            session.updateState(SessionState.PREVIEWING, preview = MediaPreview(handle, captured.metadata))
            schedulePreviewExpiry(record)
            MediaPreview(handle, captured.metadata)
        }

    private fun scheduleAutomaticRecordingStop(handle: SessionHandle, generation: Long) {
        val timer =
            scope.launch {
                val duration =
                    mutex.withLock {
                        sessions[handle]?.takeIf {
                            it.state == SessionState.RECORDING && it.recordingGeneration == generation
                        }?.options?.maxVideoDurationMillis
                    } ?: return@launch
                delay(duration)
                runCatching {
                    stopRecordingInternal(handle, expectedGeneration = generation, emitAsEvent = true)
                }
            }
        scope.launch {
            mutex.withLock {
                val session = sessions[handle]
                if (session?.state == SessionState.RECORDING &&
                    session.recordingGeneration == generation
                ) {
                    session.recordingTimerJob?.cancel()
                    session.recordingTimerJob = timer
                } else {
                    timer.cancel()
                }
            }
        }
    }

    private fun schedulePreviewExpiry(record: MediaRecord) {
        val deadline = safeDeadline(clock.nowEpochMillis(), PREVIEW_TTL_MILLIS)
        record.previewExpiresAtMillis = deadline
        scheduleAt(deadline) {
            val plan =
                mutex.withLock {
                    val current = media[record.handle]
                    if (current !== record || current.state != MediaState.PREVIEW) return@withLock null
                    val session = sessions[current.sessionHandle]
                    if (session == null || session.state != SessionState.PREVIEWING) return@withLock null
                    val operation = invalidateFrameworkOperationLocked(session)
                    session.epoch++
                    session.updateState(
                        SessionState.FAILED,
                        preview = null,
                        failure = MediaCaptureFailure(FailureCode.SESSION_TIMEOUT),
                    )
                    session.terminalAtMillis = clock.nowEpochMillis()
                    session.previewHandle = null
                    current.markDiscardedPendingCleanup(clock.nowEpochMillis())
                    TimeoutPlan(
                        session,
                        current,
                        operation,
                        takeAttachmentLocked(current.previewAttachment),
                        takeAttachmentLocked(session.liveAttachment),
                    )
                } ?: return@scheduleAt
            drainFrameworkOperation(plan.operation)
            cleanupAttachment(plan.previewAttachment)
            cleanupAttachment(plan.liveAttachment)
            closeFrameworkForSession(plan.session, cancelRecording = false)
            deleteMedia(plan.media.reference)
            mutableEvents.emit(
                MediaCaptureEvent.SessionFailed(
                    plan.session.handle,
                    MediaCaptureFailure(FailureCode.SESSION_TIMEOUT),
                ),
            )
        }
    }

    private fun scheduleLeaseExpiry(record: MediaRecord) {
        val deadline = requireNotNull(record.leaseExpiresAtMillis)
        scheduleAt(deadline) {
            val expiry = expireLease(record.handle) ?: return@scheduleAt
            expiry.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
            expiry.exportJob?.finishClaimedFailure(cancelWorker = true)
            emitLeaseExpired(expiry.handle)
        }
    }

    private suspend fun activeLeaseOrExpire(handle: MediaHandle): MediaRecord {
        val expiry = expireLeaseIfNeeded(handle)
        if (expiry != null) {
            expiry.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
            expiry.exportJob?.finishClaimedFailure(cancelWorker = true)
            emitLeaseExpired(expiry.handle)
            fail(FailureCode.INVALID_STATE)
        }
        return mutex.withLock {
            val record = requireMediaLocked(handle)
            requireMediaState(record, MediaState.LEASED)
            record
        }
    }

    private suspend fun expireLeaseIfNeeded(handle: MediaHandle): LeaseExpiry? =
        mutex.withLock {
            val record = requireMediaLocked(handle)
            if (record.state != MediaState.LEASED ||
                clock.nowEpochMillis() < requireNotNull(record.leaseExpiresAtMillis)
            ) {
                null
            } else {
                expireLeaseLocked(record)
            }
        }

    private suspend fun expireLease(handle: MediaHandle): LeaseExpiry? =
        mutex.withLock {
            val record = media[handle]
            if (record == null || record.state != MediaState.LEASED) null else expireLeaseLocked(record)
        }

    private fun expireLeaseLocked(record: MediaRecord): LeaseExpiry {
        record.state = MediaState.EXPIRY_GRACE
        val deadline = safeDeadline(clock.nowEpochMillis(), READ_GRACE_MILLIS)
        record.graceExpiresAtMillis = deadline
        val thumbnailJob = thumbnailJobs[record.handle]
        val thumbnailClaimed =
            thumbnailJob?.claimFailureLocked(FailureCode.INVALID_STATE) == true
        val exportJob = exportJobs[record.handle]
        val exportClaimed =
            exportJob?.claimFailureLocked(FailureCode.INVALID_STATE) == true
        scheduleReadGrace(record.handle, MediaState.EXPIRY_GRACE, deadline)
        return LeaseExpiry(
            record.handle,
            if (thumbnailClaimed) thumbnailJob else null,
            if (exportClaimed) exportJob else null,
        )
    }

    private fun scheduleReadGrace(handle: MediaHandle, expectedState: MediaState, deadline: Long) {
        scheduleAt(deadline) {
            val record =
                mutex.withLock {
                    media[handle]?.takeIf { it.state == expectedState }
                } ?: return@scheduleAt
            withContext(NonCancellable) { bestEffortSuspend { fileStore.revokeReads(record.reference) } }
            if (!deleteMedia(record.reference, retryOnFailure = false)) {
                scheduleReadGrace(handle, expectedState, safeDeadline(clock.nowEpochMillis(), CLEANUP_RETRY_MILLIS))
                return@scheduleAt
            }
            val transitioned =
                mutex.withLock {
                    val current = media[handle]
                    if (current !== record || current.state != expectedState) {
                        false
                    } else {
                        if (expectedState == MediaState.RELEASE_GRACE) {
                            current.markReleased(clock.nowEpochMillis())
                        } else {
                            current.markExpired(clock.nowEpochMillis())
                        }
                        true
                    }
                }
            if (transitioned) mutableEvents.emit(MediaCaptureEvent.ReadRevoked(handle))
        }
    }

    private fun scheduleAt(deadlineMillis: Long, action: suspend () -> Unit) {
        scope.launch {
            val remaining = max(0L, deadlineMillis - clock.nowEpochMillis())
            delay(remaining)
            if (clock.nowEpochMillis() >= deadlineMillis) action() else scheduleAt(deadlineMillis, action)
        }
    }

    private suspend fun revokeAllAttachments() {
        val cleanups = mutex.withLock { takeAllAttachmentsLocked() }
        cleanups.forEach { cleanupAttachment(it) }
    }

    private fun takeAllAttachmentsLocked(): List<AttachmentCleanup> =
        buildList {
            sessions.values.forEach { takeAttachmentLocked(it.liveAttachment)?.let(::add) }
            media.values.forEach { takeAttachmentLocked(it.previewAttachment)?.let(::add) }
        }

    private fun takeAttachmentLocked(slot: AttachmentSlot): AttachmentCleanup? {
        val binding = slot.binding ?: return null
        slot.binding = null
        binding.active.set(false)
        binding.mutationGate.invalidate()
        return binding.toCleanup(slot.kind)
    }

    private fun detachAttachmentLocked(
        slot: AttachmentSlot,
        adapter: AndroidRenderTargetAdapter,
        generation: Long,
    ): AttachmentCleanup? {
        if (generation <= 0) fail(FailureCode.INVALID_ARGUMENT)
        val binding = slot.binding
        return if (binding != null && binding.generation == generation && binding.adapter === adapter) {
            takeAttachmentLocked(slot)
        } else {
            null
        }
    }

    private suspend fun cleanupAttachment(cleanup: AttachmentCleanup?) {
        cleanup ?: return
        val binding = cleanup.binding
        binding.renderBinding.clearAsyncFailureHandler()
        binding.active.set(false)
        binding.mutationGate.invalidate()
        if (!binding.cleanupStarted.compareAndSet(false, true)) {
            if (binding.attachOwner.get() === coroutineContext[Job] &&
                !binding.attachSettled.isCompleted
            ) {
                return
            }
            withContext(NonCancellable) { binding.cleanupSettled.await() }
            return
        }
        if (binding.attachClaimed.compareAndSet(false, true)) {
            binding.attachSettled.complete(Unit)
        }
        if (binding.attachOwner.get() === coroutineContext[Job] &&
            !binding.attachSettled.isCompleted
        ) {
            scope.launch {
                finishAttachmentCleanup(cleanup)
            }
            return
        }
        finishAttachmentCleanup(cleanup)
    }

    private suspend fun finishAttachmentCleanup(cleanup: AttachmentCleanup) {
        val binding = cleanup.binding
        withContext(NonCancellable) {
            try {
                binding.attachSettled.await()
                bestEffortSuspend { binding.adapter.revokeCallbacks(binding.renderBinding) }
                bestEffortSuspend { binding.adapter.detach(binding.renderBinding) }
                if (binding.committed.get()) {
                    mutableEvents.emit(
                        MediaCaptureEvent.AttachmentRevoked(cleanup.kind, binding.generation),
                    )
                }
            } finally {
                binding.cleanupSettled.complete(Unit)
            }
        }
    }

    private suspend fun cleanupUncommittedCapture(reference: StoredMediaReference) {
        withContext(NonCancellable) {
            bestEffortSuspend { fileStore.revokeReads(reference) }
            deleteMedia(reference)
        }
    }

    private suspend fun schedulePendingDelete(reference: StoredMediaReference) {
        val shouldSchedule =
            mutex.withLock {
                !closed && reference in pendingDeletes && scheduledDeleteRetries.add(reference)
            }
        if (!shouldSchedule) return
        scheduleAt(safeDeadline(clock.nowEpochMillis(), CLEANUP_RETRY_MILLIS)) {
            val stillPending =
                mutex.withLock {
                    scheduledDeleteRetries -= reference
                    reference in pendingDeletes && !closed
                }
            if (!stillPending) return@scheduleAt
            deleteMedia(reference)
        }
    }

    private suspend fun deleteMedia(
        reference: StoredMediaReference,
        retryOnFailure: Boolean = true,
    ): Boolean =
        withContext(NonCancellable) {
            val deleted = runCatching { fileStore.delete(reference) }.getOrDefault(false)
            mutex.withLock {
                if (deleted) {
                    pendingDeletes -= reference
                    media.values
                        .filter { it.reference == reference && it.physicalCleanupPending }
                        .forEach { it.physicalCleanupPending = false }
                } else {
                    pendingDeletes += reference
                }
            }
            if (!deleted && retryOnFailure) schedulePendingDelete(reference)
            deleted
        }

    private suspend fun closeFrameworkForStaleSession(handle: SessionHandle) {
        val session = mutex.withLock { sessions[handle] }
        if (session != null) {
            closeFrameworkForSession(session, cancelRecording = true)
        } else {
            mutex.withLock { frameworkState = FrameworkState.Poisoned(handle) }
        }
    }

    private suspend fun closeFrameworkForSession(
        session: SessionRecord,
        cancelRecording: Boolean,
    ): Boolean {
        val attempt =
            mutex.withLock {
                when (val state = frameworkState) {
                    is FrameworkState.Owned -> {
                        if (state.session !== session) return false
                        frameworkState = FrameworkState.Closing(session)
                        FrameworkCloseAttempt.Execute
                    }
                    is FrameworkState.Closing -> {
                        if (state.session !== session) return false
                        FrameworkCloseAttempt.Await
                    }
                    is FrameworkState.Available -> FrameworkCloseAttempt.Await
                    is FrameworkState.Poisoned -> return false
                }
            }
        if (attempt == FrameworkCloseAttempt.Await) return session.frameworkCloseResult.await()
        var closeSucceeded = false
        var pending = emptyList<StoredMediaReference>()
        withContext(NonCancellable) {
            frameworkMutex.withLock {
                if (cancelRecording) bestEffortSuspend { captureFramework.cancelRecording() }
                closeSucceeded = runCatching { captureFramework.close() }.isSuccess
                pending =
                    runCatching { captureFramework.drainPendingCleanupReferences() }
                        .getOrElse {
                            closeSucceeded = false
                            emptyList()
                        }
            }
        }
        withContext(NonCancellable) {
            if (runCatching { adoptPendingReferences(pending) }.isFailure) {
                closeSucceeded = false
            }
            session.frameworkCloseResult.complete(closeSucceeded)
            mutex.withLock {
                val state = frameworkState
                if (state is FrameworkState.Closing && state.session === session) {
                    frameworkState =
                        if (closeSucceeded) {
                            FrameworkState.Available
                        } else {
                            FrameworkState.Poisoned(session.handle)
                        }
                }
            }
        }
        return closeSucceeded
    }

    private suspend fun adoptFrameworkPendingCleanup() {
        val pending =
            frameworkMutex.withLock {
                runCatching { captureFramework.drainPendingCleanupReferences() }
                    .getOrDefault(emptyList())
            }
        adoptPendingReferences(pending)
    }

    private suspend fun adoptPendingReferences(references: List<StoredMediaReference>) {
        if (references.isEmpty()) return
        mutex.withLock { pendingDeletes += references }
        references.forEach { schedulePendingDelete(it) }
    }

    private suspend fun cleanupRestartResidueOnce() {
        residueMutex.withLock {
            val shouldClean = mutex.withLock { !restartResidueCleaned }
            if (!shouldClean) return
            fileStore.cleanupRestartResidue()
            val retry = mutex.withLock { pendingDeletes.toList() }
            for (reference in retry) deleteMedia(reference)
            mutex.withLock { restartResidueCleaned = true }
        }
    }

    private suspend fun resolvePermission(resource: PermissionResource): PermissionState =
        try {
            val current = permissionGateway.currentState(resource)
            if (current == PermissionState.NOT_DETERMINED) {
                permissionGateway.request(resource)
            } else {
                current
            }
        } catch (exception: kotlinx.coroutines.CancellationException) {
            throw exception
        } catch (_: SecurityException) {
            PermissionState.DENIED
        }

    private suspend fun emitLeaseExpired(handle: MediaHandle) {
        mutableEvents.emit(MediaCaptureEvent.LeaseExpired(handle))
    }

    private fun validateOptions(options: SessionOptions) {
        if (options.enabledMediaTypes.isEmpty() || options.enabledMediaTypes.size > 2 ||
            options.maxVideoDurationMillis !in 1L..60_000L
        ) {
            fail(FailureCode.INVALID_ARGUMENT)
        }
    }

    private fun validatePrepared(prepared: PreparedCapture) {
        if (prepared.availableCameras.isEmpty() || prepared.activeCamera !in prepared.availableCameras ||
            prepared.supportedFlashModes.isEmpty() || !prepared.minZoomFactor.isFinite() ||
            !prepared.maxZoomFactor.isFinite() || prepared.minZoomFactor < 0.01 ||
            prepared.maxZoomFactor < prepared.minZoomFactor
        ) {
            fail(FailureCode.ENCODING_FAILED)
        }
    }

    private fun validateMetadata(metadata: MediaMetadata, expectedType: MediaType) {
        val durationIsValid =
            when (metadata.mediaType) {
                MediaType.PHOTO -> metadata.durationMillis == null
                MediaType.VIDEO -> metadata.durationMillis?.let { it in 1L..60_000L } == true
            }
        if (metadata.mediaType != expectedType || metadata.pixelWidth <= 0 || metadata.pixelHeight <= 0 ||
            !durationIsValid || metadata.orientationDegrees !in setOf(0, 90, 180, 270) ||
            metadata.byteLength <= 0 || !MIME_TYPE.matches(metadata.contentType)
        ) {
            fail(FailureCode.ENCODING_FAILED)
        }
    }

    private fun validateExportSource(record: MediaRecord, maxLength: Long) {
        val expectedContentType =
            when (record.metadata.mediaType) {
                MediaType.PHOTO -> "image/jpeg"
                MediaType.VIDEO -> "video/mp4"
            }
        if (record.metadata.contentType != expectedContentType) fail(FailureCode.INVALID_STATE)
        if (record.metadata.byteLength !in 1L..MAX_EXPORT_BYTES ||
            record.metadata.byteLength > maxLength
        ) {
            fail(FailureCode.MEDIA_EXPORT_TOO_LARGE)
        }
    }

    private fun requireSessionLocked(handle: SessionHandle): SessionRecord {
        ensureOpenLocked()
        pruneExpiredTombstonesLocked()
        return sessions[handle] ?: fail(FailureCode.SESSION_INVALID)
    }

    private fun requireMediaLocked(handle: MediaHandle): MediaRecord {
        ensureOpenLocked()
        pruneExpiredTombstonesLocked()
        return media[handle] ?: fail(FailureCode.MEDIA_INVALID)
    }

    private fun requireSessionState(record: SessionRecord, vararg expected: SessionState) {
        if (record.state !in expected) fail(FailureCode.INVALID_STATE)
    }

    private fun requireMediaState(record: MediaRecord, vararg expected: MediaState) {
        if (record.state !in expected) fail(FailureCode.INVALID_STATE)
    }

    private fun previewForSessionLocked(session: SessionRecord): MediaPreview {
        val handle = session.previewHandle ?: fail(FailureCode.INVALID_STATE)
        val record = media[handle] ?: fail(FailureCode.MEDIA_INVALID)
        return MediaPreview(record.handle, record.metadata)
    }

    private fun ensureOpenLocked() {
        if (closed) fail(FailureCode.INVALID_STATE)
    }

    private fun newUniqueHandleLocked(failure: FailureCode): String {
        repeat(MAX_HANDLE_GENERATION_ATTEMPTS) {
            val candidate = handleGenerator.nextHandle()
            if (candidate.isNotBlank() && candidate.length <= 128 && usedHandleValues.add(candidate)) {
                return candidate
            }
        }
        fail(failure)
    }

    private fun pruneExpiredTombstonesLocked() {
        val now = clock.nowEpochMillis()
        sessions.entries.removeAll { (_, record) ->
            record.state.isTerminal && record.terminalAtMillis?.let { now - it >= TOMBSTONE_MILLIS } == true
        }
        media.entries.removeAll { (_, record) ->
            record.state.isTerminal && record.terminalAtMillis?.let { now - it >= TOMBSTONE_MILLIS } == true
        }
    }

    private fun SessionOptions.snapshot() = copy(enabledMediaTypes = enabledMediaTypes.toSet())

    private fun PreparedCapture.snapshot() =
        copy(
            availableCameras = availableCameras.toSet(),
            supportedFlashModes = supportedFlashModes.toSet(),
        )

    private fun PreparedCapture.toReady(handle: SessionHandle) =
        SessionReady(
            sessionHandle = handle,
            activeCamera = activeCamera,
            availableCameras = availableCameras.toSet(),
            switchCameraSupported = availableCameras.size > 1,
            supportedFlashModes = supportedFlashModes.toSet(),
            focusPointSupported = focusPointSupported,
            minZoomFactor = minZoomFactor,
            maxZoomFactor = maxZoomFactor,
        )

    private fun PermissionState.toFailureCode(): FailureCode =
        when (this) {
            PermissionState.GRANTED -> error("granted has no failure")
            PermissionState.DENIED, PermissionState.NOT_DETERMINED -> FailureCode.PERMISSION_DENIED
            PermissionState.RESTRICTED -> FailureCode.PERMISSION_RESTRICTED
            PermissionState.PERMANENTLY_DENIED -> FailureCode.PERMISSION_PERMANENTLY_DENIED
            PermissionState.UNSUPPORTED -> FailureCode.UNSUPPORTED_CAPABILITY
        }

    private fun safeDeadline(now: Long, duration: Long): Long =
        if (Long.MAX_VALUE - now < duration) Long.MAX_VALUE else now + duration

    private inner class ManagedThumbnailJob(
        private val record: MediaRecord,
        private val maxPixelEdge: Int,
    ) : ThumbnailRead {
        private val result = CompletableDeferred<MediaThumbnail>()
        private val cleanupStarted = AtomicBoolean(false)
        @Volatile private var terminal: ThumbnailTerminal? = null
        @Volatile private var work: ThumbnailGenerationWork? = null
        private var worker: Job? = null

        fun start() {
            worker =
                scope.launch {
                    if (terminal != null) return@launch
                    try {
                        val posterTarget =
                            if (record.metadata.mediaType == MediaType.VIDEO) {
                                min(1_000L, requireNotNull(record.metadata.durationMillis) / 2L)
                            } else {
                                null
                            }
                        val opened =
                            thumbnailGenerator.open(
                                record.reference,
                                record.metadata,
                                ThumbnailGenerationRequest(
                                    maxPixelEdge = maxPixelEdge,
                                    videoTargetFrameMillis = posterTarget,
                                ),
                            )
                        work = opened
                        if (terminal != null) return@launch
                        val artifact = opened.generate()
                        finishSuccess(artifact)
                    } catch (_: kotlinx.coroutines.CancellationException) {
                        // The terminal owner performs NonCancellable cleanup and completion.
                    } catch (_: Exception) {
                        val claimed = mutex.withLock { claimFailureLocked(FailureCode.THUMBNAIL_GENERATION_FAILED) }
                        if (claimed) finishClaimedFailure(cancelWorker = false)
                    }
                }
        }

        override suspend fun await(): MediaThumbnail = result.await()

        override suspend fun cancel() {
            val claimed = mutex.withLock { claimFailureLocked(FailureCode.THUMBNAIL_GENERATION_CANCELLED) }
            if (claimed) finishClaimedFailure(cancelWorker = true) else awaitOutcomeIgnoringFailure()
        }

        fun claimFailureLocked(code: FailureCode): Boolean {
            if (terminal != null) return false
            terminal = ThumbnailTerminal.Failure(code)
            return true
        }

        private suspend fun finishSuccess(artifact: ThumbnailArtifact) {
            val callerCopy = validateAndCopyArtifact(artifact, record.metadata, maxPixelEdge)
            val finalResult =
                MediaThumbnail(
                    mediaHandle = record.handle,
                    copy = callerCopy,
                    pixelWidth = artifact.pixelWidth,
                    pixelHeight = artifact.pixelHeight,
                    mediaType = record.metadata.mediaType,
                    posterFrameMillis = artifact.actualPosterFrameMillis,
                )
            var cancellation: kotlinx.coroutines.CancellationException? = null
            val claim =
                try {
                    thumbnailCopyBeforeClaimForTest?.invoke(callerCopy)
                    mutex.withLock { claimSuccessLocked() }
                } catch (exception: kotlinx.coroutines.CancellationException) {
                    cancellation = exception
                    withContext(NonCancellable) { mutex.withLock { claimSuccessLocked() } }
                }
            when (claim) {
                ThumbnailSuccessClaim.Lost -> callerCopy.fill(0)
                ThumbnailSuccessClaim.Success -> finishClaimedSuccess(finalResult)
                is ThumbnailSuccessClaim.Failure -> {
                    callerCopy.fill(0)
                    finishClaimedFailure(cancelWorker = false)
                    claim.expiry?.let { emitLeaseExpired(it.handle) }
                }
            }
            cancellation?.let { throw it }
        }

        private fun claimSuccessLocked(): ThumbnailSuccessClaim {
            val current = media[record.handle]
            return if (terminal != null || thumbnailJobs[record.handle] !== this) {
                ThumbnailSuccessClaim.Lost
            } else if (current !== record || current.state != MediaState.LEASED ||
                clock.nowEpochMillis() >= requireNotNull(current.leaseExpiresAtMillis)
            ) {
                val expiry =
                    if (current === record && current.state == MediaState.LEASED) {
                        expireLeaseLocked(current)
                    } else {
                        null
                    }
                claimFailureLocked(FailureCode.INVALID_STATE)
                ThumbnailSuccessClaim.Failure(expiry)
            } else {
                terminal = ThumbnailTerminal.Success
                ThumbnailSuccessClaim.Success
            }
        }

        suspend fun finishClaimedFailure(cancelWorker: Boolean) {
            if (!cleanupStarted.compareAndSet(false, true)) {
                awaitOutcomeIgnoringFailure()
                return
            }
            val failure = terminal as? ThumbnailTerminal.Failure ?: return
            withContext(NonCancellable) {
                val initial = work
                bestEffortSuspend { initial?.revokeSourceAccess() }
                if (cancelWorker) worker?.cancel()
                bestEffortSuspend { initial?.cancelAndAwaitDecoder() }
                if (cancelWorker) bestEffortSuspend { worker?.join() }
                val late = work
                if (late != null && late !== initial) {
                    bestEffortSuspend { late.revokeSourceAccess() }
                    bestEffortSuspend { late.cancelAndAwaitDecoder() }
                }
                val active = work
                bestEffortSuspend { active?.closeSourceHandles() }
                bestEffort { active?.wipeDecodedPixels() }
                bestEffort { active?.wipeGenerationBuffer() }
                bestEffort { active?.discardPartialCopy() }
                unregisterLast()
                result.completeExceptionally(MediaCaptureException(MediaCaptureFailure(failure.code)))
            }
        }

        private suspend fun finishClaimedSuccess(finalResult: MediaThumbnail) {
            if (!cleanupStarted.compareAndSet(false, true)) return
            withContext(NonCancellable) {
                val active = work
                bestEffortSuspend { active?.closeSourceAccess() }
                bestEffortSuspend { active?.finishAndCloseDecoder() }
                bestEffortSuspend { active?.closeSourceHandles() }
                bestEffort { active?.wipeDecodedPixels() }
                bestEffort { active?.wipeGenerationBuffer() }
                unregisterLast()
                result.complete(finalResult)
            }
        }

        private suspend fun unregisterLast() {
            mutex.withLock {
                thumbnailJobs.entries.removeAll { it.value === this@ManagedThumbnailJob }
            }
        }

        private suspend fun awaitOutcomeIgnoringFailure() {
            runCatching { result.await() }
        }
    }

    private inner class ManagedExportJob(
        private val record: MediaRecord,
        private val sink: MediaCopySink,
    ) {
        private val result = CompletableDeferred<MediaExportResult>()
        private val cleanupStarted = AtomicBoolean(false)
        private val abortStarted = AtomicBoolean(false)
        private val lateCleanupStarted = AtomicBoolean(false)
        private val sinkBegun = AtomicBoolean(false)
        private val callbackGateClosed = AtomicBoolean(false)
        private val sinkTerminalMutex = Mutex()
        @Volatile private var terminal: ExportTerminal? = null
        private var commitCancellationCode: FailureCode? = null
        private var sinkCommitted = false
        @Volatile private var source: StreamingMediaRead? = null
        @Volatile private var buffer: ByteArray? = null
        private val deadline: Job =
            scope.launch(start = CoroutineStart.LAZY) {
                delay(EXPORT_DEADLINE_MILLIS)
                val claimed = mutex.withLock { claimFailureLocked(FailureCode.MEDIA_EXPORT_TIMED_OUT) }
                if (claimed) finishClaimedFailure(cancelWorker = true)
            }
        private val worker: Job =
            scope.launch(start = CoroutineStart.LAZY) {
                try {
                    executeCopy()
                } catch (_: kotlinx.coroutines.CancellationException) {
                    claimAndFinish(FailureCode.SYSTEM_INTERRUPTED)
                } catch (exception: FrameworkException) {
                    claimAndFinish(mapExportReadFailure(exception.failureCode))
                } catch (exception: MediaCaptureException) {
                    claimAndFinish(exception.failure.code)
                } catch (_: Exception) {
                    claimAndFinish(FailureCode.MEDIA_EXPORT_READ_FAILED)
                }
            }

        fun startLocked() {
            check(exportJobs[record.handle] === this && terminal == null)
            deadline.start()
            worker.start()
        }

        suspend fun await(): MediaExportResult = result.await()

        suspend fun awaitOutcome(): MediaExportResult =
            withContext(NonCancellable) { result.await() }

        fun claimFailureLocked(code: FailureCode): Boolean {
            return when (terminal) {
                null -> {
                    callbackGateClosed.set(true)
                    terminal = ExportTerminal.Failure(code)
                    true
                }
                ExportTerminal.Committing -> {
                    callbackGateClosed.set(true)
                    if (commitCancellationCode == null) commitCancellationCode = code
                    worker.cancel()
                    false
                }
                is ExportTerminal.Failure,
                ExportTerminal.Success,
                -> false
            }
        }

        private suspend fun executeCopy() = withContext(ioDispatcher) {
            val declaredLength = record.metadata.byteLength
            val contentType = record.metadata.contentType
            val read =
                try {
                    fileStore.openStreamingRead(record.reference, declaredLength, contentType)
                } catch (exception: kotlinx.coroutines.CancellationException) {
                    throw exception
                } catch (_: Exception) {
                    fail(FailureCode.MEDIA_EXPORT_READ_FAILED)
                }
            source = read
            beginSink()
            val chunk = ByteArray(MAX_EXPORT_READ_BUFFER_BYTES)
            exportBufferAllocationChangedForTest?.invoke(chunk.size)
            buffer = chunk
            var copied = 0L
            while (true) {
                coroutineContext.ensureActive()
                val readCount =
                    try {
                        read.read(chunk)
                    } catch (exception: kotlinx.coroutines.CancellationException) {
                        throw exception
                    } catch (_: Exception) {
                        fail(FailureCode.MEDIA_EXPORT_READ_FAILED)
                    }
                if (readCount < 0) break
                if (readCount == 0) continue
                if (readCount > MAX_EXPORT_READ_BUFFER_BYTES) fail(FailureCode.MEDIA_EXPORT_TOO_LARGE)
                val next = copied + readCount
                if (next > declaredLength || next > MAX_EXPORT_BYTES) {
                    fail(FailureCode.MEDIA_EXPORT_TOO_LARGE)
                }
                writeSink(chunk, readCount)
                copied = next
            }
            if (copied != declaredLength) fail(FailureCode.MEDIA_EXPORT_TOO_LARGE)
            val finalResult =
                MediaExportResult(
                    mediaHandle = record.handle,
                    mediaType = record.metadata.mediaType,
                    contentType = contentType,
                    byteLength = copied,
                )
            val preparation = mutex.withLock { prepareCommitLocked() }
            preparation.expiry?.let { expiry ->
                expiry.thumbnailJob?.finishClaimedFailure(cancelWorker = true)
                if (expiry.exportJob === this@ManagedExportJob) {
                    finishClaimedFailure(cancelWorker = false)
                } else {
                    expiry.exportJob?.finishClaimedFailure(cancelWorker = true)
                }
                emitLeaseExpired(expiry.handle)
            }
            if (preparation.failureClaimed) finishClaimedFailure(cancelWorker = false)
            if (!preparation.ready) return@withContext
            commitSink(finalResult)
        }

        private suspend fun beginSink() {
            try {
                sinkTerminalMutex.withLock {
                    coroutineContext.ensureActive()
                    if (callbackGateClosed.get()) throw kotlinx.coroutines.CancellationException()
                    sink.begin(record.metadata.mediaType, record.metadata.contentType, record.metadata.byteLength)
                    sinkBegun.set(true)
                }
            } catch (exception: kotlinx.coroutines.CancellationException) {
                throw exception
            } catch (_: Exception) {
                fail(FailureCode.MEDIA_EXPORT_SINK_REJECTED)
            }
        }

        private suspend fun writeSink(chunk: ByteArray, byteCount: Int) {
            val callbackBuffer = chunk.copyOf(byteCount)
            exportBufferAllocationChangedForTest?.invoke(callbackBuffer.size)
            try {
                sinkTerminalMutex.withLock {
                    coroutineContext.ensureActive()
                    if (callbackGateClosed.get()) throw kotlinx.coroutines.CancellationException()
                    sink.write(callbackBuffer, byteCount)
                }
            } catch (exception: kotlinx.coroutines.CancellationException) {
                throw exception
            } catch (_: Exception) {
                fail(FailureCode.MEDIA_EXPORT_WRITE_FAILED)
            } finally {
                callbackBuffer.fill(0)
                exportBufferAllocationChangedForTest?.invoke(-callbackBuffer.size)
            }
        }

        private fun prepareCommitLocked(): ExportCommitPreparation {
            if (terminal != null || exportJobs[record.handle] !== this) {
                return ExportCommitPreparation.REJECTED
            }
            val current = media[record.handle]
            if (current !== record || current.state != MediaState.LEASED ||
                clock.nowEpochMillis() >= requireNotNull(current.leaseExpiresAtMillis)
            ) {
                val expiry =
                    if (current === record && current.state == MediaState.LEASED) {
                        expireLeaseLocked(current)
                    } else {
                        null
                    }
                val failureClaimed = expiry == null && claimFailureLocked(FailureCode.INVALID_STATE)
                return ExportCommitPreparation(ready = false, expiry = expiry, failureClaimed = failureClaimed)
            }
            terminal = ExportTerminal.Committing
            return ExportCommitPreparation.READY
        }

        private suspend fun commitSink(finalResult: MediaExportResult) {
            var claimed = false
            try {
                sinkTerminalMutex.withLock {
                    coroutineContext.ensureActive()
                    if (callbackGateClosed.get()) return
                    sink.commit(finalResult.byteLength)
                    withContext(NonCancellable) {
                        sinkCommitted = true
                        exportCommitAfterSinkForTest?.invoke()
                        claimed =
                            mutex.withLock {
                                if (terminal == ExportTerminal.Committing) {
                                    callbackGateClosed.set(true)
                                    terminal = ExportTerminal.Success
                                    true
                                } else {
                                    false
                                }
                            }
                    }
                }
            } catch (_: kotlinx.coroutines.CancellationException) {
                finishCommitFailure(FailureCode.SYSTEM_INTERRUPTED)
            } catch (_: Exception) {
                finishCommitFailure(FailureCode.MEDIA_EXPORT_SINK_REJECTED)
            }
            if (claimed) {
                withContext(NonCancellable) { finishClaimedSuccess(finalResult) }
            }
        }

        private suspend fun finishCommitFailure(fallback: FailureCode) {
            withContext(NonCancellable) {
                val claimed =
                    mutex.withLock {
                        if (terminal != ExportTerminal.Committing) {
                            false
                        } else {
                            callbackGateClosed.set(true)
                            terminal = ExportTerminal.Failure(commitCancellationCode ?: fallback)
                            true
                        }
                    }
                if (claimed) finishClaimedFailure(cancelWorker = false)
            }
        }

        private suspend fun claimAndFinish(code: FailureCode) {
            withContext(NonCancellable) {
                val claimed = mutex.withLock { claimFailureLocked(code) }
                if (claimed) finishClaimedFailure(cancelWorker = false)
            }
        }

        suspend fun finishClaimedFailure(cancelWorker: Boolean) {
            if (!cleanupStarted.compareAndSet(false, true)) {
                awaitOutcomeIgnoringFailure()
                return
            }
            val failure = terminal as? ExportTerminal.Failure ?: return
            withContext(NonCancellable + ioDispatcher) {
                deadline.cancel()
                val converged =
                    withTimeoutOrNull(EXPORT_CANCEL_CONVERGENCE_MILLIS) {
                        if (cancelWorker) worker.cancel()
                        bestEffortSuspend { abortSinkOnceIfBegun() }
                        if (cancelWorker) worker.join()
                        true
                    } == true
                bestEffortSuspend { source?.close() }
                releaseReadBuffer()
                if (!cancelWorker || converged || worker.isCompleted) {
                    unregisterLast()
                } else {
                    scheduleLateFailureConvergence()
                }
                result.completeExceptionally(MediaCaptureException(MediaCaptureFailure(failure.code)))
            }
        }

        private fun scheduleLateFailureConvergence() {
            if (!lateCleanupStarted.compareAndSet(false, true)) return
            val cleanupOwner = SupervisorJob()
            val cleanupScope = CoroutineScope(ioDispatcher + cleanupOwner)
            worker.invokeOnCompletion {
                cleanupScope.launch {
                    try {
                        withContext(NonCancellable) {
                            withTimeoutOrNull(EXPORT_CANCEL_CONVERGENCE_MILLIS) {
                                bestEffortSuspend { abortSinkOnceIfBegun() }
                            }
                            unregisterLast()
                        }
                    } finally {
                        cleanupOwner.cancel()
                    }
                }
            }
        }

        private suspend fun finishClaimedSuccess(finalResult: MediaExportResult) {
            if (!cleanupStarted.compareAndSet(false, true)) return
            withContext(NonCancellable + ioDispatcher) {
                deadline.cancel()
                bestEffortSuspend { source?.close() }
                releaseReadBuffer()
                unregisterLast()
                result.complete(finalResult)
            }
        }

        private suspend fun abortSinkOnceIfBegun() {
            sinkTerminalMutex.withLock {
                if (!sinkCommitted && sinkBegun.get() && abortStarted.compareAndSet(false, true)) {
                    sink.abort()
                }
            }
        }

        private fun releaseReadBuffer() {
            val active = buffer ?: return
            active.fill(0)
            buffer = null
            exportBufferAllocationChangedForTest?.invoke(-active.size)
        }

        private suspend fun unregisterLast() {
            mutex.withLock {
                exportJobs.entries.removeAll { it.value === this@ManagedExportJob }
            }
        }

        private suspend fun awaitOutcomeIgnoringFailure() {
            runCatching { result.await() }
        }

        private fun mapExportReadFailure(code: FailureCode): FailureCode =
            if (code == FailureCode.MEDIA_EXPORT_READ_FAILED) {
                FailureCode.MEDIA_EXPORT_READ_FAILED
            } else {
                FailureCode.MEDIA_EXPORT_READ_FAILED
            }
    }

    private fun validateAndCopyArtifact(
        artifact: ThumbnailArtifact,
        metadata: MediaMetadata,
        maxPixelEdge: Int,
    ): ByteArray {
        val posterIsValid =
            if (metadata.mediaType == MediaType.PHOTO) {
                artifact.actualPosterFrameMillis == null
            } else {
                artifact.actualPosterFrameMillis != null &&
                    artifact.actualPosterFrameMillis in 0L..requireNotNull(metadata.durationMillis)
            }
        if (artifact.encodedJpeg.isEmpty() || artifact.encodedJpeg.size > MAX_THUMBNAIL_BYTES ||
            artifact.pixelWidth !in 1..maxPixelEdge || artifact.pixelHeight !in 1..maxPixelEdge ||
            artifact.orientationDegrees != 0 || !posterIsValid || !isJpeg(artifact.encodedJpeg) ||
            hasForbiddenJpegMetadata(artifact.encodedJpeg)
        ) {
            fail(FailureCode.THUMBNAIL_GENERATION_FAILED)
        }
        return artifact.encodedJpeg.copyOf()
    }

    private fun isJpeg(bytes: ByteArray): Boolean =
        bytes.size >= 4 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() &&
            bytes[bytes.lastIndex - 1] == 0xFF.toByte() && bytes.last() == 0xD9.toByte()

    private fun hasForbiddenJpegMetadata(bytes: ByteArray): Boolean {
        var index = 2
        while (index + 3 < bytes.size) {
            if (bytes[index] != 0xFF.toByte()) return false
            val marker = bytes[index + 1].toInt() and 0xFF
            if (marker == 0xD9 || marker == 0xDA) return false
            if (marker == 0xE1 || marker in 0xE2..0xEF || marker == 0xFE) return true
            val segmentLength =
                ((bytes[index + 2].toInt() and 0xFF) shl 8) or
                    (bytes[index + 3].toInt() and 0xFF)
            if (segmentLength < 2 || index + 2 + segmentLength > bytes.size) return true
            index += 2 + segmentLength
        }
        return false
    }

    private data class SessionRecord(
        val handle: SessionHandle,
        val options: SessionOptions,
        var state: SessionState = SessionState.REQUESTING_PERMISSION,
        var epoch: Long = 1,
        var initializeJob: Job? = null,
        var prepared: PreparedCapture? = null,
        var previewHandle: MediaHandle? = null,
        var terminalAtMillis: Long? = null,
        var cancelledResult: SessionCancelled? = null,
        var recordingGeneration: Long = 0,
        var recordingTimerJob: Job? = null,
        var recordingStop: RecordingStop? = null,
        var operationGeneration: Long = 0,
        var activeOperation: FrameworkOperation? = null,
        val frameworkCloseResult: CompletableDeferred<Boolean> = CompletableDeferred(),
        val liveAttachment: AttachmentSlot = AttachmentSlot(AttachmentKind.LIVE_PREVIEW),
        val observation: MutableStateFlow<SessionObservation> =
            MutableStateFlow(SessionObservation(SessionState.REQUESTING_PERMISSION)),
    ) {
        fun updateState(
            next: SessionState,
            ready: SessionReady? = observation.value.ready,
            preview: MediaPreview? = observation.value.preview,
            failure: MediaCaptureFailure? = observation.value.terminalFailure,
        ) {
            state = next
            observation.value = SessionObservation(next, ready, preview, failure)
        }
    }

    private data class MediaRecord(
        val handle: MediaHandle,
        val sessionHandle: SessionHandle,
        val reference: StoredMediaReference,
        val metadata: MediaMetadata,
        var state: MediaState = MediaState.PREVIEW,
        var previewExpiresAtMillis: Long? = null,
        var leaseExpiresAtMillis: Long? = null,
        var graceExpiresAtMillis: Long? = null,
        var terminalAtMillis: Long? = null,
        var releasedResult: MediaReleased? = null,
        var physicalCleanupPending: Boolean = false,
        val previewAttachment: AttachmentSlot = AttachmentSlot(AttachmentKind.UNCONFIRMED_PREVIEW),
    ) {
        fun markDiscardedPendingCleanup(nowEpochMillis: Long) {
            state = MediaState.DISCARDED
            physicalCleanupPending = true
            terminalAtMillis = nowEpochMillis
        }

        fun markReleased(nowEpochMillis: Long) {
            state = MediaState.RELEASED
            terminalAtMillis = nowEpochMillis
        }

        fun markExpired(nowEpochMillis: Long) {
            state = MediaState.EXPIRED
            terminalAtMillis = nowEpochMillis
        }
    }

    private data class RecordingStop(
        val generation: Long,
        var claimed: Boolean = false,
        val outcome: CompletableDeferred<MediaPreview> = CompletableDeferred(),
    )

    private data class AttachmentSlot(
        val kind: AttachmentKind,
        var highWatermark: Long = 0,
        var binding: AttachmentBinding? = null,
    )

    private data class AttachmentBinding(
        val generation: Long,
        val adapter: AndroidRenderTargetAdapter,
        val renderBinding: MediaCaptureRenderBinding = MediaCaptureRenderBinding(),
        val active: AtomicBoolean = AtomicBoolean(true),
        val committed: AtomicBoolean = AtomicBoolean(false),
        val mutationGate: MediaCaptureRenderMutationGate = MediaCaptureRenderMutationGate(),
        val cleanupStarted: AtomicBoolean = AtomicBoolean(false),
        val attachClaimed: AtomicBoolean = AtomicBoolean(false),
        val attachOwner: AtomicReference<Job?> = AtomicReference(null),
        val attachSettled: CompletableDeferred<Unit> = CompletableDeferred(),
        val cleanupSettled: CompletableDeferred<Unit> = CompletableDeferred(),
    ) {
        fun toCleanup(kind: AttachmentKind) = AttachmentCleanup(kind, this)
    }

    private sealed interface AttachmentScope {
        val kind: AttachmentKind
        val source: AndroidRenderSource

        fun currentSlotOrNull(): AttachmentSlot?

        fun currentSlotOrFail(): AttachmentSlot = currentSlotOrNull() ?: fail(FailureCode.INVALID_STATE)

        fun isStillAttachable(): Boolean

        data class Live(
            val session: SessionRecord,
            override val source: AndroidRenderSource,
        ) : AttachmentScope {
            override val kind = AttachmentKind.LIVE_PREVIEW

            override fun currentSlotOrNull() = session.liveAttachment

            override fun isStillAttachable() =
                session.state == SessionState.READY || session.state == SessionState.RECORDING
        }

        data class Preview(
            val media: MediaRecord,
            override val source: AndroidRenderSource,
        ) : AttachmentScope {
            override val kind = AttachmentKind.UNCONFIRMED_PREVIEW

            override fun currentSlotOrNull() = media.previewAttachment

            override fun isStillAttachable() = media.state == MediaState.PREVIEW
        }
    }

    private data class FrameworkOperation(
        val sessionHandle: SessionHandle,
        val epoch: Long,
        val generation: Long,
        val options: SessionOptions,
        val job: Job?,
        val active: AtomicBoolean = AtomicBoolean(true),
        val finished: AtomicBoolean = AtomicBoolean(false),
        val settled: CompletableDeferred<Unit> = CompletableDeferred(),
    )

    private data class FrameworkOperationStart(
        val operation: FrameworkOperation,
        val attachment: AttachmentCleanup?,
    )

    private sealed interface OperationAcquisition {
        data class Wait(val settled: CompletableDeferred<Unit>) : OperationAcquisition

        data class Acquired(val start: FrameworkOperationStart) : OperationAcquisition
    }

    private sealed interface FrameworkState {
        data object Available : FrameworkState

        data class Owned(val session: SessionRecord) : FrameworkState

        data class Closing(val session: SessionRecord) : FrameworkState

        data class Poisoned(val sessionHandle: SessionHandle?) : FrameworkState

        fun ownedBy(session: SessionRecord): Boolean = this is Owned && this.session === session

        fun ownerOrNull(): SessionRecord? =
            when (this) {
                is Owned -> session
                is Closing -> session
                is Available, is Poisoned -> null
            }
    }

    private enum class FrameworkCloseAttempt {
        Execute,
        Await,
    }

    private sealed interface RecordingStopClaim {
        data class Preview(val preview: MediaPreview) : RecordingStopClaim

        data class Await(val outcome: CompletableDeferred<MediaPreview>) : RecordingStopClaim

        data class Execute(
            val operation: FrameworkOperation,
            val generation: Long,
            val stop: RecordingStop,
            val timer: Job?,
            val attachment: AttachmentCleanup?,
        ) : RecordingStopClaim
    }

    private data class MediaTransitionPlan(
        val media: MediaRecord,
        val session: SessionRecord,
        val operation: FrameworkOperation?,
        val attachment: AttachmentCleanup?,
    )

    private data class ConfirmPlan(
        val session: SessionRecord,
        val media: MediaRecord,
        val expiresAt: Long,
        val operation: FrameworkOperation?,
        val attachment: AttachmentCleanup?,
    )

    private data class CancelPlan(
        val session: SessionRecord,
        val result: SessionCancelled,
        val initializeJob: Job?,
        val operation: FrameworkOperation?,
        val wasRecording: Boolean,
        val liveAttachment: AttachmentCleanup?,
        val preview: MediaRecord?,
        val previewAttachment: AttachmentCleanup?,
    )

    private data class FailurePlan(
        val session: SessionRecord,
        val operation: FrameworkOperation?,
        val wasRecording: Boolean,
        val liveAttachment: AttachmentCleanup?,
        val preview: MediaRecord?,
        val previewAttachment: AttachmentCleanup?,
    )

    private data class TimeoutPlan(
        val session: SessionRecord,
        val media: MediaRecord,
        val operation: FrameworkOperation?,
        val previewAttachment: AttachmentCleanup?,
        val liveAttachment: AttachmentCleanup?,
    )

    private data class ReleaseTransition(
        val result: MediaReleased,
        val thumbnailJob: ManagedThumbnailJob?,
        val exportJob: ManagedExportJob?,
        val graceDeadline: Long?,
    )

    private data class LeaseExpiry(
        val handle: MediaHandle,
        val thumbnailJob: ManagedThumbnailJob?,
        val exportJob: ManagedExportJob?,
    )

    private data class AttachmentPhase(
        val slot: AttachmentSlot,
        val binding: AttachmentBinding,
        val oldBinding: AttachmentCleanup?,
    )

    private data class AttachmentCleanup(
        val kind: AttachmentKind,
        val binding: AttachmentBinding,
    )

    private data class ShutdownPlan(
        val initializeJobs: List<Job>,
        val timerJobs: List<Job>,
        val operations: List<FrameworkOperation>,
        val attachments: List<AttachmentCleanup>,
        val claimedThumbnails: List<ManagedThumbnailJob>,
        val claimedExports: List<ManagedExportJob>,
        val media: List<MediaRecord>,
        val pendingDeletes: List<StoredMediaReference>,
        val frameworkOwner: SessionRecord?,
    ) {
        companion object {
            val EMPTY =
                ShutdownPlan(
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    emptyList(),
                    null,
                )
        }
    }

    private sealed interface ThumbnailTerminal {
        data object Success : ThumbnailTerminal

        data class Failure(val code: FailureCode) : ThumbnailTerminal
    }

    private sealed interface ThumbnailSuccessClaim {
        data object Lost : ThumbnailSuccessClaim

        data object Success : ThumbnailSuccessClaim

        data class Failure(val expiry: LeaseExpiry?) : ThumbnailSuccessClaim
    }

    private sealed interface ExportTerminal {
        data object Committing : ExportTerminal

        data object Success : ExportTerminal

        data class Failure(val code: FailureCode) : ExportTerminal
    }

    private data class ExportCommitPreparation(
        val ready: Boolean,
        val expiry: LeaseExpiry?,
        val failureClaimed: Boolean,
    ) {
        companion object {
            val READY = ExportCommitPreparation(ready = true, expiry = null, failureClaimed = false)
            val REJECTED = ExportCommitPreparation(ready = false, expiry = null, failureClaimed = false)
        }
    }

    private val SessionState.isTerminal: Boolean
        get() = this == SessionState.COMPLETED || this == SessionState.CANCELLED || this == SessionState.FAILED

    private val MediaState.isTerminal: Boolean
        get() = this == MediaState.DISCARDED || this == MediaState.RELEASED || this == MediaState.EXPIRED

    private companion object {
        const val PREVIEW_TTL_MILLIS = 600_000L
        const val LEASE_TTL_MILLIS = 86_400_000L
        const val READ_GRACE_MILLIS = 60_000L
        const val TOMBSTONE_MILLIS = 300_000L
        const val CLEANUP_RETRY_MILLIS = 1_000L
        const val FRAMEWORK_DRAIN_TIMEOUT_MILLIS = 5_000L
        const val MIN_THUMBNAIL_EDGE = 64
        const val MAX_THUMBNAIL_EDGE = 512
        const val MAX_THUMBNAIL_BYTES = 524_288
        const val MAX_THUMBNAIL_JOBS = 2
        const val MAX_EXPORT_BYTES = 52_428_800L
        const val MAX_EXPORT_READ_BUFFER_BYTES = 131_072
        const val MAX_EXPORT_JOBS = 4
        const val EXPORT_DEADLINE_MILLIS = 120_000L
        const val EXPORT_CANCEL_CONVERGENCE_MILLIS = 5_000L
        const val MAX_HANDLE_GENERATION_ATTEMPTS = 128
        val MIME_TYPE = Regex("^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$")
    }
}

private suspend inline fun bestEffortSuspend(crossinline action: suspend () -> Unit) {
    runCatching { action() }
}

private inline fun bestEffort(action: () -> Unit) {
    runCatching(action)
}

private fun fail(code: FailureCode): Nothing =
    throw MediaCaptureException(MediaCaptureFailure(code))
