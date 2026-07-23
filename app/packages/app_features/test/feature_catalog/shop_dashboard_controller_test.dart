import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_catalog/controllers/shop_dashboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_test_fixtures.dart';

void main() {
  test('moves from loading to Shop Domain data', () async {
    final completer = Completer<ShopDashboard>();
    final api = FakeCatalogApi((_) => completer.future);
    final controller = ShopDashboardController(catalogApi: api);

    controller.onInit();
    addTearDown(controller.onClose);
    expect(controller.viewState, isA<ShopDashboardLoading>());

    final dashboard = catalogTestDashboard();
    completer.complete(dashboard);
    await _waitForState<ShopDashboardData>(controller);

    expect((controller.viewState as ShopDashboardData).dashboard, dashboard);
    expect(api.loadCount, 1);
  });

  test('keeps empty Catalog groups as successful data', () async {
    final dashboard = catalogTestDashboard(emptySections: true);
    final controller = ShopDashboardController(
      catalogApi: FakeCatalogApi((_) async => dashboard),
    );

    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForState<ShopDashboardData>(controller);

    final data = (controller.viewState as ShopDashboardData).dashboard;
    expect(data.promotions, isEmpty);
    expect(data.categories, isEmpty);
    expect(data.recommendations, isEmpty);
  });

  test('exposes a retryable Catalog failure and recovers', () async {
    final dashboard = catalogTestDashboard();
    final api = FakeCatalogApi((loadCount) async {
      if (loadCount == 1) {
        throw const CatalogFailure(CatalogFailureCode.unavailable);
      }
      return dashboard;
    });
    final controller = ShopDashboardController(catalogApi: api);

    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForState<ShopDashboardError>(controller);

    await controller.retry();

    expect(controller.viewState, isA<ShopDashboardData>());
    expect(api.loadCount, 2);
  });

  test('ignores data delivered after disposal', () async {
    final completer = Completer<ShopDashboard>();
    final controller = ShopDashboardController(
      catalogApi: FakeCatalogApi((_) => completer.future),
    );

    controller.onInit();
    controller.onClose();
    completer.complete(catalogTestDashboard());
    await Future<void>.delayed(Duration.zero);

    expect(controller.viewState, isA<ShopDashboardLoading>());
  });
}

Future<void> _waitForState<T extends ShopDashboardViewState>(
  ShopDashboardController controller,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.viewState is T) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
