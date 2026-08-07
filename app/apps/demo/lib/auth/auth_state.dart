import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:flutter/foundation.dart';

/// Stores the in-memory session without exposing mutation outside this library.
final class AuthService {
  AuthSession? _session;

  AuthSession? get session => _session;

  bool get isLoggedIn => _session != null;

  void _replaceSession(AuthSession? session) {
    _session = session;
  }
}

/// Stores the current user without owning authentication or notifications.
final class UserService {
  UserEntity? _currentUser;

  UserEntity? get currentUser => _currentUser;

  void _replaceCurrentUser(UserEntity? user) {
    _currentUser = user;
  }
}

/// Commits session and user changes before publishing one consistent snapshot.
final class AuthStateCoordinator extends ChangeNotifier
    implements CurrentUserProvider {
  AuthStateCoordinator({void Function()? onSessionReset})
    : _authService = AuthService(),
      _userService = UserService() {
    if (onSessionReset != null) {
      attachSessionReset(onSessionReset);
    }
  }

  final ChangeNotifier _authRefreshNotifier = ChangeNotifier();

  final AuthService _authService;
  final UserService _userService;
  final List<_SessionResetRegistration> _sessionResetRegistrations = [];
  bool _isDisposed = false;
  bool _isLoggingOut = false;

  VoidCallback attachSessionReset(VoidCallback reset) {
    final registration = _SessionResetRegistration(reset);
    _sessionResetRegistrations.add(registration);
    var isAttached = true;
    return () {
      if (!isAttached) {
        return;
      }
      isAttached = false;
      _sessionResetRegistrations.remove(registration);
    };
  }

  AuthSession? get session => _authService.session;

  bool get isLoggedIn => _authService.isLoggedIn;

  /// 仅在登录态边界变化时通知 Router，避免资料编辑触发路由重建。
  Listenable get authRefreshListenable => _authRefreshNotifier;

  @override
  UserEntity? get value => _userService.currentUser;

  void authenticate(AuthResult result) {
    if (_authService.session == result.session &&
        _userService.currentUser == result.user) {
      return;
    }

    _userService._replaceCurrentUser(result.user);
    _authService._replaceSession(result.session);
    _assertConsistentState();
    _authRefreshNotifier.notifyListeners();
    notifyListeners();
  }

  void updateCurrentUser(UserEntity user) {
    final currentSession = _authService.session;
    if (currentSession == null || currentSession.userId != user.id) {
      throw StateError(
        'Current user updates require a matching authenticated session.',
      );
    }
    if (_userService.currentUser == user) {
      return;
    }

    _userService._replaceCurrentUser(user);
    _assertConsistentState();
    notifyListeners();
  }

  void logout() {
    if (_isLoggingOut ||
        (_authService.session == null && _userService.currentUser == null)) {
      return;
    }

    _isLoggingOut = true;
    final failures = <FlutterErrorDetails>[];
    final registrations = List<_SessionResetRegistration>.of(
      _sessionResetRegistrations,
    );
    try {
      for (final registration in registrations) {
        try {
          registration.reset();
        } on Object catch (_, stackTrace) {
          failures.add(
            FlutterErrorDetails(
              exception: const _SessionResetFailure(),
              stack: stackTrace,
              library: 'demo_app',
              context: ErrorDescription('while resetting a user session'),
            ),
          );
        }
      }
      _authService._replaceSession(null);
      _userService._replaceCurrentUser(null);
      _assertConsistentState();
      _authRefreshNotifier.notifyListeners();
      notifyListeners();
    } finally {
      _isLoggingOut = false;
    }
    for (final failure in failures) {
      FlutterError.reportError(failure);
    }
  }

  void _assertConsistentState() {
    assert(() {
      final currentSession = _authService.session;
      final currentUser = _userService.currentUser;
      final isLoggedOut = currentSession == null && currentUser == null;
      final isMatchingLogin =
          currentSession != null &&
          currentUser != null &&
          currentSession.userId == currentUser.id;
      return isLoggedOut || isMatchingLogin;
    }(), 'Auth session and current user must form one consistent snapshot.');
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _sessionResetRegistrations.clear();
    _authRefreshNotifier.dispose();
    super.dispose();
  }
}

final class _SessionResetRegistration {
  const _SessionResetRegistration(this.reset);

  final VoidCallback reset;
}

final class _SessionResetFailure implements Exception {
  const _SessionResetFailure();

  @override
  String toString() => 'SessionResetFailure(<redacted>)';
}
