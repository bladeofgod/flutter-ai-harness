import 'dart:async';

import 'package:app_features/feature_search/media/search_image_picker.dart';
import 'package:app_features/feature_search/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'search_test_fixtures.dart';

void main() {
  testWidgets('keeps Search in one route and delegates Product navigation', (
    tester,
  ) async {
    String? selectedProductId;
    final router = GoRouter(
      initialLocation: searchRoutePath,
      routes:
          buildSearchRoutes(
            searchApi: FakeSearchApi(),
            imagePicker: FakeSearchImagePicker(const <SearchImagePickResult>[]),
            openProduct: (context, productId) {
              selectedProductId = productId;
              unawaited(context.push<void>('/captured'));
            },
          )..add(
            GoRoute(
              path: '/captured',
              builder: (context, state) =>
                  const Scaffold(body: Text('Captured')),
            ),
          ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('search-input')), 'dress');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-product-product-1')));
    await tester.pumpAndSettle();

    expect(selectedProductId, 'product-1');
    expect(find.text('Captured'), findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      searchRoutePath,
    );
  });

  testWidgets('system Back closes Filter without changing the Search route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: searchRoutePath,
      routes: buildSearchRoutes(
        searchApi: FakeSearchApi(),
        imagePicker: FakeSearchImagePicker(const <SearchImagePickResult>[]),
        openProduct: (_, _) {},
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-filter-sheet')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-filter-sheet')), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      searchRoutePath,
    );
  });
}
