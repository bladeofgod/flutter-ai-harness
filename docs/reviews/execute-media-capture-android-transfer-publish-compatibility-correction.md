---
task: media-capture-android-transfer-publish-compatibility-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# Android Transfer Publish Compatibility Review

## Scope

- Task card: `docs/tasks/done/media-capture-android-transfer-publish-compatibility-correction.md`
- Evidence: `docs/reviews/test-evidence/media-capture-android-transfer-publish-compatibility-correction.log`
- Implementation focus:
  - `app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt`
  - `app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/MediaCaptureTransferStoreTest.kt`
  - `app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/TestTransferFileSystem.kt`
  - `app/packages/app_media_capture_bridge/android/src/androidTest/kotlin/com/example/media_capture/MediaCaptureTransferStoreInstrumentedTest.kt`
  - `scripts/quality/media-capture-android.sh`
  - `docs/bridge/media-capture-android.md`
  - `docs/native/media-capture-android-verification.md`

## Result

Passed. The Android Transfer Store no longer publishes by hard link or rename. It reserves the final extension path with exclusive create and no-follow flags, writes through the same descriptor, and commits only after descriptor/path identity, regular-file type, size, link-count, fsync and close checks pass.

## Review Notes

Initial review found one P1: descriptor close failure could be swallowed and the sink could still be marked committed. The implementation now propagates close failure, keeps the descriptor retryable, and only marks committed after a verified close. `abort()` now retries close before cleanup and only marks aborted after the close path succeeds.

Initial review also found documentation/test precision issues. The Android verification documentation now references the current compatibility evidence, the bridge docs describe final-path reservation instead of staging publish, and the instrumented test name no longer claims it simulates a hard-link-rejecting filesystem. The Android quality gate now statically rejects production `Os.link(` and `.renameTo(` usage in the Transfer Store.

## Verification

- Focused Debug/Release Transfer Store tests passed after adding close-retry coverage.
- Full Android media capture gate passed with exit code 0 in `docs/reviews/test-evidence/media-capture-android-transfer-publish-compatibility-correction.log`.
- The gate built the instrumented APK suites. It did not run `connectedDebugAndroidTest` because no ready emulator was available.
- User manually verified Android 16 customer-service capture -> preview -> send succeeds on the connected device.

## Residual Risk

No open P0/P1/P2. The remaining gap is device matrix breadth: the manual pass covers the connected Android 16 device and happy path only; emulator/API 23 and broader permission/interruption cases remain separate validation work.
