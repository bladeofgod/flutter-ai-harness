import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_wishlist/controllers/recently_viewed_controller.dart';
import 'package:app_features/feature_wishlist/controllers/wishlist_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wishlist_test_fixtures.dart';

void main() {
  test('Wishlist loads data and removes optimistically once', () async {
    final removeCompleter = Completer<WishlistOverview>();
    final overview = wishlistTestOverview();
    final api = FakeWishlistApi(
      loadWishlistHandler: (_) async => overview,
      removeHandler: (_, _) => removeCompleter.future,
      loadRecentlyViewedHandler: (_) async => recentlyViewedTestSnapshot(),
    );
    final controller = WishlistController(wishlistApi: api);
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForWishlistState<WishlistData>(controller);

    final firstRemoval = controller.remove('product-1');
    final duplicateRemoval = controller.remove('product-1');

    expect((controller.viewState as WishlistData).overview.items, hasLength(1));
    expect(api.removeCount, 1);
    removeCompleter.complete(wishlistTestOverview(itemCount: 1));
    await Future.wait(<Future<void>>[firstRemoval, duplicateRemoval]);
    expect(api.removeCount, 1);
  });

  test('Wishlist exposes failure and retry recovery', () async {
    final overview = wishlistTestOverview();
    final api = FakeWishlistApi(
      loadWishlistHandler: (count) async {
        if (count == 1) {
          throw const WishlistFailure(WishlistFailureCode.unavailable);
        }
        return overview;
      },
      removeHandler: (_, _) async => overview,
      loadRecentlyViewedHandler: (_) async => recentlyViewedTestSnapshot(),
    );
    final controller = WishlistController(wishlistApi: api);
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForWishlistState<WishlistError>(controller);

    await controller.retry();

    expect(controller.viewState, isA<WishlistData>());
    expect(api.wishlistLoadCount, 2);
  });

  test(
    'Wishlist ignores stale full snapshots from concurrent removals',
    () async {
      final overview = wishlistTestOverview();
      final first = Completer<WishlistOverview>();
      final second = Completer<WishlistOverview>();
      final api = FakeWishlistApi(
        loadWishlistHandler: (_) async => overview,
        removeHandler: (productId, _) => switch (productId) {
          'product-1' => first.future,
          'product-2' => second.future,
          _ => throw StateError('Unexpected product: $productId'),
        },
        loadRecentlyViewedHandler: (_) async => recentlyViewedTestSnapshot(),
      );
      final controller = WishlistController(wishlistApi: api);
      controller.onInit();
      addTearDown(controller.onClose);
      await _waitForWishlistState<WishlistData>(controller);

      final removeFirst = controller.remove('product-1');
      final removeSecond = controller.remove('product-2');
      second.complete(
        WishlistOverview(
          items: overview.items
              .where((item) => item.product.id != 'product-2')
              .toList(growable: false),
          recentlyViewed: overview.recentlyViewed,
          recommendations: overview.recommendations,
        ),
      );
      await removeSecond;
      first.complete(
        WishlistOverview(
          items: overview.items
              .where((item) => item.product.id != 'product-1')
              .toList(growable: false),
          recentlyViewed: overview.recentlyViewed,
          recommendations: overview.recommendations,
        ),
      );
      await removeFirst;

      expect(api.removeCount, 2);
      expect((controller.viewState as WishlistData).overview.items, isEmpty);
    },
  );

  test('Recently Viewed filters deterministic dates', () async {
    final controller = RecentlyViewedController(
      wishlistApi: successfulWishlistApi(),
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForRecentState<RecentlyViewedData>(controller);

    expect(
      (controller.viewState as RecentlyViewedData).visibleItems,
      hasLength(4),
    );
    controller.selectYesterday();
    expect(
      (controller.viewState as RecentlyViewedData).visibleItems,
      hasLength(3),
    );

    controller.openCalendar();
    controller.selectCalendarDay(17);
    controller.applyCalendarSelection();

    final custom = controller.viewState as RecentlyViewedData;
    expect(custom.selectedDate, WishlistDate(year: 2026, month: 4, day: 17));
    expect(custom.visibleItems.single.id, 'custom-1');
  });

  test('calendar cancel and Back preserve the committed date', () async {
    final controller = RecentlyViewedController(
      wishlistApi: successfulWishlistApi(),
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForRecentState<RecentlyViewedData>(controller);

    controller.openCalendar();
    controller.selectCalendarDay(17);
    expect(controller.consumeBack(), isTrue);

    final data = controller.viewState as RecentlyViewedData;
    expect(data.isCalendarOpen, isFalse);
    expect(data.isToday, isTrue);
    expect(controller.consumeBack(), isFalse);
  });

  test('Recently Viewed exposes failure and retry recovery', () async {
    final overview = wishlistTestOverview();
    final api = FakeWishlistApi(
      loadWishlistHandler: (_) async => overview,
      removeHandler: (_, _) async => overview,
      loadRecentlyViewedHandler: (count) async {
        if (count == 1) {
          throw const WishlistFailure(WishlistFailureCode.unavailable);
        }
        return recentlyViewedTestSnapshot();
      },
    );
    final controller = RecentlyViewedController(wishlistApi: api);
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForRecentState<RecentlyViewedError>(controller);

    await controller.retry();

    expect(controller.viewState, isA<RecentlyViewedData>());
    expect(api.recentLoadCount, 2);
  });
}

Future<void> _waitForWishlistState<T extends WishlistViewState>(
  WishlistController controller,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.viewState is T) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Wishlist state did not become $T.');
}

Future<void> _waitForRecentState<T extends RecentlyViewedViewState>(
  RecentlyViewedController controller,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.viewState is T) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Recently Viewed state did not become $T.');
}
