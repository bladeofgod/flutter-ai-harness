import 'package:app_data/app_data.dart';
import 'package:app_features/api/promotions_api.dart';

PromotionsOverview promotionsFixture() {
  final products = <ProductSummary>[
    _product(1, 1700),
    _product(2, 2100),
    _product(3, 2500),
    _product(4, 2900),
  ];
  return PromotionsOverview(
    flashSale: Promotion(
      id: 'promotion-flash-sale',
      title: 'Flash Sale',
      subtitle: 'Today only',
      imageAssetKey: 'assets/images/catalog/big_sale.png',
      flashSale: FlashSale(
        hours: 0,
        minutes: 36,
        seconds: 58,
        products: products,
      ),
    ),
    livePreviews: <LivePreview>[
      LivePreview(
        id: 'live-demo',
        title: 'Summer Style Edit',
        subtitle: 'A local demo preview',
        coverAssetKey: 'assets/images/profile/story_01.png',
        product: products.first,
      ),
    ],
    stories: <StorySequence>[
      StorySequence(
        id: 'story-style-edit',
        title: 'Style Edit',
        coverAssetKey: 'assets/images/profile/story_02.png',
        items: <StoryItem>[
          ProductStoryItem(
            id: 'product-one',
            title: 'Everyday color',
            imageAssetKey: 'assets/images/profile/story_02.png',
            product: products[1],
          ),
          BannerStoryItem(
            id: 'banner',
            title: 'Dress for your day',
            imageAssetKey: 'assets/images/profile/story_03.png',
            body: 'Fresh combinations for a simple daily wardrobe.',
          ),
          ProductStoryItem(
            id: 'product-two',
            title: 'The finishing layer',
            imageAssetKey: 'assets/images/profile/story_04.png',
            product: products[2],
          ),
        ],
      ),
    ],
  );
}

ProductSummary _product(int number, int priceMinorUnits) => ProductSummary(
  id: 'product-$number',
  title: 'Product $number',
  imageAssetKey:
      'assets/images/profile/product_${number.toString().padLeft(2, '0')}.png',
  price: Money(currency: Currency.usd, minorUnits: priceMinorUnits),
);

final class FakePromotionsApi implements PromotionsApi {
  FakePromotionsApi({
    this.overviewLoader,
    this.storyLoader,
    PromotionsOverview? overview,
  }) : _overview = overview ?? promotionsFixture();

  final PromotionsOverview _overview;
  final Future<PromotionsOverview> Function(int callCount)? overviewLoader;
  final Future<StorySequence> Function(String storyId, int callCount)?
  storyLoader;
  int overviewLoadCount = 0;
  int storyLoadCount = 0;

  @override
  Future<PromotionsOverview> loadOverview() {
    overviewLoadCount += 1;
    return overviewLoader?.call(overviewLoadCount) ?? Future.value(_overview);
  }

  @override
  Future<StorySequence> loadStory(String storyId) {
    storyLoadCount += 1;
    return storyLoader?.call(storyId, storyLoadCount) ??
        Future.value(
          _overview.stories.firstWhere(
            (story) => story.id == storyId,
            orElse: () =>
                throw const PromotionsFailure(PromotionsFailureCode.notFound),
          ),
        );
  }
}
