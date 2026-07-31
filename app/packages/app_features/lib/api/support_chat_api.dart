import 'package:app_core/app_core.dart';
import 'package:app_data/support.dart';

final class SupportMediaSendReceipt {
  const SupportMediaSendReceipt({
    required this.conversation,
    required this.acceptedMessageId,
    required this.resourceId,
  });

  final SupportConversation conversation;
  final String acceptedMessageId;
  final MediaResourceId resourceId;

  @override
  String toString() => 'SupportMediaSendReceipt(resource: <redacted>)';
}

/// Support Chat 页面所需的最小本地会话边界。
abstract interface class SupportChatApi {
  Future<SupportConversation> startConversation();

  Future<SupportConversation> selectQuestion(String questionId);

  Future<SupportConversation> advanceTransition();

  Future<SupportConversation> sendMessage(String text);

  Future<SupportMediaSendReceipt> sendMedia(SupportMediaContent media);

  Future<SupportConversation> receiveReply();

  Future<SupportConversation> requestRating();

  Future<SupportConversation> submitRating(int score);

  Future<void> releaseRetiredMedia();

  Future<void> clearSessionMedia();

  Future<void> dispose();
}
