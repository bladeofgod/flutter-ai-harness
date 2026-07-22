import 'package:app_core/app_core.dart';
import 'package:test/test.dart';

void main() {
  group('ApiClient', () {
    test('delegates the request and returns a typed success', () async {
      const request = ApiRequest(key: 'auth.login', payload: 'request-data');
      final transport = _RecordingTransport(
        response: const ApiResponse<Object?>.success('response-data'),
      );
      final client = ApiClient(transport: transport);

      final response = await client.send<String>(request);

      expect(transport.lastRequest, same(request));
      expect(response, isA<ApiSuccess<String>>());
      expect((response as ApiSuccess<String>).payload, 'response-data');
    });

    test('passes through a transport failure response', () async {
      const failure = ApiFailure.rejected(
        code: 'request_rejected',
        message: 'Public explanation',
      );
      final client = ApiClient(
        transport: _RecordingTransport(
          response: const ApiResponse<Object?>.failure(failure),
        ),
      );

      final response = await client.send<String>(
        const ApiRequest(key: 'auth.login'),
      );

      expect(response, isA<ApiError<String>>());
      expect((response as ApiError<String>).failure, same(failure));
    });

    test('normalizes an unknown request exception', () async {
      final client = ApiClient(transport: _ThrowingTransport.unknown());

      final response = await client.send<String>(
        const ApiRequest(key: 'missing.operation'),
      );

      final failure = (response as ApiError<String>).failure;
      expect(failure.kind, ApiFailureKind.unknownRequest);
      expect(failure.code, 'unknown_request');
      expect(failure.stackTrace, isNotNull);
    });

    test('normalizes an explicitly wrapped transport exception', () async {
      final client = ApiClient(
        transport: _ThrowingTransport.error(
          const ApiTransportException(cause: 'offline'),
        ),
      );

      final response = await client.send<String>(
        const ApiRequest(key: 'auth.login'),
      );

      final failure = (response as ApiError<String>).failure;
      expect(failure.kind, ApiFailureKind.transport);
      expect(failure.code, 'transport_error');
      expect(failure.stackTrace, isNotNull);
    });

    test('does not hide unexpected programming exceptions', () async {
      final client = ApiClient(
        transport: _ThrowingTransport.error(StateError('programming error')),
      );

      await expectLater(
        client.send<String>(const ApiRequest(key: 'auth.login')),
        throwsStateError,
      );
    });

    test('rejects a response payload with the wrong generic type', () async {
      final client = ApiClient(
        transport: _RecordingTransport(
          response: const ApiResponse<Object?>.success(42),
        ),
      );

      final response = await client.send<String>(
        const ApiRequest(key: 'auth.login'),
      );

      final failure = (response as ApiError<String>).failure;
      expect(failure.kind, ApiFailureKind.invalidResponse);
      expect(failure.code, 'invalid_response');
    });
  });

  group('sensitive diagnostics', () {
    const rawSecret = 'never-print-this-password';
    const secret = Secret<String>(rawSecret);

    test('Secret requires explicit reveal and redacts toString', () {
      expect(secret.reveal(), rawSecret);
      expect(secret.toString(), 'Secret(<redacted>)');
      expect(secret.toString(), isNot(contains(rawSecret)));
    });

    test('ApiRequest never expands its payload', () {
      const request = ApiRequest(key: 'auth.login', payload: secret);

      expect(request.toString(), contains('auth.login'));
      expect(request.toString(), contains('<redacted>'));
      expect(request.toString(), isNot(contains(rawSecret)));
    });

    test('ApiFailure never expands its message', () {
      const failure = ApiFailure.rejected(
        code: 'login_rejected',
        message: rawSecret,
      );

      expect(failure.toString(), contains('login_rejected'));
      expect(failure.toString(), contains('<redacted>'));
      expect(failure.toString(), isNot(contains(rawSecret)));
    });

    test('ApiResponse never expands a success payload', () {
      const response = ApiResponse<Secret<String>>.success(secret);

      expect(response.toString(), contains('<redacted>'));
      expect(response.toString(), isNot(contains(rawSecret)));
    });

    test('transport exceptions never expand request keys or causes', () {
      const unknown = UnknownApiRequestException(rawSecret);
      const transport = ApiTransportException(cause: secret);

      expect(unknown.toString(), isNot(contains(rawSecret)));
      expect(transport.toString(), isNot(contains(rawSecret)));
      expect(unknown.toString(), contains('<redacted>'));
      expect(transport.toString(), contains('<redacted>'));
    });

    test('normalized failures do not retain exception messages', () async {
      final client = ApiClient(
        transport: _ThrowingTransport.error(
          const ApiTransportException(cause: rawSecret),
        ),
      );

      final response = await client.send<String>(
        const ApiRequest(key: 'auth.login', payload: secret),
      );

      expect(response.toString(), isNot(contains(rawSecret)));
      expect(
        (response as ApiError<String>).failure.toString(),
        isNot(contains(rawSecret)),
      );
    });
  });
}

final class _RecordingTransport implements ApiTransport {
  _RecordingTransport({required this.response});

  final ApiResponse<Object?> response;
  ApiRequest? lastRequest;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    lastRequest = request;
    return response;
  }
}

final class _ThrowingTransport implements ApiTransport {
  const _ThrowingTransport._(this.error);

  factory _ThrowingTransport.unknown() {
    return const _ThrowingTransport._(
      UnknownApiRequestException('missing.operation'),
    );
  }

  factory _ThrowingTransport.error(Object error) {
    return _ThrowingTransport._(error);
  }

  final Object error;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    throw error;
  }
}
