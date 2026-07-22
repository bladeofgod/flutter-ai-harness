import 'api_failure.dart';
import 'api_request.dart';
import 'api_response.dart';
import 'api_transport.dart';
import 'api_transport_exception.dart';

/// Delegates requests and normalizes transport outcomes.
final class ApiClient {
  const ApiClient({required ApiTransport transport}) : _transport = transport;

  final ApiTransport _transport;

  Future<ApiResponse<T>> send<T>(ApiRequest request) async {
    try {
      final response = await _transport.send(request);

      return switch (response) {
        ApiSuccess<Object?>(:final payload) => _validatePayload<T>(payload),
        ApiError<Object?>(:final failure) => ApiResponse<T>.failure(failure),
      };
    } on UnknownApiRequestException catch (_, stackTrace) {
      return ApiResponse<T>.failure(
        ApiFailure.unknownRequest(stackTrace: stackTrace),
      );
    } on ApiTransportException catch (_, stackTrace) {
      return ApiResponse<T>.failure(
        ApiFailure.transport(stackTrace: stackTrace),
      );
    }
  }

  ApiResponse<T> _validatePayload<T>(Object? payload) {
    if (payload is T) {
      return ApiResponse<T>.success(payload);
    }

    return ApiResponse<T>.failure(const ApiFailure.invalidResponse());
  }
}
