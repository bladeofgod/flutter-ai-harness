import 'dart:async';

import 'package:app_data/search.dart';
import 'package:app_features/feature_search/controllers/search_controller.dart';
import 'package:app_features/feature_search/media/search_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test_fixtures.dart';

void main() {
  test(
    'normalizes text, exposes results and deduplicates the same submit',
    () async {
      final api = FakeSearchApi();
      final controller = _controller(api: api);
      addTearDown(controller.onClose);
      controller.queryController.text = '  Floral   DRESS ';

      await controller.submit();
      await controller.submit();

      expect(controller.state, SearchViewState.results);
      expect(controller.textResult?.products.single.id, 'product-1');
      expect(api.textQueries, hasLength(1));
      expect(api.textQueries.single.normalizedText, 'floral dress');
    },
  );

  test(
    'keeps empty results successful and maps expected API failures',
    () async {
      var callCount = 0;
      final api = FakeSearchApi(
        textHandler: (query) async {
          callCount += 1;
          if (callCount == 1) {
            return searchTextResult(query, empty: true);
          }
          throw const SearchFailure(SearchFailureCode.unavailable);
        },
      );
      final controller = _controller(api: api);
      addTearDown(controller.onClose);
      controller.queryController.text = 'nothing';

      await controller.submit();
      expect(controller.state, SearchViewState.empty);

      controller.queryController.text = 'retry term';
      await controller.submit();
      expect(controller.state, SearchViewState.error);
      expect(controller.error, SearchUiError.unavailable);
    },
  );

  test('cancel and picker failure preserve the current text result', () async {
    final picker = FakeSearchImagePicker(<SearchImagePickResult>[
      const SearchImagePickCanceled(),
      const SearchImagePickFailed(
        SearchImagePickFailure(SearchImagePickFailureCode.permissionDenied),
      ),
    ]);
    final controller = _controller(picker: picker);
    addTearDown(controller.onClose);
    controller.queryController.text = 'dress';
    await controller.submit();

    await controller.pickImage();
    expect(controller.state, SearchViewState.results);
    expect(controller.imagePickFailure, isNull);

    await controller.pickImage();
    expect(controller.state, SearchViewState.results);
    expect(
      controller.imagePickFailure?.code,
      SearchImagePickFailureCode.permissionDenied,
    );
  });

  test(
    'moves through deterministic recognizing, recognized and results states',
    () async {
      final completer = Completer<SearchImageResult>();
      final api = FakeSearchApi(imageHandler: (_) => completer.future);
      final controller = _controller(
        api: api,
        picker: FakeSearchImagePicker(<SearchImagePickResult>[
          successfulImagePick(),
        ]),
      );
      addTearDown(controller.onClose);

      final pending = controller.pickImage();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, SearchViewState.imageRecognizing);
      expect(controller.selectedImageBytes, <int>[1, 2, 3]);
      expect(api.imageInputs.single.toString(), 'SearchImageInput(<redacted>)');

      completer.complete(searchImageResult());
      await pending;
      expect(controller.state, SearchViewState.imageRecognized);
      expect(controller.imageResult?.recognizedLabel, 'Floral summer dress');

      controller.showImageResults();
      expect(controller.state, SearchViewState.imageResults);
    },
  );

  test(
    'filter draft cancels cleanly and apply reruns an active query',
    () async {
      final api = FakeSearchApi();
      final controller = _controller(api: api);
      addTearDown(controller.onClose);
      controller.queryController.text = 'dress';
      await controller.submit();

      controller.beginFilter();
      controller.selectDraftAudience(CatalogAudience.male);
      controller.cancelFilter();
      expect(controller.appliedFilter.audience, CatalogAudience.all);

      controller.beginFilter();
      controller.selectDraftCategory('category-shoes');
      await controller.applyFilter();
      expect(controller.appliedFilter.categoryId, 'category-shoes');
      expect(api.textQueries, hasLength(2));
      expect(api.textQueries.last.filter.categoryId, 'category-shoes');
    },
  );

  test(
    'image retry reuses selected bytes without reopening the picker',
    () async {
      var imageCallCount = 0;
      final picker = FakeSearchImagePicker(<SearchImagePickResult>[
        successfulImagePick(),
      ]);
      final controller = _controller(
        api: FakeSearchApi(
          imageHandler: (_) async {
            imageCallCount += 1;
            if (imageCallCount == 1) {
              throw const SearchFailure(SearchFailureCode.unavailable);
            }
            return searchImageResult();
          },
        ),
        picker: picker,
      );
      addTearDown(controller.onClose);

      await controller.pickImage();
      expect(controller.state, SearchViewState.error);
      await controller.retry();

      expect(controller.state, SearchViewState.imageRecognized);
      expect(imageCallCount, 2);
      expect(picker.callCount, 1);
    },
  );

  test('propagates programming errors without leaving the flow busy', () async {
    final error = StateError('programming failure');
    final controller = _controller(
      api: FakeSearchApi(textHandler: (_) => Future<SearchResult>.error(error)),
    );
    addTearDown(controller.onClose);
    controller.queryController.text = 'dress';

    await expectLater(controller.submit(), throwsA(same(error)));

    expect(controller.state, SearchViewState.initial);
    expect(controller.error, isNull);
  });

  test('ignores a recognition result delivered after disposal', () async {
    final completer = Completer<SearchImageResult>();
    final controller = _controller(
      api: FakeSearchApi(imageHandler: (_) => completer.future),
      picker: FakeSearchImagePicker(<SearchImagePickResult>[
        successfulImagePick(),
      ]),
    );

    final pending = controller.pickImage();
    await Future<void>.delayed(Duration.zero);
    controller.onClose();
    completer.complete(searchImageResult());
    await pending;

    expect(controller.imageResult, isNull);
    expect(controller.selectedImageBytes, isNull);
  });
}

SearchFlowController _controller({
  FakeSearchApi? api,
  SearchImagePicker? picker,
}) => SearchFlowController(
  searchApi: api ?? FakeSearchApi(),
  imagePicker: picker ?? FakeSearchImagePicker(const <SearchImagePickResult>[]),
);
