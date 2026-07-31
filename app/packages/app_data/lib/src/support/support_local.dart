import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';
import 'support_failure.dart';
import 'support_fixture_handler.dart';
import 'support_models.dart';

part 'support_mapper.dart';

final class SupportLocalDataSource {
  const SupportLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SupportConversation> startConversation() =>
      _request(SupportFixtureHandler.startConversationKey);

  Future<SupportConversation> selectQuestion(String questionId) => _request(
    SupportFixtureHandler.selectQuestionKey,
    payload: <String, Object?>{'questionId': questionId},
  );

  Future<SupportConversation> advanceTransition() =>
      _request(SupportFixtureHandler.advanceTransitionKey);

  Future<SupportConversation> sendMessage(String text) => _request(
    SupportFixtureHandler.sendMessageKey,
    payload: <String, Object?>{'text': text},
  );

  Future<SupportConversation> sendMedia(SupportMediaContent media) => _request(
    SupportFixtureHandler.sendMediaKey,
    payload: <String, Object?>{
      'resourceId': media.resourceId.value,
      'mediaType': media.type.name,
      'label': media.label,
      'durationMillis': media.duration?.inMilliseconds,
    },
  );

  Future<SupportConversation> receiveReply() =>
      _request(SupportFixtureHandler.receiveReplyKey);

  Future<SupportConversation> requestRating() =>
      _request(SupportFixtureHandler.requestRatingKey);

  Future<SupportConversation> submitRating(int score) => _request(
    SupportFixtureHandler.submitRatingKey,
    payload: <String, Object?>{'score': score},
  );

  Future<SupportConversation> _request(String key, {Object? payload}) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(key: key, payload: payload),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _SupportFixtureMapper.conversation(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mapped = SupportFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => SupportFailureCode.unknownRequest,
      ApiFailureKind.transport => SupportFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => SupportFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'support.invalid_state' => SupportFailureCode.invalidState,
        'support.question_not_found' => SupportFailureCode.questionNotFound,
        _ => SupportFailureCode.invalidResponse,
      },
    });
    if (failure.stackTrace case final stackTrace?) {
      Error.throwWithStackTrace(mapped, stackTrace);
    }
    throw mapped;
  }
}
