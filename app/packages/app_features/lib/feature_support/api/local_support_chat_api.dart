import 'package:app_data/support.dart';

import '../../api/support_chat_api.dart';

final class LocalSupportChatApi implements SupportChatApi {
  const LocalSupportChatApi({required SupportLocalDataSource dataSource})
    : _dataSource = dataSource;

  final SupportLocalDataSource _dataSource;

  @override
  Future<SupportConversation> startConversation() =>
      _dataSource.startConversation();

  @override
  Future<SupportConversation> selectQuestion(String questionId) =>
      _dataSource.selectQuestion(questionId);

  @override
  Future<SupportConversation> advanceTransition() =>
      _dataSource.advanceTransition();

  @override
  Future<SupportConversation> sendMessage(String text) =>
      _dataSource.sendMessage(text);

  @override
  Future<SupportConversation> receiveReply() => _dataSource.receiveReply();

  @override
  Future<SupportConversation> requestRating() => _dataSource.requestRating();

  @override
  Future<SupportConversation> submitRating(int score) =>
      _dataSource.submitRating(score);
}
