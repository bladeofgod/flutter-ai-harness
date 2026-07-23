import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('dispatches requests to the owning handler', () async {
    final transport = FixtureApiTransport(
      handlers: <FixtureRequestHandler>[
        const _ValueHandler('feature.a', 42),
        const _ValueHandler('feature.b', 'ok'),
      ],
    );

    final response = await transport.send(const ApiRequest(key: 'feature.b'));

    expect(response, isA<ApiSuccess<Object?>>());
    expect((response as ApiSuccess<Object?>).payload, 'ok');
  });

  test('rejects duplicate request keys during composition', () {
    expect(
      () => FixtureApiTransport(
        handlers: const <FixtureRequestHandler>[
          _ValueHandler('duplicate.key', 1),
          _ValueHandler('duplicate.key', 2),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('unknown requests keep the transport boundary explicit', () async {
    final client = ApiClient(
      transport: FixtureApiTransport(handlers: const <FixtureRequestHandler>[]),
    );

    final response = await client.send<Object?>(
      const ApiRequest(key: 'missing.key'),
    );

    expect(response, isA<ApiError<Object?>>());
    final failure = (response as ApiError<Object?>).failure;
    expect(failure.kind, ApiFailureKind.unknownRequest);
    expect(failure.code, 'unknown_request');
  });
}

final class _ValueHandler implements FixtureRequestHandler {
  const _ValueHandler(this.key, this.value);

  final String key;
  final Object? value;

  @override
  Set<String> get requestKeys => <String>{key};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      ApiResponse<Object?>.success(value);
}
