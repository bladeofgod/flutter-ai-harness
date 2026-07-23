import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';

/// Rewards 展示与 Checkout 结算共同使用的 Demo Voucher 事实源。
final Voucher shoppeFiveVoucherFixture = Voucher(
  id: 'voucher-shoppe-five',
  code: 'SHOPPE5',
  title: r'$5 off your Demo order',
  discount: Money(currency: Currency.usd, minorUnits: 500),
  minimumSpend: Money(currency: Currency.usd, minorUnits: 1000),
);
