import 'dart:convert';
import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:app_features/api/search_api.dart';
import 'package:app_features/api/search_image_picker.dart';

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
  FakeSearchImagePicker(
    List<SearchImagePickResult> galleryResults, {
    List<SearchImagePickResult> cameraResults = const <SearchImagePickResult>[],
  }) : _galleryResults = List<SearchImagePickResult>.of(galleryResults),
       _cameraResults = List<SearchImagePickResult>.of(cameraResults);

  final List<SearchImagePickResult> _galleryResults;
  final List<SearchImagePickResult> _cameraResults;
  var callCount = 0;
  var cameraCallCount = 0;
  var clearCount = 0;
  var disposeCount = 0;

  @override
  Future<SearchImagePickResult> pickFromGallery() async {
    callCount += 1;
    return _galleryResults.removeAt(0);
  }

  @override
  Future<SearchImagePickResult> capturePhoto() async {
    cameraCallCount += 1;
    return _cameraResults.removeAt(0);
  }

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

SearchImagePickSuccess successfulImagePick() =>
    SearchImagePickSuccess(Uint8List.fromList(<int>[1, 2, 3]));

const String _onePixelJpegBase64 =
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////'
    '////////////////////////////////////////////////////////2wBDAf//'
    '////////////////////////////////////////////////////////////////////'
    '////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA'
    'AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB'
    'AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA'
    'AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA'
    'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA'
    'AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//'
    'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';

Uint8List validSearchJpeg() => base64Decode(_onePixelJpegBase64);
