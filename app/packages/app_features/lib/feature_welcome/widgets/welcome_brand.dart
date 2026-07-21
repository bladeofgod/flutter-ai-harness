import 'package:flutter/widgets.dart';

class WelcomeBrand extends StatelessWidget {
  const WelcomeBrand({super.key});

  static const _asset = 'assets/images/welcome/shoppe_brand.png';

  @override
  Widget build(BuildContext context) => Image.asset(
    _asset,
    package: 'app_features',
    width: 150,
    height: 150,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}
