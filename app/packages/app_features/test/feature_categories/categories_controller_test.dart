import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_categories/controllers/categories_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'categories_test_fixtures.dart';

void main() {
  test('loads initial Clothing results and applies a subcategory', () async {
    final api = FakeCatalogBrowseApi(
      (query, _) async => categoriesTestResult(query),
    );
    final controller = CategoriesController(catalogApi: api);
    addTearDown(controller.onClose);

    controller.onInit();
    await _waitForState<CategoriesData>(controller);
    expect(controller.appliedFilter.categoryId, 'category-clothing');
    expect(api.loadCount, 1);

    await controller.selectSubcategory('subcategory-1');

    expect(controller.appliedFilter.subcategoryId, 'subcategory-1');
    expect(api.loadCount, 2);
  });

  test('applies and resets typed filter conditions', () async {
    final api = FakeCatalogBrowseApi(
      (query, _) async => categoriesTestResult(query),
    );
    final controller = CategoriesController(catalogApi: api);
    addTearDown(controller.onClose);
    controller.onInit();
    await _waitForState<CategoriesData>(controller);

    await controller.applyFilter(
      CatalogFilter(
        audience: CatalogAudience.male,
        categoryId: 'category-shoes',
      ),
    );
    expect(controller.query.filter.audience, CatalogAudience.male);
    expect(controller.query.filter.categoryId, 'category-shoes');

    await controller.resetFilters();
    expect(controller.query, CatalogQuery.initial());
  });

  test('keeps empty results successful and retries failures', () async {
    final api = FakeCatalogBrowseApi((query, count) async {
      if (count == 1) {
        throw const CatalogFailure(CatalogFailureCode.unavailable);
      }
      return categoriesTestResult(query, empty: true);
    });
    final controller = CategoriesController(catalogApi: api);
    addTearDown(controller.onClose);
    controller.onInit();
    await _waitForState<CategoriesError>(controller);

    await controller.retry();

    expect(controller.viewState, isA<CategoriesEmpty>());
    expect(api.loadCount, 2);
  });

  test('deduplicates the same in-flight query', () async {
    final completer = Completer<CatalogBrowseResult>();
    final api = FakeCatalogBrowseApi((query, _) => completer.future);
    final controller = CategoriesController(catalogApi: api);
    addTearDown(controller.onClose);

    final first = controller.load();
    final second = controller.load();
    expect(api.loadCount, 1);

    completer.complete(categoriesTestResult(CatalogQuery.initial()));
    await Future.wait(<Future<void>>[first, second]);
    expect(controller.viewState, isA<CategoriesData>());
  });

  test('ignores stale data and results delivered after disposal', () async {
    final first = Completer<CatalogBrowseResult>();
    final second = Completer<CatalogBrowseResult>();
    final api = FakeCatalogBrowseApi(
      (query, count) => count == 1 ? first.future : second.future,
    );
    final controller = CategoriesController(catalogApi: api);

    final firstLoad = controller.load();
    final maleFilter = CatalogFilter(
      audience: CatalogAudience.male,
      categoryId: 'category-shoes',
    );
    final secondLoad = controller.applyFilter(maleFilter);
    first.complete(categoriesTestResult(CatalogQuery.initial()));
    await firstLoad;
    expect(controller.viewState, isA<CategoriesLoading>());

    controller.onClose();
    second.complete(
      categoriesTestResult(CatalogQuery.initial().copyWith(filter: maleFilter)),
    );
    await secondLoad;
    expect(controller.viewState, isA<CategoriesLoading>());
  });

  test('filter controller isolates draft, reset and category expansion', () {
    final initial = CatalogQuery.initial().filter;
    final controller = CategoriesFilterController(
      initialFilter: initial,
      categories: categoriesTestOptions(),
    );
    addTearDown(controller.onClose);

    controller.selectAudience(CatalogAudience.male);
    controller.toggleCategory('category-shoes');
    expect(controller.draft.audience, CatalogAudience.male);
    expect(controller.draft.categoryId, 'category-shoes');
    expect(initial.audience, CatalogAudience.female);

    controller.reset();
    expect(controller.draft, CatalogQuery.initial().filter);
    expect(controller.expandedCategoryId, 'category-clothing');
  });
}

Future<void> _waitForState<T extends CategoriesViewState>(
  CategoriesController controller,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.viewState is T) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
