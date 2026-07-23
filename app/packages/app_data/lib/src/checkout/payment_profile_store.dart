import 'dart:async';

import 'checkout_models.dart';

/// 地址与掩码支付方式的进程级唯一事实来源。
final class PaymentProfileStore {
  PaymentProfileStore({PaymentProfileSnapshot? initialSnapshot})
    : _snapshot = initialSnapshot ?? fixedPaymentProfileSnapshot();

  PaymentProfileSnapshot _snapshot;
  final StreamController<PaymentProfileSnapshot> _snapshots =
      StreamController<PaymentProfileSnapshot>.broadcast(sync: true);

  PaymentProfileSnapshot get current => _snapshot;
  Stream<PaymentProfileSnapshot> get snapshots => _snapshots.stream;

  void reset() {
    _snapshot = fixedPaymentProfileSnapshot();
    _snapshots.add(_snapshot);
  }

  PaymentProfileSnapshot upsertAddress(ShippingAddress address) {
    final addresses = <ShippingAddress>[..._snapshot.addresses];
    final index = addresses.indexWhere((current) => current.id == address.id);
    if (index == -1) {
      addresses.add(address);
    } else {
      addresses[index] = address;
    }
    return _publish(
      addresses: addresses,
      paymentMethods: _snapshot.paymentMethods,
      selectedAddressId: _snapshot.selectedAddressId ?? address.id,
      selectedPaymentMethodId: _snapshot.selectedPaymentMethodId,
    );
  }

  PaymentProfileSnapshot removeAddress(String addressId) {
    final addresses = _snapshot.addresses
        .where((address) => address.id != addressId)
        .toList(growable: false);
    if (addresses.length == _snapshot.addresses.length) {
      throw ArgumentError.value(addressId, 'addressId', 'Address not found.');
    }
    return _publish(
      addresses: addresses,
      paymentMethods: _snapshot.paymentMethods,
      selectedAddressId: _snapshot.selectedAddressId == addressId
          ? addresses.firstOrNull?.id
          : _snapshot.selectedAddressId,
      selectedPaymentMethodId: _snapshot.selectedPaymentMethodId,
    );
  }

  PaymentProfileSnapshot selectAddress(String addressId) {
    _requirePresent(
      _snapshot.addresses.any((address) => address.id == addressId),
      addressId,
      'addressId',
    );
    return _publish(
      addresses: _snapshot.addresses,
      paymentMethods: _snapshot.paymentMethods,
      selectedAddressId: addressId,
      selectedPaymentMethodId: _snapshot.selectedPaymentMethodId,
    );
  }

  PaymentProfileSnapshot upsertPaymentMethod(PaymentMethod method) {
    final methods = <PaymentMethod>[..._snapshot.paymentMethods];
    final index = methods.indexWhere((current) => current.id == method.id);
    if (index == -1) {
      methods.add(method);
    } else {
      methods[index] = method;
    }
    return _publish(
      addresses: _snapshot.addresses,
      paymentMethods: methods,
      selectedAddressId: _snapshot.selectedAddressId,
      selectedPaymentMethodId: _snapshot.selectedPaymentMethodId ?? method.id,
    );
  }

  PaymentProfileSnapshot removePaymentMethod(String paymentMethodId) {
    final methods = _snapshot.paymentMethods
        .where((method) => method.id != paymentMethodId)
        .toList(growable: false);
    if (methods.length == _snapshot.paymentMethods.length) {
      throw ArgumentError.value(
        paymentMethodId,
        'paymentMethodId',
        'Payment method not found.',
      );
    }
    return _publish(
      addresses: _snapshot.addresses,
      paymentMethods: methods,
      selectedAddressId: _snapshot.selectedAddressId,
      selectedPaymentMethodId:
          _snapshot.selectedPaymentMethodId == paymentMethodId
          ? methods.firstOrNull?.id
          : _snapshot.selectedPaymentMethodId,
    );
  }

  PaymentProfileSnapshot selectPaymentMethod(String paymentMethodId) {
    _requirePresent(
      _snapshot.paymentMethods.any((method) => method.id == paymentMethodId),
      paymentMethodId,
      'paymentMethodId',
    );
    return _publish(
      addresses: _snapshot.addresses,
      paymentMethods: _snapshot.paymentMethods,
      selectedAddressId: _snapshot.selectedAddressId,
      selectedPaymentMethodId: paymentMethodId,
    );
  }

  PaymentProfileSnapshot _publish({
    required List<ShippingAddress> addresses,
    required List<PaymentMethod> paymentMethods,
    required String? selectedAddressId,
    required String? selectedPaymentMethodId,
  }) {
    _snapshot = PaymentProfileSnapshot(
      addresses: addresses,
      paymentMethods: paymentMethods,
      selectedAddressId: selectedAddressId,
      selectedPaymentMethodId: selectedPaymentMethodId,
    );
    _snapshots.add(_snapshot);
    return _snapshot;
  }

  Future<void> close() => _snapshots.close();
}

PaymentProfileSnapshot fixedPaymentProfileSnapshot() => PaymentProfileSnapshot(
  addresses: <ShippingAddress>[
    ShippingAddress(
      id: 'shipping-home',
      recipientName: 'Olivia Martin',
      streetLine: '26, Duong So 2, Thao Dien Ward',
      city: 'Ho Chi Minh City',
      region: 'District 2',
      postalCode: '700000',
      country: 'Vietnam',
    ),
  ],
  paymentMethods: <PaymentMethod>[
    PaymentMethod(id: 'payment-card-primary', brand: 'Visa', lastFour: '9843'),
    PaymentMethod(
      id: 'payment-card-secondary',
      brand: 'Mastercard',
      lastFour: '1289',
    ),
  ],
  selectedAddressId: 'shipping-home',
  selectedPaymentMethodId: 'payment-card-primary',
);

void _requirePresent(bool isPresent, String value, String name) {
  if (!isPresent) {
    throw ArgumentError.value(value, name, 'Value is not present.');
  }
}
