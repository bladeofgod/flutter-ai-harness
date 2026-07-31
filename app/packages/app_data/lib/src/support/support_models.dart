import 'dart:typed_data';

import 'package:app_core/app_core.dart';

import '../checkout/checkout_models.dart';

const int supportMediaMaxPosterBytes = 512 * 1024;
const int supportMediaMaxPosterDimension = 512;

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

enum SupportMediaType { image, video }

final class SupportMediaPoster {
  factory SupportMediaPoster({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    if (bytes.isEmpty ||
        bytes.lengthInBytes > supportMediaMaxPosterBytes ||
        width < 1 ||
        width > supportMediaMaxPosterDimension ||
        height < 1 ||
        height > supportMediaMaxPosterDimension ||
        !_isBoundedSanitizedPng(bytes, width: width, height: height)) {
      throw ArgumentError('Invalid bounded Support media poster.');
    }
    return SupportMediaPoster._(
      bytes: Uint8List.fromList(bytes),
      width: width,
      height: height,
    );
  }

  const SupportMediaPoster._({
    required Uint8List bytes,
    required this.width,
    required this.height,
  }) : _bytes = bytes;

  final Uint8List _bytes;
  final int width;
  final int height;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'SupportMediaPoster(<redacted>)';
}

final class SupportMediaContent extends SupportMessageContent {
  factory SupportMediaContent({
    required MediaResourceId resourceId,
    required SupportMediaType type,
    required String label,
    SupportMediaPoster? poster,
    Duration? duration,
  }) {
    final normalizedLabel = _requiredText(label, 'label');
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
    return SupportMediaContent._(
      resourceId: resourceId,
      type: type,
      label: normalizedLabel,
      poster: poster,
      duration: duration,
    );
  }

  const SupportMediaContent._({
    required this.resourceId,
    required this.type,
    required this.label,
    required this.poster,
    required this.duration,
  });

  final MediaResourceId resourceId;
  final SupportMediaType type;
  final String label;
  final SupportMediaPoster? poster;
  final Duration? duration;

  @override
  String toString() =>
      'SupportMediaContent(type: ${type.name}, resource: <redacted>, '
      'metadata: <redacted>)';
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

bool _isBoundedSanitizedPng(
  Uint8List bytes, {
  required int width,
  required int height,
}) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) {
    return false;
  }
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }
  var offset = signature.length;
  var sawHeader = false;
  var sawPalette = false;
  var sawImageData = false;
  var imageDataEnded = false;
  while (offset + 12 <= bytes.length) {
    final length = _readUint32(bytes, offset);
    final chunkEnd = offset + 12 + length;
    if (chunkEnd > bytes.length) {
      return false;
    }
    final typeOffset = offset + 4;
    final dataOffset = offset + 8;
    final storedCrc = _readUint32(bytes, dataOffset + length);
    if (_crc32(bytes, typeOffset, dataOffset + length) != storedCrc) {
      return false;
    }
    final isHeader = _matchesChunk(bytes, typeOffset, 73, 72, 68, 82);
    final isPalette = _matchesChunk(bytes, typeOffset, 80, 76, 84, 69);
    final isImageData = _matchesChunk(bytes, typeOffset, 73, 68, 65, 84);
    final isEnd = _matchesChunk(bytes, typeOffset, 73, 69, 78, 68);
    if (isHeader) {
      if (sawHeader || offset != signature.length || length != 13) {
        return false;
      }
      if (_readUint32(bytes, dataOffset) != width ||
          _readUint32(bytes, dataOffset + 4) != height) {
        return false;
      }
      sawHeader = true;
    } else if (isPalette) {
      if (!sawHeader || sawPalette || sawImageData || length == 0) {
        return false;
      }
      sawPalette = true;
    } else if (isImageData) {
      if (!sawHeader || imageDataEnded || length == 0) {
        return false;
      }
      sawImageData = true;
    } else if (isEnd) {
      return sawHeader &&
          sawImageData &&
          length == 0 &&
          chunkEnd == bytes.length;
    } else {
      return false;
    }
    if (sawImageData && !isImageData) {
      imageDataEnded = true;
    }
    offset = chunkEnd;
  }
  return false;
}

bool _matchesChunk(
  Uint8List bytes,
  int offset,
  int first,
  int second,
  int third,
  int fourth,
) {
  return bytes[offset] == first &&
      bytes[offset + 1] == second &&
      bytes[offset + 2] == third &&
      bytes[offset + 3] == fourth;
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index += 1) {
    crc ^= bytes[index];
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
