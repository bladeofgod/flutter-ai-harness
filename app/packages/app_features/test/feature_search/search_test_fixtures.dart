import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:app_features/api/search_api.dart';
import 'package:app_features/feature_search/media/search_image_picker.dart';

CatalogFilter searchTestFilter({
  CatalogAudience audience = CatalogAudience.all,
  String categoryId = 'category-clothing',
}) => CatalogFilter(audience: audience, categoryId: categoryId);

ProductSummary searchTestProduct({
  String id = 'product-1',
  String title = 'Floral summer dress',
}) => ProductSummary(
  id: id,
  title: title,
  imageAssetKey: 'assets/images/profile/product_01.png',
);

SearchResult searchTextResult(SearchQuery query, {bool empty = false}) =>
    SearchResult(
      query: query,
      products: empty
          ? const <ProductSummary>[]
          : <ProductSummary>[searchTestProduct()],
    );

SearchImageResult searchImageResult() => SearchImageResult(
  recognizedLabel: 'Floral summer dress',
  products: <ProductSummary>[searchTestProduct()],
);

final class FakeSearchApi implements SearchApi {
  FakeSearchApi({this.textHandler, this.imageHandler});

  final Future<SearchResult> Function(SearchQuery query)? textHandler;
  final Future<SearchImageResult> Function(SearchImageInput input)?
  imageHandler;
  final List<SearchQuery> textQueries = <SearchQuery>[];
  final List<SearchImageInput> imageInputs = <SearchImageInput>[];

  @override
  Future<SearchResult> searchText(SearchQuery query) {
    textQueries.add(query);
    return textHandler?.call(query) ?? Future.value(searchTextResult(query));
  }

  @override
  Future<SearchImageResult> searchImage(SearchImageInput input) {
    imageInputs.add(input);
    return imageHandler?.call(input) ?? Future.value(searchImageResult());
  }
}

final class FakeSearchImagePicker implements SearchImagePicker {
  FakeSearchImagePicker(List<SearchImagePickResult> results)
    : _results = List<SearchImagePickResult>.of(results);

  final List<SearchImagePickResult> _results;
  var callCount = 0;

  @override
  Future<SearchImagePickResult> pickFromGallery() async {
    callCount += 1;
    return _results.removeAt(0);
  }
}

SearchImagePickSuccess successfulImagePick() =>
    SearchImagePickSuccess(Uint8List.fromList(<int>[1, 2, 3]));
