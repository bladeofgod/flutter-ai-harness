import 'dart:async';

import 'media_playback_driver.dart';

typedef ActiveMediaPlayerRevoked = Future<void> Function();

final class ActiveMediaPlayerLease {
  const ActiveMediaPlayerLease._(this._entry);

  final _ActiveMediaPlayerEntry _entry;
}

final class ActiveMediaPlayerCoordinator {
  ActiveMediaPlayerCoordinator._();

  static _ActiveMediaPlayerEntry? _active;
  static Future<void>? _transition;

  static Future<ActiveMediaPlayerLease> activate(
    MediaPlaybackDriver driver, {
    required ActiveMediaPlayerRevoked onRevoked,
  }) {
    return _enqueue(() async {
      final entry = _ActiveMediaPlayerEntry(driver, onRevoked);
      final previous = _active;
      if (previous != null) {
        _active = null;
        previous.isBeingRevoked = true;
        try {
          await previous.onRevoked();
        } on Object {
          try {
            await previous.disposeOnce();
          } on Object {
            // The previous owner still gets a chance to release its media lease.
          }
        } finally {
          previous.isBeingRevoked = false;
        }
      }
      _active = entry;
      return ActiveMediaPlayerLease._(entry);
    });
  }

  static bool isActive(ActiveMediaPlayerLease lease) {
    return identical(_active, lease._entry);
  }

  static Future<void> release(ActiveMediaPlayerLease lease) {
    final entry = lease._entry;
    if (entry.isBeingRevoked) {
      return entry.disposeOnce();
    }
    return _enqueue(() async {
      if (identical(_active, entry)) {
        _active = null;
      }
      await entry.disposeOnce();
    });
  }

  static Future<void> resetForTesting() {
    return _enqueue(() async {
      final active = _active;
      _active = null;
      try {
        await active?.disposeOnce();
      } on Object {
        // Tests reset global ownership even when a disposal Fake throws.
      }
    });
  }

  static Future<T> _enqueue<T>(Future<T> Function() operation) async {
    while (true) {
      final pending = _transition;
      if (pending == null) break;
      await pending;
    }
    final completed = Completer<void>();
    final acquired = completed.future;
    _transition = acquired;
    try {
      return await operation();
    } finally {
      if (identical(_transition, acquired)) {
        _transition = null;
      }
      completed.complete();
    }
  }
}

final class _ActiveMediaPlayerEntry {
  _ActiveMediaPlayerEntry(this.driver, this.onRevoked);

  final MediaPlaybackDriver driver;
  final ActiveMediaPlayerRevoked onRevoked;
  Future<void>? _disposeFuture;
  bool isBeingRevoked = false;

  Future<void> disposeOnce() {
    return _disposeFuture ??= driver.dispose();
  }
}
