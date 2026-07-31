# Android Media Capture Native UI

Android native UI module path: `app/native/android/media_capture_ui/`.

The module is an Android Views full-screen presenter for the Android Media Capture Core. It depends
directly on the typed Core project and does not import Flutter, Channel/Wire DTOs, CameraX provider
types, media paths, URI/file descriptors, raw bytes, or Core internal rendering SPI.

## Build And Dependency Boundary

The UI module is a standalone Android Library. Its own `settings.gradle.kts` includes the Core project
from `../media_capture` as `:media_capture_core`, so the Demo Host, Android Core build files, shared
Capability/Wire contracts, CI and Flutter plugin wiring are unchanged.

Pinned module toolchain and dependencies:

| Item | Version |
| --- | --- |
| Gradle wrapper | 8.12, reused from Demo Host command |
| Android Gradle Plugin | 8.9.1 |
| Kotlin Android plugin | 2.1.0 |
| Java source/target | 11 |
| compileSdk / minSdk | 35 / 23 |
| AndroidX Core KTX | 1.16.0 |
| AndroidX Lifecycle Runtime KTX | 2.9.2 |
| kotlinx.coroutines Android/Test | 1.9.0 |
| AndroidX Test Core / Ext JUnit | 1.6.1 / 1.2.1 |
| Robolectric | 4.14.1 |

The module does not declare camera, microphone, storage, photo library, Activity, Service or exported
components in its Manifest. Host permission declaration and final platform gate remain separate tasks.

## Public Entry

`MediaCaptureUiPresenter` is the production entry point:

```kotlin
val presenter = MediaCaptureUiPresenter(
    activity = activity,
    lifecycleOwner = lifecycleOwner,
    mediaCapture = androidMediaCapture,
)
val session = presenter.present(MediaCaptureUiConfig())
val result = session.awaitResult()
```

`present` must run on the Android main thread with a live Activity and a LifecycleOwner in at least
`CREATED` state. Production always uses `Dispatchers.Main.immediate`; dispatcher injection is internal to
module tests. A shared weak identity registry compares the presentable Activity with `===`, not
`equals`/`hashCode` or a Fragment/view lifecycle identity, to enforce one active presentation across
Presenter instances. An application Activity lifecycle callback always closes the flow when that Activity
is destroyed, even when the consumer supplied a separate LifecycleOwner. The slot is released only after
Core/session/surface/Dialog cleanup completes. The full-screen flow uses an Android `Dialog`, and
`MediaCaptureFlowResult` has exactly one terminal outcome:

- `Confirmed(ConfirmedMedia)`
- `Cancelled`
- `Failure(MediaCaptureFailure)`

Consumer code receives only Core confirmed lease metadata on confirm. Cancel is a normal terminal result.
Failures carry Core stable `FailureCode` values without backend details. `MediaCaptureFlowSession` exposes
only `awaitResult()`, `dismiss()` and `onDisplayRotationChanged()`; callers cannot cancel the internal
completion primitive or bypass terminal cleanup.

## UI Flow

The first version follows the approved capture layout without storing external design identifiers or
assets in the repository. The live camera remains full bleed above a fixed 112 dp black control area. The
black visual background extends through the bottom system inset, while controls remain in the 112 dp safe
content area above it; camera content must not show behind gesture or navigation insets. The module draws
its small monochrome controls locally, uses an 80 dp photo shutter, expands to a 98 dp recording progress
control, and reserves primary blue for progress and confirmation. Controls retain content descriptions and
at least 48 dp touch targets.

Supported interactions:

- Tap shutter to take a photo.
- Long-press shutter to start recording; release to stop.
- While recording, vertical movement adjusts zoom. UI gesture values are clamped to the latest
  `SessionReady.minZoomFactor/maxZoomFactor` snapshot before calling Core.
- Long-press recording hides both side actions immediately. After stop/retake returns to a ready state,
  flash and switch-camera are restored only if the latest snapshot advertises those capabilities.
- Releasing while CameraX is still acknowledging recording stores a pending stop intent; the coordinator
  stops immediately after framework start instead of recording until the duration limit.
- Tap canvas sends normalized focus coordinates in `[0, 1]` only when `focusPointSupported` is true.
- Switch camera and flash are enabled from the latest `SessionReady` snapshot instead of probing by
  failed calls.
- Flash initializes from the latest supported snapshot and exposes its current mode through visual
  selection and accessibility description.
- Preview uses the top close action for retake and a compact bottom `send` action for confirm. The
  platform Back action still cancels the flow until terminal cleanup starts.

The UI composes Core concrete `MediaCaptureRenderView` only. Live preview attaches with
`attachLivePreview`; unconfirmed preview attaches with `attachUnconfirmedPreview`. Rotation, retake and
preview transitions allocate a fresh owner generation and fresh surface. Old surfaces are cleaned through
`onPreviewOwnerDestroyed`.

## Lifecycle And Cleanup

`MediaCaptureFlowCoordinator` owns the session flow:

- Owns a module-scoped `SupervisorJob` on the injected UI dispatcher; cleanup does not depend on an
  Activity `lifecycleScope` that may already be cancelled.
- Starts Core `startSession` and collects `sessionObservation`.
- Publishes a newly returned Session only after atomically rechecking the owner gate; a Session returned
  after owner close is cancelled before terminal ownership can be released.
- Creates a fresh `MediaCaptureRenderSurfaceOwner` with positive owner generation for each surface.
- Replaces live/unconfirmed surfaces on rotation, retake and preview changes.
- Calls `onAppBackgrounded` when a still-alive owner moves to the background, removes the retired
  surface, and preserves the flow. Foreground recovery allocates a strictly higher owner generation
  and explicitly reattaches the latest live or unconfirmed preview.
- Calls `onPreviewOwnerDestroyed` during owner destroy, terminal completion and surface replacement.
- Owner destroy and dismiss synchronously close an atomic action gate and cancel the in-flight action;
  cleanup does not queue behind ordinary capture actions.
- Session observations are applied sequentially under the action transaction gate, so a newer StateFlow
  value cannot cancel a surface destroy/create/attach transaction already in progress.
- Cancels the Core session for cancel/failure/owner-destroy outcomes, then stops observation and
  recording timer jobs, destroys the surface, unbinds UI callbacks, releases the owner slot, and
  completes the public result last. A confirmed lease that arrives after another terminal outcome is
  released through Core instead of being dropped.
- Terminal cleanup waits up to five seconds for the cancelled action to settle. A confirm that committed
  a lease before cancellation is settled with the retained preview handle even if Core did not return
  `ConfirmedMedia`. Lease release uses a short bounded retry first; a still-unsettled handle is transferred
  to a process-owned cleanup scope with bounded exponential backoff until Core confirms release or
  `media_invalid`. The Activity slot remains occupied until that cleanup recovers. Other cleanup failure or
  timeout completes the public result but deliberately keeps the Activity slot poisoned, preventing a new
  flow from sharing possibly live native resources.
- Reserves UI phases synchronously, drops repeated/obsolete actions, and deduplicates preview state so a
  photo or manual recording stop attaches one unconfirmed surface exactly once.

The coordinator does not access `PreviewView`, `SurfaceProvider`, Core session internals, renderer source,
private media files, path/URI/read scope or Wire data. It calls only the Core public `MediaCapture` API.

## Accessibility And Layout

Controls use at least 48 dp touch targets and content descriptions for cancel, capture, stop recording,
switch camera, flash with current mode, retake and confirm. Recording status is represented by a gray
track and primary-blue progress arc instead of explanatory text. System bar Insets become content
padding. Robolectric coverage checks 320 px width, landscape, enlarged font scale and bounded child
layout. Visible strings and accessibility labels use one locale at a time through complete default and
Simplified Chinese resources. The primary capture surface remains unframed.

## Testing Boundary

Module tests cover:

- Gesture mutual exclusion, tap/long-press threshold, release-before-recording-start, disabled video,
  vertical zoom threshold and clamp.
- Start/live attach, rotation replacement generation, owner cleanup and single attach behavior.
- Click photo, preview attach, retake, confirm and cancel terminal handling.
- Long-press recording, release/auto-stop preview, repeated action after failure and exactly-once result.
- Cross-Presenter owner exclusion, cleanup-before-reentry, invalid owner/main-thread rejection and
  non-cancellable internal completion ownership.
- Same-Activity exclusion across distinct LifecycleOwners, cleanup-failure slot poisoning and fixed
  production Main-dispatcher ownership.
- Owner-destroy/confirm races, late confirmed lease release, repeated photo gating, and exactly-once
  photo/manual-stop preview attachment.
- Late start Session cancellation, committed-confirm cancellation settlement and failed surface
  retirement without replacement attach.
- Background suspension, foreground higher-generation reattach, and terminal owner-destroy cleanup.
- View accessibility/flash state, photo and recording control geometry, recording side-action removal,
  48 dp preview confirmation target, preview actions, full focus touch sequence with a concrete render
  child, system Insets, 320 px/landscape/large-font layout and normalized focus.

The Fake Core implements only the public `MediaCapture` interface. It does not claim real Camera preview,
CameraX binding, system permission dialogs, hardware recording, encoder behavior or device performance.
Those remain Android quality-gate and final integration responsibilities.

Local validation command:

```bash
JAVA_HOME=<JDK_17_OR_NEWER> ANDROID_HOME=<ANDROID_SDK> \
  app/apps/demo/android/gradlew -p app/native/android/media_capture_ui test lint
```

Real-device gaps:

- Real Camera and Microphone runtime permission dialogs.
- CameraX live preview frames, tap-focus hardware behavior and zoom smoothness.
- Photo capture and video recording on device.
- Automatic video stop at Core duration limit with real encoder output.
- Rotation/background/foreground behavior in an Activity host.
- Vendor camera interruption and performance/memory behavior.
