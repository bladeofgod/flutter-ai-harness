import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/welcome_brand.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    required this.onGetStarted,
    required this.onSignIn,
    super.key,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  static const _referenceSafeHeight = 734.0;
  static const _topGap = 183.0;
  static const _brandTitleGap = 13.0;
  static const _titleDescriptionGap = 18.0;
  static const _minimumActionGap = 32.0;
  static const _primaryHeight = 61.0;
  static const _primarySecondaryGap = 9.0;
  static const _secondaryHitHeight = 48.0;
  static const _bottomGap = 26.0;

  static const _systemUiStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _systemUiStyle,
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleHeight = _measureTextHeight(
              context,
              text: 'Shoppe',
              style: _WelcomeTextStyles.brand,
              maxWidth: 335,
              maxLines: 1,
            );
            final descriptionHeight = _measureTextHeight(
              context,
              text: 'Beautiful eCommerce UI Kit for your online store',
              style: _WelcomeTextStyles.description,
              maxWidth: 249,
            );
            final fixedHeight =
                _topGap +
                150 +
                _brandTitleGap +
                titleHeight +
                _titleDescriptionGap +
                descriptionHeight +
                _primaryHeight +
                _primarySecondaryGap +
                _secondaryHitHeight +
                _bottomGap;
            final contentHeight = math.max(
              constraints.maxHeight,
              math.max(_referenceSafeHeight, fixedHeight + _minimumActionGap),
            );
            final actionGap = contentHeight - fixedHeight;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 375),
                  child: SizedBox(
                    height: contentHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: _topGap),
                          const WelcomeBrand(),
                          const SizedBox(height: _brandTitleGap),
                          Text(
                            'Shoppe',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: _WelcomeTextStyles.brand,
                          ),
                          const SizedBox(height: _titleDescriptionGap),
                          SizedBox(
                            width: 249,
                            child: Text(
                              'Beautiful eCommerce UI Kit for your online store',
                              textAlign: TextAlign.center,
                              style: _WelcomeTextStyles.description,
                            ),
                          ),
                          SizedBox(height: actionGap),
                          SizedBox(
                            width: double.infinity,
                            height: _primaryHeight,
                            child: ElevatedButton(
                              onPressed: onGetStarted,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textOnPrimary,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "Let's get started",
                                  style: _WelcomeTextStyles.primaryAction,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: _primarySecondaryGap),
                          SizedBox(
                            height: _secondaryHitHeight,
                            child: Semantics(
                              button: true,
                              label: 'I already have an account',
                              child: ExcludeSemantics(
                                child: InkWell(
                                  onTap: onSignIn,
                                  borderRadius: BorderRadius.circular(24),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'I already have an account',
                                          maxLines: 1,
                                          style: _WelcomeTextStyles
                                              .secondaryAction,
                                        ),
                                        const SizedBox(width: 16),
                                        const _ArrowButtonVisual(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: _bottomGap),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  double _measureTextHeight(
    BuildContext context, {
    required String text,
    required TextStyle style,
    required double maxWidth,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }
}

class _ArrowButtonVisual extends StatelessWidget {
  const _ArrowButtonVisual();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: const BoxDecoration(
      color: AppColors.primary,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.arrow_forward,
      size: 18,
      color: AppColors.textOnPrimary,
    ),
  );
}

abstract final class _WelcomeTextStyles {
  static const _nunitoVariations = <FontVariation>[
    FontVariation('YTLC', 500),
    FontVariation('wdth', 100),
  ];

  static const brand = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: AppFonts.raleway,
    package: AppFonts.package,
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 61 / 52,
    letterSpacing: 0,
    fontVariations: [FontVariation('wght', 700)],
  );

  static const description = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 19,
    fontWeight: FontWeight.w300,
    height: 33 / 19,
    letterSpacing: 0,
    fontVariations: [..._nunitoVariations, FontVariation('wght', 300)],
  );

  static const primaryAction = TextStyle(
    color: AppColors.textOnPrimary,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 22,
    fontWeight: FontWeight.w300,
    height: 31 / 22,
    letterSpacing: 0,
    fontVariations: [..._nunitoVariations, FontVariation('wght', 300)],
  );

  static const secondaryAction = TextStyle(
    color: Color(0xE6202020),
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 15,
    fontWeight: FontWeight.w300,
    height: 26 / 15,
    letterSpacing: 0,
    fontVariations: [..._nunitoVariations, FontVariation('wght', 300)],
  );
}
