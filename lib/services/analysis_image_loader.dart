import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/analysis_image.dart';
import '../widgets/common/app_network_image.dart';

enum AnalysisImageLoadStatus { ready, missing, unavailable }

class AnalysisImageLoadResult {
  final AnalysisImageLoadStatus status;
  final String? url;

  const AnalysisImageLoadResult({required this.status, this.url});
}

/// Resolves stored and legacy image candidates using the viewer's image cache.
class AnalysisImageLoader {
  final Future<void> Function(String url) _loadImage;
  final Set<String> _missingUrls = <String>{};

  AnalysisImageLoader({Future<void> Function(String url)? loadImage})
    : _loadImage = loadImage ?? _loadDecodedImage;

  Future<AnalysisImageLoadResult> load(AnalysisImage image) async {
    var hadTemporaryFailure = false;
    for (final url in image.urls.map((url) => url.trim()).toSet()) {
      if (url.isEmpty || _missingUrls.contains(url)) continue;
      try {
        await _loadImage(url);
        return AnalysisImageLoadResult(
          status: AnalysisImageLoadStatus.ready,
          url: url,
        );
      } catch (error) {
        final statusCode = switch (error) {
          HttpExceptionWithStatus() => error.statusCode,
          NetworkImageLoadException() => error.statusCode,
          _ => null,
        };
        if (statusCode == 404 || statusCode == 410) {
          _missingUrls.add(url);
        } else {
          hadTemporaryFailure = true;
        }
      }
    }
    return AnalysisImageLoadResult(
      status: hadTemporaryFailure
          ? AnalysisImageLoadStatus.unavailable
          : AnalysisImageLoadStatus.missing,
    );
  }

  static Future<void> _loadDecodedImage(String url) async {
    final stream = AppNetworkImage.provider(
      url,
    ).resolve(ImageConfiguration.empty);
    final completer = Completer<void>();
    final listener = ImageStreamListener(
      (image, _) {
        image.dispose();
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    try {
      stream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      stream.removeListener(listener);
    }
  }
}
