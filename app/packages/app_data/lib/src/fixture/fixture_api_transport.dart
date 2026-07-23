import 'package:app_core/app_core.dart';

/// Fixture 请求处理器。每个 Feature 只声明并处理自己拥有的请求键。
abstract interface class FixtureRequestHandler {
  Set<String> get requestKeys;

  Future<ApiResponse<Object?>> handle(ApiRequest request);
}

/// 将请求分发给组合注入的 Feature Fixture Handler。
final class FixtureApiTransport implements ApiTransport {
  FixtureApiTransport({required Iterable<FixtureRequestHandler> handlers})
    : _handlersByKey = _indexHandlers(handlers);

  final Map<String, FixtureRequestHandler> _handlersByKey;

  static Map<String, FixtureRequestHandler> _indexHandlers(
    Iterable<FixtureRequestHandler> handlers,
  ) {
    final indexed = <String, FixtureRequestHandler>{};
    for (final handler in handlers) {
      for (final key in handler.requestKeys) {
        if (key.trim().isEmpty) {
          throw ArgumentError.value(key, 'handlers', 'Request key is empty.');
        }
        if (indexed.containsKey(key)) {
          throw ArgumentError.value(
            key,
            'handlers',
            'Duplicate Fixture request key.',
          );
        }
        indexed[key] = handler;
      }
    }
    return Map<String, FixtureRequestHandler>.unmodifiable(indexed);
  }

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) {
    final handler = _handlersByKey[request.key];
    if (handler == null) {
      throw UnknownApiRequestException(request.key);
    }
    return handler.handle(request);
  }

  @override
  String toString() =>
      'FixtureApiTransport(handlers: ${_handlersByKey.length}, payloads: <redacted>)';
}
