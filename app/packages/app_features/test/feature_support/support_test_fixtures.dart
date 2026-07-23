import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart'
    show FixtureApiTransport, FixtureRequestHandler;
import 'package:app_data/support.dart';
import 'package:app_features/api/support_chat_api.dart';

final class DataSourceSupportApi implements SupportChatApi {
  const DataSourceSupportApi(this.source);

  final SupportLocalDataSource source;

  @override
  Future<SupportConversation> startConversation() => source.startConversation();

  @override
  Future<SupportConversation> selectQuestion(String questionId) =>
      source.selectQuestion(questionId);

  @override
  Future<SupportConversation> advanceTransition() => source.advanceTransition();

  @override
  Future<SupportConversation> sendMessage(String text) =>
      source.sendMessage(text);

  @override
  Future<SupportConversation> receiveReply() => source.receiveReply();

  @override
  Future<SupportConversation> requestRating() => source.requestRating();

  @override
  Future<SupportConversation> submitRating(int score) =>
      source.submitRating(score);
}

final class CountingSupportApi implements SupportChatApi {
  CountingSupportApi(this.delegate);

  final SupportChatApi delegate;
  int startCount = 0;
  int selectCount = 0;
  int advanceCount = 0;
  int sendCount = 0;
  int replyCount = 0;

  @override
  Future<SupportConversation> startConversation() {
    startCount += 1;
    return delegate.startConversation();
  }

  @override
  Future<SupportConversation> selectQuestion(String questionId) {
    selectCount += 1;
    return delegate.selectQuestion(questionId);
  }

  @override
  Future<SupportConversation> advanceTransition() {
    advanceCount += 1;
    return delegate.advanceTransition();
  }

  @override
  Future<SupportConversation> sendMessage(String text) {
    sendCount += 1;
    return delegate.sendMessage(text);
  }

  @override
  Future<SupportConversation> receiveReply() {
    replyCount += 1;
    return delegate.receiveReply();
  }

  @override
  Future<SupportConversation> requestRating() => delegate.requestRating();

  @override
  Future<SupportConversation> submitRating(int score) =>
      delegate.submitRating(score);
}

SupportChatApi createSupportApi() {
  final handler = SupportFixtureHandler();
  return DataSourceSupportApi(
    SupportLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    ),
  );
}

Future<void> immediateSupportDelay(Duration duration) async {}
