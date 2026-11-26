import 'dart:convert';

/// A textbook reference and its image candidates, ordered by preference.
/// A null reference denotes a stored image without a matching page reference.
class AnalysisImage {
  final String? reference;
  final List<String> urls;

  const AnalysisImage({this.reference, required this.urls});
}

final RegExp analysisImageReferencePattern = RegExp(
  r'(?:[0-9\u4e00-\u9fff]+)?P\d+(?:[-~～—–－]P?\d+)?',
);

/// Prefer actual image metadata while retaining the historical URL convention.
List<AnalysisImage> analysisImages({
  required String text,
  String? storedImages,
  required String legacyBaseUrl,
}) {
  final references = analysisImageReferencePattern
      .allMatches(text)
      .map((match) => match.group(0)!)
      .toList();
  final assigned = List.generate(references.length, (_) => <String>[]);
  final unassigned = <String>[];

  for (final url in _storedImageUrls(storedImages)) {
    final filename = Uri.parse(url).pathSegments.lastOrNull ?? '';
    final stem = filename.replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    final normalizedStem = _referenceKey(stem);
    final ordinalMatch = RegExp(r'-(\d+)$').firstMatch(stem);
    final ordinal = int.tryParse(ordinalMatch?.group(1) ?? '');
    int? index;

    // A filename may include the complete textbook reference. Prefer that
    // evidence over an ordinal alone, which is also common in stored names.
    final matchingReferences = <int>[];
    for (var i = 0; i < references.length; i++) {
      final reference = _referenceKey(references[i]);
      if (normalizedStem.endsWith(reference) ||
          (ordinal != null && normalizedStem.endsWith('$reference-$ordinal'))) {
        matchingReferences.add(i);
      }
    }
    if (matchingReferences.isNotEmpty) {
      index = ordinal != null && matchingReferences.contains(ordinal - 1)
          ? ordinal - 1
          : matchingReferences.first;
    } else if (ordinal != null && ordinal > 0 && ordinal <= references.length) {
      index = ordinal - 1;
    }

    if (index == null) {
      unassigned.add(url);
    } else {
      assigned[index].add(url);
    }
  }

  final base = legacyBaseUrl.trim();
  final hasLegacyBase = _isHttpUrl(base);
  return [
    for (var i = 0; i < references.length; i++)
      AnalysisImage(
        reference: references[i],
        urls: <String>{
          ...assigned[i],
          if (hasLegacyBase)
            '$base${references[i]}-${i + 1}.jpg?x-oss-process=style/water_mark',
        }.toList(growable: false),
      ),
    for (final url in unassigned) AnalysisImage(urls: [url]),
  ];
}

String _referenceKey(String reference) =>
    reference.replaceAll(RegExp(r'[-~～—–－]P?'), '-');

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

Iterable<String> _storedImageUrls(String? storedImages) {
  final urls = <String>{};

  void collect(dynamic value) {
    if (value is List) {
      for (final item in value) {
        collect(item);
      }
    } else if (value is String) {
      final trimmed = value.trim();
      if (_isHttpUrl(trimmed)) {
        urls.add(trimmed);
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded != trimmed) collect(decoded);
        } on FormatException {
          // Empty values, legacy flags and malformed metadata are not URLs.
        }
      }
    }
  }

  collect(storedImages);
  return urls;
}
