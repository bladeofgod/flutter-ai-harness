import 'api_failure.dart';

/// A transport-neutral success or failure result.
sealed class ApiResponse<T> {
  const ApiResponse();

  const factory ApiResponse.success(T payload) = ApiSuccess<T>;

  const factory ApiResponse.failure(ApiFailure failure) = ApiError<T>;
}

final class ApiSuccess<T> extends ApiResponse<T> {
  const ApiSuccess(this.payload);

  final T payload;

  @override
  String toString() => 'ApiSuccess<$T>(payload: <redacted>)';
}

final class ApiError<T> extends ApiResponse<T> {
  const ApiError(this.failure);

  final ApiFailure failure;

  @override
  String toString() => 'ApiError<$T>($failure)';
}
