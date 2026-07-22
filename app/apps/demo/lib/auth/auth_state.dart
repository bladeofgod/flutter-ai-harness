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
  AuthStateCoordinator()
    : _authService = AuthService(),
      _userService = UserService();

  final AuthService _authService;
  final UserService _userService;

  AuthSession? get session => _authService.session;

  bool get isLoggedIn => _authService.isLoggedIn;

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
    if (_authService.session == null && _userService.currentUser == null) {
      return;
    }

    _authService._replaceSession(null);
    _userService._replaceCurrentUser(null);
    _assertConsistentState();
    notifyListeners();
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
}
