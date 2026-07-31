# Android Media Capture Bridge Adapter

Android Adapter path: `app/packages/app_media_capture_bridge/android/`.

The Adapter implements the Android entry declared by the shared plugin pubspec:
`com.example.media_capture.MediaCaptureBridgePlugin`. It owns only the Flutter/Native boundary. Camera,
media files, render sources, thumbnail generation and the full-screen capture state machine remain in the
Android Core and Native UI modules. The Adapter additionally owns the short-lived Wire V3 transfer store;
that store is transport infrastructure and is not a second media library.

## Dependency Boundary

The standalone Android Library includes the existing Core and UI Gradle projects by repository-relative
paths. Its only production dependencies are Flutter embedding API, AndroidX Core/Lifecycle,
kotlinx.coroutines, Android Core and Android Native UI. The Flutter embedding version is derived from the
selected Flutter SDK `engine.stamp` and resolved from Flutter's official Maven repository.

The Adapter Manifest declares no permission, Activity, Service or exported component. Camera and
Microphone permission declarations remain a Host responsibility. The Adapter injects a narrow Android
permission delegate into Core. `present_capture_flow` reserves its presentation slot, checks or requests
Camera, and also checks or requests Microphone when video with audio is enabled; only a granted preflight
may create the full-screen UI. Direct operations retain the Core timing: Camera at explicit Session start
and Microphone when audio recording starts. Core checks again before touching CameraX.

The Android platform Gate removed the previous direct `activity-ktx` dependency after confirming that no
Adapter production source consumes it; Activity ownership continues to arrive through Flutter's
`ActivityPluginBinding`, while permission helpers use AndroidX Core and lifecycle checks use AndroidX
Lifecycle.

## Wire Boundary

The command transport rejects encoded messages above 65536 bytes before `StandardMethodCodec` creates a
MethodCall or Map. Event control messages have a 4096-byte bound. `MediaCaptureWireCodec` then validates the
complete Wire V3 request before constructing Native models:

- exact envelope and payload key sets;
- Wire version and requestId pattern, plus opaque handles constrained only to 1 through 128 characters;
- strict Boolean/String/Int/Double types, finite numbers and signed platform integers;
- closed enum/list values, list cardinality and duplicate rejection;
- duration, focus, zoom and thumbnail edge ranges.

Raw Maps stop at the codec. Core and UI receive `SessionOptions`, `SessionHandle`, `MediaHandle`,
`FlashMode` and other typed Native models. Every Native result/event is validated again before encoding.
Thumbnail output is bounded to 524288 bytes and the requested pixel edge, copied before Channel delivery,
and checked as structurally valid JPEG with canonical JFIF only; APP metadata, COM, invalid marker order,
dimension mismatch and source metadata are rejected as `wire_encoding_failed`.

Failures use static messages and closed details. Payloads, requestIds, handles, media bytes, paths, URI,
owner generations, SDK objects and raw exceptions are never copied into error details or logs.

## Scoped Transfer Store

`materialize_media_resource` accepts only an active confirmed `mediaHandle`. Under the lifecycle coordinator
lock, the Adapter first reserves one of four active export slots and the media's declared byte length against
the 104857600-byte attachment budget. Capacity rejection occurs before Core is called. The Adapter then
creates a 128-bit CSPRNG, unpadded base64url export handle and an empty staging file beneath
`Context.cacheDir/app_media_capture_bridge/exports`.

The typed `MediaCopySink` writes at most 52428800 bytes directly to that staging file. It validates Core's
media type, MIME and declared/actual length, flushes and syncs the output, and atomically renames within the
same directory. Only after the committed file is registered does the Adapter return a canonical
`Uri.fromFile` locator on the Android main thread. The URI is validated against the shared Wire golden
vectors and is never logged, persisted, emitted as an event or placed in error details. Export handles use
`android.util.Base64` so the declared Android API 23 minimum remains supported without desugaring.

The store TTL is five minutes. `release_materialized_media`, TTL expiry, Flutter completion failure, Engine
detach and a late Core result all delete staging/final files before releasing active count/bytes. Release is
idempotent through a 4096-entry, five-minute tombstone registry; concurrent releases join one cleanup claim.
Delete failure returns only `transfer_store_unavailable`, retains the record and capacity, and permits the
same reserved cleanup to be retried without exposing a path. The Controller performs bounded exponential
background retries, and later release/materialize calls re-enter retained cleanup. Plugin startup rejects a
symlinked/non-canonical root and sweeps prior-process residue before opening the transfer generation.

Materialize and export release never call Core `releaseMedia`. The Flutter owner must import the temporary
file first, then release the export handle and independently release the source media lease.

## Lifecycle Coordinator

`MediaCaptureBridgeController` is the single linearization boundary for:

- Engine and UI owner generations;
- 32 pending requests and 4096 completed request tombstones with a 300-second TTL;
- four active transfer exports, 104857600 active bytes and 4096 release tombstones;
- exactly-once Flutter completion;
- Session, unconfirmed Preview and confirmed lease adoption;
- one presentation slot and one Event sink generation;
- Activity/Engine boundary scans and late-result cleanup.

Core calls execute outside the coordinator lock. A callback re-enters the coordinator on the Android main
dispatcher to decide whether its generation is still open, adopt any Session/lease, reserve the completed
tombstone and synchronously encode the Flutter reply before the boundary can interleave. A boundary first
removes and tombstones affected requests, retains their in-flight operations, cleans the Native resources,
then sends `bridge_unavailable`. A late Session is cancelled, a late confirmed lease is released, and a late
thumbnail clears both Native and encoded copies without a second Flutter callback. Failed Session/lease/Core
cleanup stays in an owner-scoped registry with bounded exponential retry; ownership is never discarded just
because the first cleanup attempts failed.

Activity replacement creates a new Core because CameraX is bound to a LifecycleOwner. The new owner may be
attached immediately, but new capture work remains blocked until the old owner's presentation, in-flight
operations, Sessions, Previews and failed cleanup have drained. Already delivered leases remain Engine-owned
and continue to route to the original Core for thumbnail/release. That old Core stays alive through
release/expiry grace until `media_read_revoked`, then closes. Engine detach closes the transfer generation,
releases leases, waits for late operations, aborts sinks, and deletes staging/committed transfer files before
completing pending Flutter callbacks. It then closes every retained Core, cancels each event collector and
finally cancels the Engine scope.

## Presentation And Events

`present_capture_flow` requires the currently attached Activity and invokes `MediaCaptureUiPresenter` and
all dismiss operations on the Android main dispatcher.
`dismiss_capture_flow` accepts only the originating presentation request ID. A matching active flow is
dismissed on the main dispatcher and its original Flutter result completes as `capture_flow_cancelled`;
unknown or already settled IDs are idempotent no-ops.
Concurrent presentation returns `presentation_conflict`. Confirmed/cancelled/failure outcomes map to the
three Wire terminal forms; confirmed media is adopted before success. Activity or Engine detach dismisses
the current UI and wins any still-pending completion.

Core events are encoded before resource adoption on the current Event sink generation and delivered on the
Android main dispatcher. The Adapter handles the standard Flutter `listen`/`cancel` wire messages directly,
instead of using Android's `EventChannel` wrapper that implicitly cancels the old sink before a repeated
listen. The five Wire events and `session_timeout` failure envelope are supported. A second listener is
rejected without replacing the first. Outbound encoding failure terminates only the current sink as
`wire_encoding_failed`; relisten is allowed afterward. Native-only attachment revocation is never projected
to Flutter.

## Testing Boundary

Debug and Release each run 61 local tests covering all 16 methods, five events, timeout failure, three presentation
outcomes, malformed input, output encoding, request capacities, duplicate/tombstone TTL, listener
generation, bounded pre-decode transports, permission callback identity, main-thread presentation,
adoption-before-success, Activity replacement, Engine detach, failed cleanup retry, late
Session/lease/thumbnail cleanup, transfer commit/release, capacity, TTL, restart sweep, symlink rejection,
API 23 base64url handles and shared canonical file-URI vectors. Lint runs with warnings as errors and checks
Core/UI dependencies.

These JVM/Robolectric/Fake results do not prove Flutter Host auto-registration, real Activity presentation,
CameraX frames, system permission dialogs, hardware recording or device performance. Android Quality Gate
and final cross-runtime Integration own those checks.
