/// Marks a value as sensitive and prevents accidental string interpolation.
final class Secret<T> {
  const Secret(T value) : _value = value;

  final T _value;

  /// Explicitly reveals the value at the narrow boundary that consumes it.
  T reveal() => _value;

  @override
  String toString() => 'Secret(<redacted>)';
}
