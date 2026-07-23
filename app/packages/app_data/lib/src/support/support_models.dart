import '../checkout/checkout_models.dart';

enum SupportConversationStage {
  starting,
  connecting,
  typing,
  active,
  rating,
  rated,
}

enum SupportParticipant { customer, supportAgent, system }

sealed class SupportMessageContent {
  const SupportMessageContent();
}

final class SupportTextContent extends SupportMessageContent {
  factory SupportTextContent(String text) =>
      SupportTextContent._(_requiredText(text, 'text'));

  const SupportTextContent._(this.text);

  final String text;
}

final class SupportVoucherContent extends SupportMessageContent {
  factory SupportVoucherContent({
    required Voucher voucher,
    required String description,
  }) => SupportVoucherContent._(
    voucher: voucher,
    description: _requiredText(description, 'description'),
  );

  const SupportVoucherContent._({
    required this.voucher,
    required this.description,
  });

  final Voucher voucher;
  final String description;
}

final class SupportMessage {
  factory SupportMessage({
    required String id,
    required SupportParticipant participant,
    required SupportMessageContent content,
  }) => SupportMessage._(
    id: _requiredText(id, 'id'),
    participant: participant,
    content: content,
  );

  const SupportMessage._({
    required this.id,
    required this.participant,
    required this.content,
  });

  final String id;
  final SupportParticipant participant;
  final SupportMessageContent content;
}

final class SuggestedQuestion {
  factory SuggestedQuestion({required String id, required String label}) =>
      SuggestedQuestion._(
        id: _requiredText(id, 'id'),
        label: _requiredText(label, 'label'),
      );

  const SuggestedQuestion._({required this.id, required this.label});

  final String id;
  final String label;
}

final class ServiceRating {
  factory ServiceRating({required int score}) {
    if (score < 1 || score > 5) {
      throw ArgumentError.value(score, 'score', 'Rating must be from 1 to 5.');
    }
    return ServiceRating._(score);
  }

  const ServiceRating._(this.score);

  final int score;
}

final class SupportConversation {
  factory SupportConversation({
    required String id,
    required SupportConversationStage stage,
    required List<SuggestedQuestion> suggestedQuestions,
    required List<SupportMessage> messages,
    ServiceRating? rating,
  }) {
    _requireUniqueIds(
      suggestedQuestions.map((question) => question.id),
      'suggestedQuestions',
    );
    _requireUniqueIds(messages.map((message) => message.id), 'messages');
    if (stage == SupportConversationStage.rated && rating == null) {
      throw ArgumentError('A rated conversation requires a rating.');
    }
    if (stage != SupportConversationStage.rated && rating != null) {
      throw ArgumentError('Only a rated conversation may contain a rating.');
    }
    return SupportConversation._(
      id: _requiredText(id, 'id'),
      stage: stage,
      suggestedQuestions: List<SuggestedQuestion>.unmodifiable(
        suggestedQuestions,
      ),
      messages: List<SupportMessage>.unmodifiable(messages),
      rating: rating,
    );
  }

  const SupportConversation._({
    required this.id,
    required this.stage,
    required this.suggestedQuestions,
    required this.messages,
    required this.rating,
  });

  final String id;
  final SupportConversationStage stage;
  final List<SuggestedQuestion> suggestedQuestions;
  final List<SupportMessage> messages;
  final ServiceRating? rating;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}

void _requireUniqueIds(Iterable<String> ids, String name) {
  final unique = <String>{};
  for (final id in ids) {
    if (!unique.add(id)) {
      throw ArgumentError.value(id, name, 'Duplicate ID.');
    }
  }
}
