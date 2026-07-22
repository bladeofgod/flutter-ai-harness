import 'api_request.dart';
import 'api_response.dart';

/// Executes an [ApiRequest] without imposing a concrete transport protocol.
abstract interface class ApiTransport {
  Future<ApiResponse<Object?>> send(ApiRequest request);
}
