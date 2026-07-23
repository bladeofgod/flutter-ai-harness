import 'package:app_data/app_data.dart';
import 'package:app_features/api/catalog_api.dart';

final class FakeCatalogBrowseApi implements CatalogBrowseApi {
  FakeCatalogBrowseApi(this._browse);

  final Future<CatalogBrowseResult> Function(CatalogQuery query, int loadCount)
  _browse;
  final List<CatalogQuery> queries = <CatalogQuery>[];

  int get loadCount => queries.length;

  @override
  Future<CatalogBrowseResult> browse(CatalogQuery query) {
    queries.add(query);
    return _browse(query, loadCount);
  }
}

CatalogBrowseResult categoriesTestResult(
  CatalogQuery query, {
  bool empty = false,
}) => CatalogBrowseResult(
  query: query,
  categories: categoriesTestOptions(),
  products: empty
      ? const <ProductSummary>[]
      : List<ProductSummary>.generate(
          20,
          (index) => ProductSummary(
            id: 'product-${index + 1}',
            title: 'Demo catalog product ${index + 1}',
            imageAssetKey:
                'assets/images/catalog/products/categories_product_${((index % 9) + 1).toString().padLeft(2, '0')}.png',
            price: Money(
              currency: Currency.usd,
              minorUnits: 1700 + index * 100,
            ),
          ),
        ),
);

List<CatalogFilterCategory> categoriesTestOptions() => <CatalogFilterCategory>[
  CatalogFilterCategory(
    id: 'category-clothing',
    name: 'Clothing',
    imageAssetKey: 'assets/images/profile/product_12.png',
    subcategories: List<CatalogSubcategory>.generate(
      10,
      (index) => CatalogSubcategory(
        id: 'subcategory-${index + 1}',
        name: <String>[
          'Dresses',
          'Pants',
          'Skirts',
          'Shorts',
          'Jackets',
          'Hoodies',
          'Shirts',
          'Polo',
          'T-Shirts',
          'Tunics',
        ][index],
        imageAssetKey:
            'assets/images/profile/product_${(index + 1).toString().padLeft(2, '0')}.png',
      ),
    ),
  ),
  for (final option in <({String id, String name, int image})>[
    (id: 'category-shoes', name: 'Shoes', image: 20),
    (id: 'category-bags', name: 'Bags', image: 16),
    (id: 'category-lingerie', name: 'Lingerie', image: 17),
    (id: 'category-accessories', name: 'Accessories', image: 18),
    (id: 'category-for-you', name: 'Just for You', image: 19),
  ])
    CatalogFilterCategory(
      id: option.id,
      name: option.name,
      imageAssetKey:
          'assets/images/profile/product_${option.image.toString().padLeft(2, '0')}.png',
      subcategories: const <CatalogSubcategory>[],
    ),
];
