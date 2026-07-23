import 'dart:typed_data';

import '../catalog/catalog_models.dart';

/// 文本搜索的规范化查询。展示和匹配均使用去首尾、合并空白后的值。
final class SearchQuery {
  factory SearchQuery({required String text, required CatalogFilter filter}) {
    final normalizedText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Search text must not be empty.');
    }
    return SearchQuery._(
      text: normalizedText,
      normalizedText: normalizedText.toLowerCase(),
      filter: filter,
    );
  }

  const SearchQuery._({
    required this.text,
    required this.normalizedText,
    required this.filter,
  });

  final String text;
  final String normalizedText;
  final CatalogFilter filter;

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.normalizedText == normalizedText &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(normalizedText, filter);
}

/// 一次文本搜索返回的不可变结果。
final class SearchResult {
  SearchResult({required this.query, required List<ProductSummary> products})
    : products = List<ProductSummary>.unmodifiable(products);

  final SearchQuery query;
  final List<ProductSummary> products;
}

/// 图片搜索输入只保留内存字节，不暴露 Plugin、路径或文件元数据。
final class SearchImageInput {
  SearchImageInput(Uint8List bytes) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Image must not be empty.');
    }
  }

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);
  int get byteLength => _bytes.lengthInBytes;

  @override
  String toString() => 'SearchImageInput(<redacted>)';
}

/// 确定性 Demo 图片识别结果。
final class SearchImageResult {
  SearchImageResult({
    required String recognizedLabel,
    required List<ProductSummary> products,
  }) : recognizedLabel = _requiredText(recognizedLabel, 'recognizedLabel'),
       products = List<ProductSummary>.unmodifiable(products);

  final String recognizedLabel;
  final List<ProductSummary> products;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}
