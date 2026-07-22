import 'package:app_data/app_data.dart';
import 'package:demo_app/auth/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthStateCoordinator', () {
    test('starts with a consistent logged-out state', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.isLoggedIn, isFalse);
      expect(coordinator.session, isNull);
      expect(coordinator.value, isNull);
    });

    test('owns state independently from other coordinators', () {
      final first = AuthStateCoordinator();
      final second = AuthStateCoordinator();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var secondNotificationCount = 0;
      second.addListener(() => secondNotificationCount += 1);

      first.authenticate(_authResult());

      expect(first.isLoggedIn, isTrue);
      expect(second.isLoggedIn, isFalse);
      expect(second.value, isNull);
      expect(secondNotificationCount, 0);
    });

    test('publishes one consistent snapshot after authentication', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      final snapshots = <_AuthSnapshot>[];
      coordinator.addListener(() {
        snapshots.add(_AuthSnapshot.capture(coordinator));
      });

      coordinator.authenticate(_authResult());

      expect(snapshots, hasLength(1));
      expect(snapshots.single.isLoggedIn, isTrue);
      expect(snapshots.single.sessionUserId, 'user-romina');
      expect(snapshots.single.currentUserId, 'user-romina');
    });

    test('does not notify when the same authentication is committed twice', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      final result = _authResult();
      var notificationCount = 0;
      coordinator.addListener(() => notificationCount += 1);

      coordinator.authenticate(result);
      coordinator.authenticate(result);

      expect(notificationCount, 1);
    });

    test('updates only a user matching the current session', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.authenticate(_authResult());
      final snapshots = <_AuthSnapshot>[];
      coordinator.addListener(() {
        snapshots.add(_AuthSnapshot.capture(coordinator));
      });

      coordinator.updateCurrentUser(
        coordinator.value!.copyWith(displayName: 'Updated Romina'),
      );

      expect(snapshots, hasLength(1));
      expect(snapshots.single.sessionUserId, 'user-romina');
      expect(snapshots.single.currentUserId, 'user-romina');
      expect(coordinator.value!.displayName, 'Updated Romina');
    });

    test('rejects a mismatched current user without changing state', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.authenticate(_authResult());
      final originalUser = coordinator.value;
      var notificationCount = 0;
      coordinator.addListener(() => notificationCount += 1);

      expect(
        () => coordinator.updateCurrentUser(_user(id: 'another-user')),
        throwsStateError,
      );
      expect(coordinator.value, same(originalUser));
      expect(notificationCount, 0);
    });

    test('clears session and user before one logout notification', () {
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.authenticate(_authResult());
      final snapshots = <_AuthSnapshot>[];
      coordinator.addListener(() {
        snapshots.add(_AuthSnapshot.capture(coordinator));
      });

      coordinator.logout();
      coordinator.logout();

      expect(snapshots, hasLength(1));
      expect(snapshots.single.isLoggedIn, isFalse);
      expect(snapshots.single.sessionUserId, isNull);
      expect(snapshots.single.currentUserId, isNull);
    });
  });
}

AuthResult _authResult() {
  final user = _user(id: 'user-romina');
  return AuthResult(
    user: user,
    session: AuthSession(id: 'session-user-romina', userId: 'user-romina'),
  );
}

UserEntity _user({required String id}) {
  return UserEntity(
    id: id,
    displayName: 'Romina',
    email: EmailAddress('romina@example.com'),
    callingCode: CountryCallingCode('+44'),
    phoneNumber: PhoneNumber('7700900123'),
    avatar: UserAvatar.asset('images/auth/romina.png'),
  );
}

final class _AuthSnapshot {
  const _AuthSnapshot({
    required this.isLoggedIn,
    required this.sessionUserId,
    required this.currentUserId,
  });

  factory _AuthSnapshot.capture(AuthStateCoordinator coordinator) {
    return _AuthSnapshot(
      isLoggedIn: coordinator.isLoggedIn,
      sessionUserId: coordinator.session?.userId,
      currentUserId: coordinator.value?.id,
    );
  }

  final bool isLoggedIn;
  final String? sessionUserId;
  final String? currentUserId;
}
