import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/analysis_image.dart';
import 'package:yibubang/services/analysis_image_loader.dart';

void main() {
  const storedUrl = 'https://example.com/stored.jpg';
  const legacyUrl = 'https://example.com/legacy.jpg';
  const image = AnalysisImage(urls: [storedUrl, legacyUrl]);

  test(
    'returns the first image that loads, preserving candidate order',
    () async {
      final calls = <String>[];
      final loader = AnalysisImageLoader(
        loadImage: (url) async {
          calls.add(url);
        },
      );

      final result = await loader.load(image);

      expect(result.status, AnalysisImageLoadStatus.ready);
      expect(result.url, storedUrl);
      expect(calls, [storedUrl]);
    },
  );

  test('falls back to legacy when the stored image is missing', () async {
    final calls = <String>[];
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        calls.add(url);
        if (url == storedUrl) {
          throw HttpExceptionWithStatus(404, 'Missing', uri: Uri.parse(url));
        }
      },
    );

    final result = await loader.load(image);

    expect(result.status, AnalysisImageLoadStatus.ready);
    expect(result.url, legacyUrl);
    expect(calls, [storedUrl, legacyUrl]);
    await loader.load(image);
    expect(calls, [storedUrl, legacyUrl, legacyUrl]);
  });

  test('remembers 404 and 410 only for this loader instance', () async {
    final calls = <String>[];
    Future<void> missing(String url) async {
      calls.add(url);
      if (url == storedUrl) {
        throw const HttpExceptionWithStatus(404, 'Missing');
      }
      throw NetworkImageLoadException(statusCode: 410, uri: Uri.parse(url));
    }

    final loader = AnalysisImageLoader(loadImage: missing);
    final first = await loader.load(image);
    final second = await loader.load(image);

    expect(first.status, AnalysisImageLoadStatus.missing);
    expect(first.url, isNull);
    expect(second.status, AnalysisImageLoadStatus.missing);
    expect(calls, [storedUrl, legacyUrl]);

    final freshLoader = AnalysisImageLoader(loadImage: missing);
    await freshLoader.load(image);
    expect(calls, [storedUrl, legacyUrl, storedUrl, legacyUrl]);
  });

  test('network failure stays retryable and does not become missing', () async {
    var attempts = 0;
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        attempts++;
        if (attempts == 1) throw const SocketException('Offline');
      },
    );
    const singleImage = AnalysisImage(urls: [storedUrl]);

    final failed = await loader.load(singleImage);
    final recovered = await loader.load(singleImage);

    expect(failed.status, AnalysisImageLoadStatus.unavailable);
    expect(failed.url, isNull);
    expect(recovered.status, AnalysisImageLoadStatus.ready);
    expect(recovered.url, storedUrl);
    expect(attempts, 2);
  });

  test('a temporary candidate failure takes precedence over missing', () async {
    final calls = <String>[];
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        calls.add(url);
        if (url == storedUrl) {
          throw const HttpExceptionWithStatus(404, 'Missing');
        }
        throw TimeoutException('Image load timed out');
      },
    );

    expect(
      (await loader.load(image)).status,
      AnalysisImageLoadStatus.unavailable,
    );
    expect(
      (await loader.load(image)).status,
      AnalysisImageLoadStatus.unavailable,
    );
    expect(calls, [storedUrl, legacyUrl, legacyUrl]);
  });

  test('continues to a working fallback after a temporary failure', () async {
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        if (url == storedUrl) {
          throw const HttpExceptionWithStatus(503, 'Try again');
        }
      },
    );

    final result = await loader.load(image);

    expect(result.status, AnalysisImageLoadStatus.ready);
    expect(result.url, legacyUrl);
  });

  test('access and server errors never permanently disable a URL', () async {
    var attempts = 0;
    final loader = AnalysisImageLoader(
      loadImage: (url) async {
        attempts++;
        if (attempts == 1) {
          throw const HttpExceptionWithStatus(403, 'Forbidden');
        }
        if (attempts == 2) {
          throw NetworkImageLoadException(statusCode: 500, uri: Uri.parse(url));
        }
      },
    );
    const singleImage = AnalysisImage(urls: [storedUrl]);

    expect(
      (await loader.load(singleImage)).status,
      AnalysisImageLoadStatus.unavailable,
    );
    expect(
      (await loader.load(singleImage)).status,
      AnalysisImageLoadStatus.unavailable,
    );
    expect(
      (await loader.load(singleImage)).status,
      AnalysisImageLoadStatus.ready,
    );
    expect(attempts, 3);
  });

  test(
    'an empty candidate list is missing without a network request',
    () async {
      var called = false;
      final loader = AnalysisImageLoader(
        loadImage: (url) async {
          called = true;
        },
      );

      final result = await loader.load(const AnalysisImage(urls: []));

      expect(result.status, AnalysisImageLoadStatus.missing);
      expect(called, isFalse);
    },
  );
}
