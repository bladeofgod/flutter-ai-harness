import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/catalog_api.dart';
import 'controllers/categories_controller.dart';
import 'pages/categories_filter_page.dart';
import 'pages/categories_page.dart';

const categoriesRoutePath = '/categories';
const categoriesFilterRoutePath = '/categories/filter';

typedef CategoriesProductNavigation =
    void Function(BuildContext context, String productId);

final class CategoriesFilterRouteArguments {
  CategoriesFilterRouteArguments({
    required this.initialFilter,
    required List<CatalogFilterCategory> categories,
  }) : categories = List<CatalogFilterCategory>.unmodifiable(categories);

  final CatalogFilter initialFilter;
  final List<CatalogFilterCategory> categories;
}

List<RouteBase> buildCategoriesRoutes({
  required CatalogBrowseApi catalogApi,
  ValueChanged<String>? onProductSelected,
  CategoriesProductNavigation? openProduct,
}) => <RouteBase>[
  GoRoute(
    path: categoriesRoutePath,
    builder: (context, state) => CategoriesPage(
      controller: CategoriesController(catalogApi: catalogApi),
      onProductSelected: openProduct == null
          ? onProductSelected ?? _ignoreProductSelection
          : (productId) => openProduct(context, productId),
      openFilter: (initialFilter, categories) => context.push<CatalogFilter>(
        categoriesFilterRoutePath,
        extra: CategoriesFilterRouteArguments(
          initialFilter: initialFilter,
          categories: categories,
        ),
      ),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: 'filter',
        redirect: (context, state) =>
            state.extra is CategoriesFilterRouteArguments
            ? null
            : categoriesRoutePath,
        pageBuilder: (context, state) {
          final arguments = state.extra;
          final resolvedArguments = arguments is CategoriesFilterRouteArguments
              ? arguments
              : CategoriesFilterRouteArguments(
                  initialFilter: CatalogQuery.initial().filter,
                  categories: const <CatalogFilterCategory>[],
                );
          return MaterialPage<CatalogFilter>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: CategoriesFilterPage(
              controller: CategoriesFilterController(
                initialFilter: resolvedArguments.initialFilter,
                categories: resolvedArguments.categories,
              ),
              onCancel: context.pop,
              onApply: (filter) => context.pop(filter),
            ),
          );
        },
      ),
    ],
  ),
];

void _ignoreProductSelection(String productId) {}
