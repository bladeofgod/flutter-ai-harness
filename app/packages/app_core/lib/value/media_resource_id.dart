/// Opaque identifier for an app-owned media resource.
final class MediaResourceId {
  factory MediaResourceId(String value) {
    if (!_pattern.hasMatch(value)) {
      throw const FormatException('Invalid MediaResourceId');
    }
    return MediaResourceId._(value);
  }

  const MediaResourceId._(this.value);

  static final RegExp _pattern = RegExp(r'^mr_[0-9a-f]{32}$');

  /// The validated transport-neutral representation.
  final String value;

  static MediaResourceId? tryParse(String value) {
    if (!_pattern.hasMatch(value)) {
      return null;
    }
    return MediaResourceId._(value);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaResourceId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MediaResourceId(<redacted>)';
}
