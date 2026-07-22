import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Registry returns deterministic Domain-only Profile data', () async {
    final firstRegistry = FeaturesRegistry.local();
    final secondRegistry = FeaturesRegistry.local();

    final ProfileDashboard first = await firstRegistry.profileDashboardApi
        .load();
    final ProfileDashboard second = await secondRegistry.profileDashboardApi
        .load();

    expect(first.announcement?.title, 'Announcement');
    expect(first.recentlyViewed, hasLength(5));
    expect(first.orders.items.map((item) => item.status), [
      OrderStatus.toPay,
      OrderStatus.toReceive,
      OrderStatus.toReview,
    ]);
    expect(first.stories, hasLength(4));
    expect(first.newItems, hasLength(5));
    expect(first.mostPopular, hasLength(4));
    expect(first.categories, hasLength(8));
    expect(first.flashSale.displayCountdown, '00:36:58');
    expect(first.topProducts, hasLength(5));
    expect(first.recommendations, hasLength(8));
    expect(
      second.recommendations.map((product) => product.id),
      orderedEquals(first.recommendations.map((product) => product.id)),
    );
  });
}
