import 'package:app_core/app_core.dart';
import 'package:app_data/src/cart/cart_failure.dart';
import 'package:app_data/src/cart/cart_fixture_handler.dart';
import 'package:app_data/src/cart/cart_local.dart';
import 'package:app_data/src/cart/cart_models.dart';
import 'package:app_data/src/catalog/catalog_models.dart';
import 'package:app_data/src/fixture/fixture_api_transport.dart';
import 'package:test/test.dart';

void main() {
  group('CartLocalDataSource', () {
    test('loads fixed Demo cart and a fresh handler restores it', () async {
      final first = _dataSource();
      final initial = await first.load();
      await first.remove(lineId: initial.items.first.id);

      expect((await first.load()).items, hasLength(1));
      expect((await _dataSource().load()).items, hasLength(2));
    });

    test('upserts same variation and separates another variation', () async {
      final source = _dataSource(initialItems: const <CartItem>[]);
      final product = _product('one');
      final pink = CartLineInput(
        product: product,
        variation: ProductVariation(color: 'Pink', size: 'M'),
        quantity: 2,
      );

      await source.upsert(pink);
      var result = await source.upsert(pink);
      expect(result.didMutate, isTrue);
      expect(result.cart.items, hasLength(1));
      expect(result.cart.items.single.quantity, 4);

      result = await source.upsert(
        CartLineInput(
          product: product,
          variation: ProductVariation(color: 'Blue', size: 'M'),
        ),
      );
      expect(result.cart.items, hasLength(2));
    });

    test('updates quantity, removes, and keeps totals exact', () async {
      final source = _dataSource();
      final initial = await source.load();
      final first = initial.items.first;

      var result = await source.setQuantity(lineId: first.id, quantity: 3);
      expect(result.cart.total.minorUnits, 7200);
      expect(result.cart.totalQuantity, 4);

      result = await source.remove(lineId: first.id);
      expect(result.cart.items, hasLength(1));
      expect(result.cart.total.minorUnits, 2100);
    });

    test('checkout clear is atomic and idempotent by attempt ID', () async {
      final source = _dataSource();

      final first = await source.clearAfterSuccessfulCheckout(
        attemptId: 'attempt-1',
      );
      final repeated = await source.clearAfterSuccessfulCheckout(
        attemptId: 'attempt-1',
      );

      expect(first.didMutate, isTrue);
      expect(first.cart.isEmpty, isTrue);
      expect(repeated.didMutate, isFalse);
      expect(repeated.cart.isEmpty, isTrue);
    });

    test('maps rejected and malformed responses to stable failures', () async {
      final source = _dataSource();
      await expectLater(
        source.setQuantity(lineId: 'missing', quantity: 1),
        throwsA(const CartFailure(CartFailureCode.lineNotFound)),
      );
      await expectLater(
        source.setQuantity(lineId: 'line', quantity: 0),
        throwsA(const CartFailure(CartFailureCode.invalidInput)),
      );

      final malformed = CartLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: const <FixtureRequestHandler>[_MalformedCartHandler()],
          ),
        ),
      );
      await expectLater(
        malformed.load(),
        throwsA(const CartFailure(CartFailureCode.invalidResponse)),
      );
    });
  });
}

CartLocalDataSource _dataSource({List<CartItem>? initialItems}) =>
    CartLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[
            CartFixtureHandler(initialItems: initialItems),
          ],
        ),
      ),
    );

ProductSummary _product(String id) => ProductSummary(
  id: id,
  title: 'Demo product',
  imageAssetKey: 'assets/images/example.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
);

final class _MalformedCartHandler implements FixtureRequestHandler {
  const _MalformedCartHandler();

  @override
  Set<String> get requestKeys => const <String>{CartFixtureHandler.loadKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      const ApiResponse<Object?>.success(<String, Object?>{
        'didMutate': false,
        'cart': <String, Object?>{'currency': 'USD', 'items': 'invalid'},
      });
}
