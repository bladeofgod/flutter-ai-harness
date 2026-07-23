import 'package:app_data/support.dart';

/// Support Chat 页面所需的最小本地会话边界。
abstract interface class SupportChatApi {
  Future<SupportConversation> startConversation();

  Future<SupportConversation> selectQuestion(String questionId);

  Future<SupportConversation> advanceTransition();

  Future<SupportConversation> sendMessage(String text);

  Future<SupportConversation> receiveReply();

  Future<SupportConversation> requestRating();

  Future<SupportConversation> submitRating(int score);
}
