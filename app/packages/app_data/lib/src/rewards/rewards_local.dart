import 'dart:async';

import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';
import 'rewards_failure.dart';
import 'rewards_fixture_handler.dart';
import 'rewards_models.dart';

part 'rewards_mapper.dart';

typedef RewardsMutationResult = ({RewardsSnapshot snapshot, bool didMutate});

final class RewardsLocalDataSource {
  RewardsLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;
  final StreamController<RewardsSnapshot> _snapshotUpdates =
      StreamController<RewardsSnapshot>.broadcast(sync: true);

  /// 成功 mutation 后发布的新 Snapshot；初始值仍通过 [load] 获取。
  Stream<RewardsSnapshot> get snapshotUpdates => _snapshotUpdates.stream;

  Future<RewardsSnapshot> load() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: RewardsFixtureHandler.loadKey),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _RewardsFixtureMapper.snapshot(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<RewardsMutationResult> consumeReminder({
    required String voucherId,
  }) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: RewardsFixtureHandler.consumeReminderKey,
        payload: <String, Object?>{'voucherId': voucherId},
      ),
    );
    final result = switch (response) {
      ApiSuccess<Object?>(:final payload) => _RewardsFixtureMapper.mutation(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
    if (result.didMutate) {
      _snapshotUpdates.add(result.snapshot);
    }
    return result;
  }

  Future<void> close() => _snapshotUpdates.close();

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = RewardsFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => RewardsFailureCode.unknownRequest,
      ApiFailureKind.transport => RewardsFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => RewardsFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'rewards.invalid_input' => RewardsFailureCode.invalidInput,
        'rewards.voucher_not_found' => RewardsFailureCode.voucherNotFound,
        'rewards.reminder_unavailable' =>
          RewardsFailureCode.reminderUnavailable,
        _ => RewardsFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
