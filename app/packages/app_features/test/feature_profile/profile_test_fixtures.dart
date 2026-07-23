import 'package:app_data/app_data.dart';
import 'package:app_features/api/current_user_provider.dart';
import 'package:app_features/api/profile_dashboard_api.dart';
import 'package:flutter/foundation.dart';

final class FakeProfileDashboardApi implements ProfileDashboardApi {
  FakeProfileDashboardApi(this._load);

  final Future<ProfileDashboard> Function(int loadCount) _load;
  var loadCount = 0;

  @override
  Future<ProfileDashboard> load() {
    loadCount += 1;
    return _load(loadCount);
  }
}

final class FakeCurrentUserProvider implements CurrentUserProvider {
  FakeCurrentUserProvider(this._value);

  UserEntity? _value;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  int get listenerCount => _listeners.length;

  @override
  UserEntity? get value => _value;

  void setUser(UserEntity? user) {
    _value = user;
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

UserEntity profileTestUser(String displayName) => UserEntity(
  id: 'user-${displayName.toLowerCase().replaceAll(' ', '-')}',
  displayName: displayName,
  email: EmailAddress(
    '${displayName.toLowerCase().replaceAll(' ', '.')}@example.com',
  ),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('2015550123'),
  avatar: UserAvatar.asset('assets/images/profile/avatar_romina.png'),
);

ProfileDashboard profileTestDashboard({
  bool emptySections = false,
}) => ProfileDashboard(
  announcement: Announcement(
    title: 'Announcement',
    message: 'A deterministic profile message.',
  ),
  recentlyViewed: emptySections
      ? const <RecentlyViewed>[]
      : List<RecentlyViewed>.generate(
          5,
          (index) => RecentlyViewed(
            id: 'recent-${index + 1}',
            imageAssetKey:
                'assets/images/profile/recent_${(index + 1).toString().padLeft(2, '0')}.png',
          ),
        ),
  orders: OrderSummary(
    items: const <OrderStatusSummary>[
      OrderStatusSummary(status: OrderStatus.toPay),
      OrderStatusSummary(status: OrderStatus.toReceive, hasNotification: true),
      OrderStatusSummary(status: OrderStatus.toReview),
    ],
  ),
  stories: emptySections
      ? const <Story>[]
      : List<Story>.generate(
          4,
          (index) => Story(
            id: 'story-${index + 1}',
            title: index == 0 ? 'Live Shopping' : 'Story ${index + 1}',
            imageAssetKey:
                'assets/images/profile/story_${(index + 1).toString().padLeft(2, '0')}.png',
            isLive: index == 0,
          ),
        ),
  newItems: emptySections
      ? const <ProductSummary>[]
      : List<ProductSummary>.generate(
          5,
          (index) => profileTestProduct(index + 1),
        ),
  mostPopular: emptySections
      ? const <ProductSummary>[]
      : List<ProductSummary>.generate(
          4,
          (index) => profileTestProduct(index + 6, tag: 'New'),
        ),
  categories: emptySections
      ? const <CategorySummary>[]
      : List<CategorySummary>.generate(
          8,
          (index) => CategorySummary(
            id: 'category-${index + 1}',
            name: 'Category ${index + 1}',
            imageAssetKey:
                'assets/images/profile/product_${(index + 9).toString().padLeft(2, '0')}.png',
            itemCount: 100 + index,
          ),
        ),
  flashSale: FlashSale(
    hours: 0,
    minutes: 36,
    seconds: 58,
    products: emptySections
        ? const <ProductSummary>[]
        : List<ProductSummary>.generate(
            6,
            (index) => profileTestProduct(index + 10, tag: '-20%'),
          ),
  ),
  topProducts: emptySections
      ? const <ProductSummary>[]
      : List<ProductSummary>.generate(
          5,
          (index) => profileTestProduct(index + 16, title: 'Top ${index + 1}'),
        ),
  recommendations: emptySections
      ? const <ProductSummary>[]
      : List<ProductSummary>.generate(
          8,
          (index) => profileTestProduct(index + 1),
        ),
);

ProductSummary profileTestProduct(
  int number, {
  String? title,
  String? tag,
}) => ProductSummary(
  id: 'product-$number',
  title: title ?? 'Demo product $number',
  imageAssetKey:
      'assets/images/profile/product_${number.toString().padLeft(2, '0')}.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
  tag: tag,
  popularityCount: 1780,
);
