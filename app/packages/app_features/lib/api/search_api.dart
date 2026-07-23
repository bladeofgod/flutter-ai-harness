import 'package:app_data/search.dart';

/// 文本和图片搜索共用的窄业务边界。
abstract interface class SearchApi {
  Future<SearchResult> searchText(SearchQuery query);

  Future<SearchImageResult> searchImage(SearchImageInput input);
}
