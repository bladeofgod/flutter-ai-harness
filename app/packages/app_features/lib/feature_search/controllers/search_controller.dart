import 'dart:async';
import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../api/search_api.dart';
import '../../api/search_image_picker.dart';

enum SearchViewState {
  initial,
  searching,
  results,
  empty,
  error,
  imageRecognizing,
  imageRecognized,
  imageResults,
}

enum SearchUiError { unavailable }

enum _FailedSearchOperation { text, image }

base class SearchFlowController extends GetxController {
  SearchFlowController({
    required SearchApi searchApi,
    required SearchImagePicker imagePicker,
    CatalogFilter? initialFilter,
  }) : _searchApi = searchApi,
       _imagePicker = imagePicker,
       _appliedFilter = initialFilter ?? _defaultFilter,
       _draftFilter = initialFilter ?? _defaultFilter;

  static final CatalogFilter _defaultFilter = CatalogFilter(
    audience: CatalogAudience.all,
    categoryId: 'category-clothing',
  );

  final SearchApi _searchApi;
  final SearchImagePicker _imagePicker;
  final queryController = TextEditingController();

  SearchViewState _state = SearchViewState.initial;
  SearchUiError? _error;
  SearchImagePickFailure? _imagePickFailure;
  SearchResult? _textResult;
  SearchImageResult? _imageResult;
  Uint8List? _selectedImageBytes;
  late CatalogFilter _appliedFilter;
  late CatalogFilter _draftFilter;
  SearchQuery? _lastSubmittedQuery;
  _FailedSearchOperation? _failedOperation;
  bool _isPickingImage = false;
  bool _isDisposed = false;
  var _operationGeneration = 0;

  SearchViewState get state => _state;
  SearchUiError? get error => _error;
  SearchImagePickFailure? get imagePickFailure => _imagePickFailure;
  SearchResult? get textResult => _textResult;
  SearchImageResult? get imageResult => _imageResult;
  CatalogFilter get appliedFilter => _appliedFilter;
  CatalogFilter get draftFilter => _draftFilter;
  bool get isPickingImage => _isPickingImage;
  Uint8List? get selectedImageBytes {
    final bytes = _selectedImageBytes;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  Future<void> submit({bool force = false}) async {
    if (_isDisposed || _isPickingImage) {
      return;
    }
    final text = queryController.text.trim();
    if (text.isEmpty) {
      _lastSubmittedQuery = null;
      _textResult = null;
      _error = null;
      _state = SearchViewState.initial;
      update();
      return;
    }
    final query = SearchQuery(text: text, filter: _appliedFilter);
    if (!force &&
        query == _lastSubmittedQuery &&
        (_state == SearchViewState.results ||
            _state == SearchViewState.empty)) {
      return;
    }
    if (_state == SearchViewState.searching) {
      return;
    }

    final previousState = _state;
    _state = SearchViewState.searching;
    _error = null;
    _failedOperation = null;
    _imagePickFailure = null;
    final generation = ++_operationGeneration;
    update();
    try {
      final result = await _searchApi.searchText(query);
      if (_isDisposed || generation != _operationGeneration) {
        return;
      }
      _lastSubmittedQuery = query;
      _textResult = result;
      _state = result.products.isEmpty
          ? SearchViewState.empty
          : SearchViewState.results;
    } on SearchFailure {
      if (!_isDisposed && generation == _operationGeneration) {
        _error = SearchUiError.unavailable;
        _failedOperation = _FailedSearchOperation.text;
        _state = SearchViewState.error;
      }
    } on Object catch (error, stackTrace) {
      if (!_isDisposed && generation == _operationGeneration) {
        _state = previousState;
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        update();
      }
    }
  }

  Future<void> pickImage() => _selectImage(_imagePicker.pickFromGallery);

  Future<void> capturePhoto() => _selectImage(_imagePicker.capturePhoto);

  Future<void> _selectImage(
    Future<SearchImagePickResult> Function() select,
  ) async {
    if (_isDisposed || _isPickingImage || _state == SearchViewState.searching) {
      return;
    }
    _isPickingImage = true;
    _imagePickFailure = null;
    _failedOperation = null;
    final previousState = _state;
    final generation = ++_operationGeneration;
    update();
    try {
      final pickResult = await select();
      if (_isDisposed || generation != _operationGeneration) {
        return;
      }
      switch (pickResult) {
        case SearchImagePickCanceled():
          return;
        case SearchImagePickFailed(:final failure):
          _imagePickFailure = failure;
          return;
        case SearchImagePickSuccess(:final bytes):
          _selectedImageBytes?.fillRange(0, _selectedImageBytes!.length, 0);
          _selectedImageBytes = Uint8List.fromList(bytes);
          bytes.fillRange(0, bytes.length, 0);
      }

      _state = SearchViewState.imageRecognizing;
      _error = null;
      update();
      final imageResult = await _searchApi.searchImage(
        SearchImageInput(_selectedImageBytes!),
      );
      if (_isDisposed || generation != _operationGeneration) {
        return;
      }
      _imageResult = imageResult;
      _state = SearchViewState.imageRecognized;
    } on SearchFailure {
      if (!_isDisposed && generation == _operationGeneration) {
        _error = SearchUiError.unavailable;
        _failedOperation = _FailedSearchOperation.image;
        _state = SearchViewState.error;
      }
    } on Object catch (error, stackTrace) {
      if (!_isDisposed && generation == _operationGeneration) {
        _state = previousState;
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isPickingImage = false;
        update();
      }
    }
  }

  void showImageResults() {
    if (_isDisposed ||
        _state != SearchViewState.imageRecognized ||
        _imageResult == null) {
      return;
    }
    _state = SearchViewState.imageResults;
    update();
  }

  void beginFilter() {
    _draftFilter = _appliedFilter;
  }

  void selectDraftAudience(CatalogAudience audience) {
    if (_isDisposed || _draftFilter.audience == audience) {
      return;
    }
    _draftFilter = _draftFilter.copyWith(audience: audience);
    update();
  }

  void selectDraftCategory(String categoryId) {
    if (_isDisposed || _draftFilter.categoryId == categoryId) {
      return;
    }
    _draftFilter = _draftFilter.copyWith(
      categoryId: categoryId,
      clearSubcategory: true,
    );
    update();
  }

  void cancelFilter() {
    if (_isDisposed) {
      return;
    }
    _draftFilter = _appliedFilter;
    update();
  }

  Future<void> applyFilter() async {
    if (_isDisposed) {
      return;
    }
    final changed = _draftFilter != _appliedFilter;
    _appliedFilter = _draftFilter;
    if (changed && queryController.text.trim().isNotEmpty) {
      await submit(force: true);
    } else {
      update();
    }
  }

  Future<void> retry() async {
    if (_state != SearchViewState.error) {
      return;
    }
    switch (_failedOperation) {
      case _FailedSearchOperation.text:
        await submit(force: true);
      case _FailedSearchOperation.image:
        await _retrySelectedImage();
      case null:
        return;
    }
  }

  Future<void> _retrySelectedImage() async {
    final bytes = _selectedImageBytes;
    if (_isDisposed || _isPickingImage || bytes == null) {
      return;
    }
    _isPickingImage = true;
    _failedOperation = null;
    _error = null;
    _state = SearchViewState.imageRecognizing;
    final generation = ++_operationGeneration;
    update();
    try {
      final imageResult = await _searchApi.searchImage(SearchImageInput(bytes));
      if (_isDisposed || generation != _operationGeneration) {
        return;
      }
      _imageResult = imageResult;
      _state = SearchViewState.imageRecognized;
    } on SearchFailure {
      if (!_isDisposed && generation == _operationGeneration) {
        _error = SearchUiError.unavailable;
        _failedOperation = _FailedSearchOperation.image;
        _state = SearchViewState.error;
      }
    } on Object catch (error, stackTrace) {
      if (!_isDisposed && generation == _operationGeneration) {
        _error = SearchUiError.unavailable;
        _failedOperation = _FailedSearchOperation.image;
        _state = SearchViewState.error;
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isPickingImage = false;
        update();
      }
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    _operationGeneration += 1;
    _selectedImageBytes?.fillRange(0, _selectedImageBytes!.length, 0);
    _selectedImageBytes = null;
    _imageResult = null;
    _failedOperation = null;
    queryController.clear();
    queryController.dispose();
    unawaited(_clearImageDraftsOnClose());
    super.onClose();
  }

  Future<void> _clearImageDraftsOnClose() async {
    try {
      await _imagePicker.clearDrafts();
    } on Object catch (_, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: const _SearchMediaCleanupFailure(),
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while clearing Search media drafts'),
        ),
      );
    }
  }
}

final class _SearchMediaCleanupFailure implements Exception {
  const _SearchMediaCleanupFailure();

  @override
  String toString() => 'SearchMediaCleanupFailure(<redacted>)';
}
