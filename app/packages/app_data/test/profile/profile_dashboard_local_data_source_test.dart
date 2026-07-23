import 'dart:collection';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('deterministic Profile Fixture', () {
    late ProfileDashboardLocalDataSource dataSource;

    setUp(() {
      dataSource = _dataSource(
        FixtureApiTransport(
          handlers: <FixtureRequestHandler>[ProfileDashboardFixtureHandler()],
        ),
      );
    });

    test('maps the complete Dashboard in design section order', () async {
      final dashboard = await dataSource.load();

      expect(dashboard.announcement?.title, 'Announcement');
      expect(
        dashboard.announcement?.message,
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
        'Maecenas hendrerit luctus libero ac vulputate.',
      );
      expect(dashboard.recentlyViewed.map((item) => item.id), <String>[
        'recent-1',
        'recent-2',
        'recent-3',
        'recent-4',
        'recent-5',
      ]);
      expect(dashboard.orders.items.map((item) => item.status), <OrderStatus>[
        OrderStatus.toPay,
        OrderStatus.toReceive,
        OrderStatus.toReview,
      ]);
      expect(dashboard.orders.items[1].hasNotification, isTrue);
      expect(dashboard.stories, hasLength(4));
      expect(dashboard.stories.first.isLive, isTrue);
      expect(dashboard.stories.skip(1).every((story) => !story.isLive), isTrue);
      expect(dashboard.newItems, hasLength(5));
      expect(dashboard.newItems.first.price?.minorUnits, 1700);
      expect(dashboard.newItems.first.displayPrice, r'$17,00');
      expect(dashboard.mostPopular.map((item) => item.tag), <String?>[
        'New',
        'Sale',
        'Hot',
        'New',
      ]);
      expect(
        dashboard.mostPopular.every((item) => item.popularityCount == 1780),
        isTrue,
      );
      expect(dashboard.categories.map((item) => item.name), <String>[
        'Clothing',
        'Shoes',
        'Bags',
        'Lingerie',
        'Dresses',
        'Jackets',
        'Tops',
        'Accessories',
      ]);
      expect(dashboard.categories, hasLength(8));
      expect(dashboard.categories.map((item) => item.imageAssetKey), <String>[
        for (var index = 10; index <= 17; index += 1)
          _imageKey('product', index),
      ]);
      expect(dashboard.flashSale.displayCountdown, '00:36:58');
      expect(dashboard.flashSale.products, hasLength(6));
      expect(dashboard.topProducts.map((item) => item.title), <String>[
        'Dresses',
        'T-Shirts',
        'Skirts',
        'Shoes',
        'Bags',
      ]);
      expect(dashboard.recommendations, hasLength(8));
    });

    test('is stable across repeated reads', () async {
      final first = await dataSource.load();
      final second = await dataSource.load();

      expect(
        second.recentlyViewed.map((item) => item.imageAssetKey),
        first.recentlyViewed.map((item) => item.imageAssetKey),
      );
      expect(
        second.recommendations.map((item) => item.id),
        first.recommendations.map((item) => item.id),
      );
      expect(
        second.flashSale.displayCountdown,
        first.flashSale.displayCountdown,
      );
    });

    test('uses only the approved local Profile image keys', () async {
      final dashboard = await dataSource.load();
      final keys = _imageKeys(dashboard);
      final allowed = <String>{
        for (var index = 1; index <= 5; index += 1) _imageKey('recent', index),
        for (var index = 1; index <= 4; index += 1) _imageKey('story', index),
        for (var index = 1; index <= 20; index += 1)
          _imageKey('product', index),
      };

      expect(keys, isNotEmpty);
      expect(keys.difference(allowed), isEmpty);
      expect(keys.any((key) => key.contains('localhost')), isFalse);
      expect(keys.any((key) => Uri.parse(key).hasScheme), isFalse);
    });
  });

  group('empty and failure boundaries', () {
    test(
      'maps all empty sections without inventing fallback content',
      () async {
        final dataSource = _dataSource(
          _PayloadTransport(_emptyDashboardPayload()),
        );

        final dashboard = await dataSource.load();

        expect(dashboard.announcement, isNull);
        expect(dashboard.recentlyViewed, isEmpty);
        expect(dashboard.orders.items, isEmpty);
        expect(dashboard.stories, isEmpty);
        expect(dashboard.newItems, isEmpty);
        expect(dashboard.mostPopular, isEmpty);
        expect(dashboard.categories, isEmpty);
        expect(dashboard.flashSale.products, isEmpty);
        expect(dashboard.topProducts, isEmpty);
        expect(dashboard.recommendations, isEmpty);
      },
    );

    test('normalizes malformed structures to invalidResponse', () async {
      final dataSource = _dataSource(
        const _PayloadTransport(<String, Object?>{'recentlyViewed': 'wrong'}),
      );

      await expectLater(
        dataSource.load(),
        throwsA(
          const ProfileDashboardFailure(
            ProfileDashboardFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test('normalizes invalid Domain values from payloads', () async {
      final payload = _emptyDashboardPayload();
      payload['recentlyViewed'] = <Object?>[
        <String, Object?>{
          'id': 'recent-1',
          'imageAssetKey': 'https://localhost/image.png',
        },
      ];
      final dataSource = _dataSource(_PayloadTransport(payload));

      await expectLater(
        dataSource.load(),
        throwsA(
          const ProfileDashboardFailure(
            ProfileDashboardFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test('maps unavailable rejection to a stable failure', () async {
      final dataSource = _dataSource(const _UnavailableTransport());

      await expectLater(
        dataSource.load(),
        throwsA(
          const ProfileDashboardFailure(
            ProfileDashboardFailureCode.unavailable,
          ),
        ),
      );
    });

    test('maps transport failures and preserves their stack', () async {
      final dataSource = _dataSource(_ThrowingTransport());

      try {
        await dataSource.load();
        fail('Expected ProfileDashboardFailure.');
      } on ProfileDashboardFailure catch (failure, stackTrace) {
        expect(failure.code, ProfileDashboardFailureCode.transportUnavailable);
        expect(stackTrace.toString(), contains('_ThrowingTransport.send'));
      }
    });

    test('does not hide unexpected mapper programming errors', () async {
      final dataSource = _dataSource(_PayloadTransport(_ProgrammingErrorMap()));

      await expectLater(dataSource.load(), throwsStateError);
    });

    test('uses the stable Profile Dashboard request key', () async {
      final transport = _KeyRecordingTransport();
      final dataSource = _dataSource(transport);

      await dataSource.load();

      expect(transport.key, 'profile.dashboard.load');
    });
  });
}

ProfileDashboardLocalDataSource _dataSource(ApiTransport transport) =>
    ProfileDashboardLocalDataSource(apiClient: ApiClient(transport: transport));

Map<String, Object?> _emptyDashboardPayload() => <String, Object?>{
  'announcement': null,
  'recentlyViewed': <Object?>[],
  'orders': <String, Object?>{'items': <Object?>[]},
  'stories': <Object?>[],
  'newItems': <Object?>[],
  'mostPopular': <Object?>[],
  'categories': <Object?>[],
  'flashSale': <String, Object?>{
    'hours': 0,
    'minutes': 0,
    'seconds': 0,
    'products': <Object?>[],
  },
  'topProducts': <Object?>[],
  'recommendations': <Object?>[],
};

Set<String> _imageKeys(ProfileDashboard dashboard) => <String>{
  ...dashboard.recentlyViewed.map((item) => item.imageAssetKey),
  ...dashboard.stories.map((item) => item.imageAssetKey),
  ...dashboard.newItems.map((item) => item.imageAssetKey),
  ...dashboard.mostPopular.map((item) => item.imageAssetKey),
  ...dashboard.categories.map((item) => item.imageAssetKey),
  ...dashboard.flashSale.products.map((item) => item.imageAssetKey),
  ...dashboard.topProducts.map((item) => item.imageAssetKey),
  ...dashboard.recommendations.map((item) => item.imageAssetKey),
};

String _imageKey(String family, int number) =>
    'assets/images/profile/${family}_${number.toString().padLeft(2, '0')}.png';

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _UnavailableTransport implements ApiTransport {
  const _UnavailableTransport();

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'profile.dashboard_unavailable'),
      );
}

final class _ThrowingTransport implements ApiTransport {
  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    throw const ApiTransportException(cause: 'private detail');
  }
}

final class _KeyRecordingTransport implements ApiTransport {
  String? key;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    return ApiResponse<Object?>.success(_emptyDashboardPayload());
  }
}

final class _ProgrammingErrorMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => throw StateError('programming error');

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Iterable<String> get keys => const <String>[];

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}
