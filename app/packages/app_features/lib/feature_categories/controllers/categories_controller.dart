import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/catalog_api.dart';

sealed class CategoriesViewState {
  const CategoriesViewState();
}

final class CategoriesLoading extends CategoriesViewState {
  const CategoriesLoading();
}

final class CategoriesData extends CategoriesViewState {
  const CategoriesData(this.result);

  final CatalogBrowseResult result;
}

final class CategoriesEmpty extends CategoriesViewState {
  const CategoriesEmpty(this.result);

  final CatalogBrowseResult result;
}

final class CategoriesError extends CategoriesViewState {
  const CategoriesError(this.failure);

  final CatalogFailure failure;
}

/// 管理 Categories 查询、已应用筛选和滚动相关展示状态。
final class CategoriesController extends GetxController {
  CategoriesController({
    required CatalogBrowseApi catalogApi,
    CatalogQuery? initialQuery,
  }) : _catalogApi = catalogApi,
       _query = initialQuery ?? CatalogQuery.initial();

  final CatalogBrowseApi _catalogApi;
  final Rx<CategoriesViewState> _viewState = Rx<CategoriesViewState>(
    const CategoriesLoading(),
  );
  final RxBool _isScrolled = false.obs;

  CatalogQuery _query;
  CatalogQuery? _activeQuery;
  Future<void>? _activeLoad;
  var _requestGeneration = 0;
  var _isDisposed = false;

  CategoriesViewState get viewState => _viewState.value;
  CatalogQuery get query => _query;
  CatalogFilter get appliedFilter => _query.filter;
  bool get isScrolled => _isScrolled.value;

  @override
  void onInit() {
    super.onInit();
    _loadFromLifecycle();
  }

  Future<void> load({CatalogQuery? query}) {
    if (_isDisposed) {
      return Future<void>.value();
    }
    final target = query ?? _query;
    final activeLoad = _activeLoad;
    if (activeLoad != null && _activeQuery == target) {
      return activeLoad;
    }

    _query = target;
    _activeQuery = target;
    final requestGeneration = ++_requestGeneration;
    _viewState.value = const CategoriesLoading();
    final load = _performLoad(target, requestGeneration);
    _activeLoad = load;
    unawaited(
      load.then<void>(
        (_) => _clearActiveLoad(load),
        onError: (Object _, StackTrace _) => _clearActiveLoad(load),
      ),
    );
    return load;
  }

  void _clearActiveLoad(Future<void> load) {
    if (_activeLoad == load) {
      _activeLoad = null;
      _activeQuery = null;
    }
  }

  Future<void> _performLoad(CatalogQuery query, int requestGeneration) async {
    try {
      final result = await _catalogApi.browse(query);
      if (_canPublish(requestGeneration)) {
        _viewState.value = result.products.isEmpty
            ? CategoriesEmpty(result)
            : CategoriesData(result);
      }
    } on CatalogFailure catch (failure) {
      if (_canPublish(requestGeneration)) {
        _viewState.value = CategoriesError(failure);
      }
    }
  }

  Future<void> selectSubcategory(String? subcategoryId) => load(
    query: _query.copyWith(
      filter: _query.filter.copyWith(
        subcategoryId: subcategoryId,
        clearSubcategory: subcategoryId == null,
      ),
    ),
  );

  Future<void> applyFilter(CatalogFilter filter) =>
      load(query: _query.copyWith(filter: filter));

  Future<void> resetFilters() => load(query: CatalogQuery.initial());

  Future<void> retry() => load();

  void retryFromUi() {
    _loadFromLifecycle();
  }

  void setScrolled(bool value) {
    if (!_isDisposed && _isScrolled.value != value) {
      _isScrolled.value = value;
    }
  }

  bool _canPublish(int requestGeneration) =>
      !_isDisposed && requestGeneration == _requestGeneration;

  void _loadFromLifecycle() {
    unawaited(_loadAndReportUnexpectedError());
  }

  Future<void> _loadAndReportUnexpectedError() async {
    try {
      await load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while loading Categories'),
        ),
      );
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    _requestGeneration += 1;
    super.onClose();
  }
}

/// 只拥有筛选页草稿；取消页面不会修改 Categories 已应用条件。
final class CategoriesFilterController extends GetxController {
  CategoriesFilterController({
    required CatalogFilter initialFilter,
    required List<CatalogFilterCategory> categories,
  }) : categories = List<CatalogFilterCategory>.unmodifiable(categories),
       _draft = Rx<CatalogFilter>(initialFilter),
       _expandedCategoryId = RxnString(initialFilter.categoryId);

  final List<CatalogFilterCategory> categories;
  final Rx<CatalogFilter> _draft;
  final RxnString _expandedCategoryId;

  CatalogFilter get draft => _draft.value;
  String? get expandedCategoryId => _expandedCategoryId.value;

  void selectAudience(CatalogAudience audience) {
    _draft.value = draft.copyWith(audience: audience);
  }

  void toggleCategory(String categoryId) {
    if (_expandedCategoryId.value == categoryId) {
      _expandedCategoryId.value = null;
      return;
    }
    _expandedCategoryId.value = categoryId;
    _draft.value = draft.copyWith(
      categoryId: categoryId,
      clearSubcategory: true,
    );
  }

  void selectSubcategory(String categoryId, String subcategoryId) {
    _expandedCategoryId.value = categoryId;
    _draft.value = CatalogFilter(
      audience: draft.audience,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
    );
  }

  void reset() {
    final resetFilter = CatalogQuery.initial().filter;
    _draft.value = resetFilter;
    _expandedCategoryId.value = resetFilter.categoryId;
  }
}
