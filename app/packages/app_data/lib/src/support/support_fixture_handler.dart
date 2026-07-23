import 'package:app_core/app_core.dart';

import '../fixture/fixture_api_transport.dart';
import '../fixture/shoppe_voucher_fixture.dart';

/// Support Chat 请求键与进程内脚本进度的唯一所有者。
final class SupportFixtureHandler implements FixtureRequestHandler {
  static const String startConversationKey = 'support.conversation.start';
  static const String selectQuestionKey = 'support.question.select';
  static const String advanceTransitionKey = 'support.transition.advance';
  static const String sendMessageKey = 'support.message.send';
  static const String receiveReplyKey = 'support.reply.receive';
  static const String requestRatingKey = 'support.rating.request';
  static const String submitRatingKey = 'support.rating.submit';

  String _stage = 'starting';
  int _messageSequence = 0;
  int _replySequence = 0;
  int? _rating;
  final List<Map<String, Object?>> _messages = <Map<String, Object?>>[];

  void resetSession() => _messages.clear();

  @override
  Set<String> get requestKeys => const <String>{
    startConversationKey,
    selectQuestionKey,
    advanceTransitionKey,
    sendMessageKey,
    receiveReplyKey,
    requestRatingKey,
    submitRatingKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        startConversationKey => _start(),
        selectQuestionKey => _selectQuestion(request.payload),
        advanceTransitionKey => _advanceTransition(),
        sendMessageKey => _sendMessage(request.payload),
        receiveReplyKey => _receiveReply(),
        requestRatingKey => _requestRating(),
        submitRatingKey => _submitRating(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _start() {
    _stage = 'starting';
    _messageSequence = 0;
    _replySequence = 0;
    _rating = null;
    _messages.clear();
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _selectQuestion(Object? payload) {
    if (_stage != 'starting') {
      return _invalidState();
    }
    final questionId = payload is Map<String, Object?>
        ? payload['questionId']
        : null;
    final selected = _questions.where(
      (question) => question['id'] == questionId,
    );
    if (selected.isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'support.question_not_found'),
      );
    }
    _messages.add(
      _textMessage(participant: 'customer', text: selected.single['label']!),
    );
    _stage = 'connecting';
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _advanceTransition() {
    switch (_stage) {
      case 'connecting':
        _stage = 'typing';
      case 'typing' when _replySequence == 0:
        _messages.add(
          _textMessage(
            participant: 'supportAgent',
            text: 'Hello! I am Alex from Shoppe Support. How can I help?',
          ),
        );
        _replySequence = 1;
        _stage = 'active';
      default:
        return _invalidState();
    }
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _sendMessage(Object? payload) {
    if (_stage != 'active') {
      return _invalidState();
    }
    final text = payload is Map<String, Object?> ? payload['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'support.invalid_state'),
      );
    }
    _messages.add(_textMessage(participant: 'customer', text: text.trim()));
    _stage = 'typing';
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _receiveReply() {
    if (_stage != 'typing' || _replySequence == 0) {
      return _invalidState();
    }
    if (_replySequence == 1) {
      _messages
        ..add(
          _textMessage(
            participant: 'supportAgent',
            text:
                'Thanks for the details. This Demo conversation uses a fixed local response.',
          ),
        )
        ..add(_voucherMessage());
    } else {
      _messages.add(
        _textMessage(
          participant: 'supportAgent',
          text: 'I have added that note to this local Demo conversation.',
        ),
      );
    }
    _replySequence += 1;
    _stage = 'active';
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _requestRating() {
    if (_stage != 'active') {
      return _invalidState();
    }
    _stage = 'rating';
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _submitRating(Object? payload) {
    if (_stage != 'rating') {
      return _invalidState();
    }
    final score = payload is Map<String, Object?> ? payload['score'] : null;
    if (score is! int || score < 1 || score > 5) {
      return _invalidState();
    }
    _rating = score;
    _stage = 'rated';
    return ApiResponse<Object?>.success(_conversationPayload());
  }

  ApiResponse<Object?> _invalidState() => const ApiResponse<Object?>.failure(
    ApiFailure.rejected(code: 'support.invalid_state'),
  );

  Map<String, Object?> _conversationPayload() => <String, Object?>{
    'id': 'support-demo-session',
    'stage': _stage,
    'suggestedQuestions': _questions
        .map((question) => Map<String, Object?>.from(question))
        .toList(growable: false),
    'messages': _messages
        .map((message) => Map<String, Object?>.from(message))
        .toList(growable: false),
    'rating': _rating,
  };

  Map<String, Object?> _textMessage({
    required String participant,
    required Object text,
  }) => <String, Object?>{
    'id': 'support-message-${_messageSequence++}',
    'participant': participant,
    'content': <String, Object?>{'type': 'text', 'text': text},
  };

  Map<String, Object?> _voucherMessage() => <String, Object?>{
    'id': 'support-message-${_messageSequence++}',
    'participant': 'supportAgent',
    'content': <String, Object?>{
      'type': 'voucher',
      'description': 'A Demo voucher you can view in your local voucher list.',
      'voucher': <String, Object?>{
        'id': shoppeFiveVoucherFixture.id,
        'code': shoppeFiveVoucherFixture.code,
        'title': shoppeFiveVoucherFixture.title,
        'discountMinorUnits': shoppeFiveVoucherFixture.discount.minorUnits,
        'minimumSpendMinorUnits':
            shoppeFiveVoucherFixture.minimumSpend.minorUnits,
        'currency': shoppeFiveVoucherFixture.discount.currency.code,
      },
    },
  };
}

const List<Map<String, Object?>> _questions = <Map<String, Object?>>[
  <String, Object?>{'id': 'order-status', 'label': 'Where is my order?'},
  <String, Object?>{'id': 'return-item', 'label': 'How can I return an item?'},
  <String, Object?>{
    'id': 'payment-question',
    'label': 'I have a payment question',
  },
];
