import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:app_features/feature_search/controllers/search_controller.dart';
import 'package:app_features/feature_search/media/search_image_picker.dart';
import 'package:app_features/feature_search/pages/search_page.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test_fixtures.dart';

void main() {
  testWidgets('renders search, submits text and opens a product by stable ID', (
    tester,
  ) async {
    String? selectedProductId;
    final api = FakeSearchApi();
    await _setViewport(tester, const Size(375, 812));
    await _pumpSearch(
      tester,
      api: api,
      onProductSelected: (value) => selectedProductId = value,
    );

    expect(find.byKey(const ValueKey('search-initial')), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('search-input')),
      'Floral dress',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('search-results-scroll')), findsOneWidget);
    expect(find.text('Floral summer dress'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('search-product-product-1')));
    expect(selectedProductId, 'product-1');
    expect(api.textQueries.single.normalizedText, 'floral dress');
  });

  testWidgets('filter cancel is isolated and Apply reruns the current query', (
    tester,
  ) async {
    final api = FakeSearchApi();
    await _setViewport(tester, const Size(375, 812));
    await _pumpSearch(tester, api: api);
    await tester.enterText(find.byKey(const ValueKey('search-input')), 'dress');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-filter-sheet')), findsOneWidget);
    await tester.tap(find.text('Men'));
    await tester.tap(find.byKey(const ValueKey('search-filter-cancel')));
    await tester.pumpAndSettle();
    expect(api.textQueries, hasLength(1));
    expect(api.textQueries.single.filter.audience, CatalogAudience.all);

    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('search-filter-category-shoes')),
    );
    await tester.tap(find.byKey(const ValueKey('search-filter-apply')));
    await tester.pumpAndSettle();

    expect(api.textQueries, hasLength(2));
    expect(api.textQueries.last.filter.categoryId, 'category-shoes');
  });

  testWidgets('shows recognizing, recognized and deterministic result states', (
    tester,
  ) async {
    final completer = Completer<SearchImageResult>();
    final api = FakeSearchApi(imageHandler: (_) => completer.future);
    final picker = FakeSearchImagePicker(<SearchImagePickResult>[
      SearchImagePickSuccess(_onePixelPng()),
    ]);
    await _setViewport(tester, const Size(375, 812));
    await _pumpSearch(tester, api: api, picker: picker);

    await tester.tap(find.byKey(const ValueKey('search-image-entry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-recognizing')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('search-image-preview'))),
      const Size(210, 240),
    );

    completer.complete(searchImageResult());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('search-recognized')), findsOneWidget);
    expect(find.text('Image recognized'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-show-image-results')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-results-scroll')), findsOneWidget);
    expect(find.text('Demo visual match'), findsOneWidget);
  });

  testWidgets('picker cancel stays on the current page and failure is stable', (
    tester,
  ) async {
    final picker = FakeSearchImagePicker(<SearchImagePickResult>[
      const SearchImagePickCanceled(),
      const SearchImagePickFailed(
        SearchImagePickFailure(SearchImagePickFailureCode.tooLarge),
      ),
    ]);
    await _setViewport(tester, const Size(375, 812));
    await _pumpSearch(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('search-image-entry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-initial')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-image-entry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('search-image-error')), findsOneWidget);
    expect(find.text('Choose a photo smaller than 2 MB.'), findsOneWidget);
  });

  testWidgets('renders empty and retryable API error states', (tester) async {
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
    await _setViewport(tester, const Size(375, 812));
    await _pumpSearch(tester, api: api);

    await tester.enterText(find.byKey(const ValueKey('search-input')), 'none');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('search-input')), 'error');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('search-error')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('handles compact, landscape, scaled text and keyboard insets', (
    tester,
  ) async {
    const cases = <({Size size, double textScale})>[
      (size: Size(320, 568), textScale: 1),
      (size: Size(812, 375), textScale: 1),
      (size: Size(375, 812), textScale: 1.3),
    ];
    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpSearch(tester, textScale: testCase.textScale);
      await tester.tap(find.byKey(const ValueKey('search-input')));
      await tester.showKeyboard(find.byKey(const ValueKey('search-input')));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${testCase.size}');

      await tester.enterText(
        find.byKey(const ValueKey('search-input')),
        'dress',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      tester.testTextInput.hide();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('search-results-scroll')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '${testCase.size} result');
    }
  });
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  FakeSearchApi? api,
  SearchImagePicker? picker,
  ValueChanged<String>? onProductSelected,
  double textScale = 1,
}) async {
  final controller = SearchFlowController(
    searchApi: api ?? FakeSearchApi(),
    imagePicker:
        picker ?? FakeSearchImagePicker(const <SearchImagePickResult>[]),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: SearchPage(
        controller: controller,
        onProductSelected: onProductSelected ?? (_) {},
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);
