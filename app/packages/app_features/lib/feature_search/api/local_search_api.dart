import 'package:app_data/search.dart';

import '../../api/search_api.dart';

final class LocalSearchApi implements SearchApi {
  const LocalSearchApi({required SearchLocalDataSource dataSource})
    : _dataSource = dataSource;

  final SearchLocalDataSource _dataSource;

  @override
  Future<SearchResult> searchText(SearchQuery query) =>
      _dataSource.searchText(query);

  @override
  Future<SearchImageResult> searchImage(SearchImageInput input) =>
      _dataSource.searchImage(input);
}
