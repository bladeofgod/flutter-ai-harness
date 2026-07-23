enum SearchFailureCode {
  unavailable,
  invalidQuery,
  invalidResponse,
  transportUnavailable,
  unknownRequest,
}

final class SearchFailure implements Exception {
  const SearchFailure(this.code);

  final SearchFailureCode code;

  @override
  String toString() => 'SearchFailure(${code.name})';
}
