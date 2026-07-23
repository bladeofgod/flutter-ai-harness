part of 'support_local.dart';

abstract final class _SupportFixtureMapper {
  static SupportConversation conversation(Object? payload) => _decode(() {
    final values = _map(payload, 'conversation');
    final rating = values['rating'];
    return SupportConversation(
      id: _string(values, 'id'),
      stage: _stage(_string(values, 'stage')),
      suggestedQuestions: _list(values, 'suggestedQuestions', _question),
      messages: _list(values, 'messages', _message),
      rating: rating == null ? null : ServiceRating(score: _intValue(rating)),
    );
  });

  static SuggestedQuestion _question(Object? payload) {
    final values = _map(payload, 'question');
    return SuggestedQuestion(
      id: _string(values, 'id'),
      label: _string(values, 'label'),
    );
  }

  static SupportMessage _message(Object? payload) {
    final values = _map(payload, 'message');
    final content = _map(values['content'], 'message.content');
    return SupportMessage(
      id: _string(values, 'id'),
      participant: switch (_string(values, 'participant')) {
        'customer' => SupportParticipant.customer,
        'supportAgent' => SupportParticipant.supportAgent,
        'system' => SupportParticipant.system,
        final value => throw FormatException('Unknown participant: $value'),
      },
      content: switch (_string(content, 'type')) {
        'text' => SupportTextContent(_string(content, 'text')),
        'voucher' => SupportVoucherContent(
          description: _string(content, 'description'),
          voucher: _voucher(content['voucher']),
        ),
        final value => throw FormatException('Unknown content type: $value'),
      },
    );
  }

  static Voucher _voucher(Object? payload) {
    final values = _map(payload, 'voucher');
    final currency = Currency.fromCode(_string(values, 'currency'));
    return Voucher(
      id: _string(values, 'id'),
      code: _string(values, 'code'),
      title: _string(values, 'title'),
      discount: Money(
        currency: currency,
        minorUnits: _int(values, 'discountMinorUnits'),
      ),
      minimumSpend: Money(
        currency: currency,
        minorUnits: _int(values, 'minimumSpendMinorUnits'),
      ),
    );
  }

  static SupportConversationStage _stage(String value) => switch (value) {
    'starting' => SupportConversationStage.starting,
    'connecting' => SupportConversationStage.connecting,
    'typing' => SupportConversationStage.typing,
    'active' => SupportConversationStage.active,
    'rating' => SupportConversationStage.rating,
    'rated' => SupportConversationStage.rated,
    _ => throw FormatException('Unknown Support stage: $value'),
  };

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on SupportFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const SupportFailure(SupportFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _map(Object? payload, String name) {
    if (payload is! Map<String, Object?>) {
      throw FormatException('$name must be a map.');
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String) {
      throw FormatException('$key must be a string.');
    }
    return value;
  }

  static int _int(Map<String, Object?> values, String key) =>
      _intValue(values[key]);

  static int _intValue(Object? value) {
    if (value is! int) {
      throw FormatException('Value must be an integer.');
    }
    return value;
  }

  static List<T> _list<T>(
    Map<String, Object?> values,
    String key,
    T Function(Object? value) map,
  ) {
    final value = values[key];
    if (value is! List<Object?>) {
      throw FormatException('$key must be a list.');
    }
    return value.map(map).toList(growable: false);
  }
}
