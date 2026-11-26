import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/models/analysis_image.dart';

const base = 'https://images.example/question/restore/40/BK479';

String legacy(String reference, int ordinal) =>
    '$base$reference-$ordinal.jpg?x-oss-process=style/water_mark';

void main() {
  test('retains textbook labels and supported page ranges', () {
    final images = analysisImages(
      text: '（系统解剖学P87）及（系统解剖学P172～173）、（内科学P12-P13）',
      legacyBaseUrl: base,
    );

    expect(images.map((image) => image.reference), [
      '系统解剖学P87',
      '系统解剖学P172～173',
      '内科学P12-P13',
    ]);
    expect(images[1].urls, [legacy('系统解剖学P172～173', 2)]);
  });

  test(
    'prefers stored URL for its reference without replacing other pages',
    () {
      const stored = 'https://images.example/BK479系统解剖学P87-1.jpg';
      final images = analysisImages(
        text: '（系统解剖学P87）与（内科学P217）',
        storedImages: stored,
        legacyBaseUrl: base,
      );

      expect(images[0].urls, [stored, legacy('系统解剖学P87', 1)]);
      expect(images[1].urls, [legacy('内科学P217', 2)]);
    },
  );

  test('maps BK479P217-2 to second reference instead of first stored slot', () {
    const stored = 'https://images.example/BK479P217-2.jpg';
    final images = analysisImages(
      text: '（内科学P190）与（内科学P217）',
      storedImages: jsonEncode([stored]),
      legacyBaseUrl: base,
    );

    expect(images[0].urls, [legacy('内科学P190', 1)]);
    expect(images[1].urls, [stored, legacy('内科学P217', 2)]);
  });

  test('decodes JSON strings and percent-encoded reference filenames', () {
    final stored = Uri.parse(
      'https://images.example/BK479系统解剖学P87-1.jpg',
    ).toString();
    final images = analysisImages(
      text: '（系统解剖学P87）',
      storedImages: jsonEncode(stored),
      legacyBaseUrl: base,
    );

    expect(images.single.urls, [stored, legacy('系统解剖学P87', 1)]);
  });

  test(
    'preserves standalone BMP images without inventing a page reference',
    () {
      const stored = 'https://images.example/anatomy.bmp';
      final images = analysisImages(
        text: '这里是图片说明，没有教材页码。',
        storedImages: stored,
        legacyBaseUrl: base,
      );

      expect(images, hasLength(1));
      expect(images.single.reference, isNull);
      expect(images.single.urls, [stored]);
    },
  );

  test('filters invalid URLs, deduplicates, and preserves metadata order', () {
    const first = 'https://images.example/anatomy.bmp';
    const second = 'http://images.example/diagram.png';
    final images = analysisImages(
      text: '',
      storedImages: jsonEncode([
        first,
        'file:///private/photo.jpg',
        'javascript:alert(1)',
        0,
        null,
        first,
        second,
        'https://',
      ]),
      legacyBaseUrl: '',
    );

    expect(images.map((image) => image.urls.single), [first, second]);
  });

  test('empty or malformed metadata preserves all legacy candidates', () {
    for (final metadata in [null, '', '0', '[]', 'broken json']) {
      final images = analysisImages(
        text: '（系统解剖学P87）和（内科学P217）',
        storedImages: metadata,
        legacyBaseUrl: base,
      );
      expect(images.map((image) => image.urls), [
        [legacy('系统解剖学P87', 1)],
        [legacy('内科学P217', 2)],
      ]);
    }
  });

  test('does not generate legacy URLs without a usable base', () {
    for (final prefix in ['', '   ', 'file:///images/', 'https://']) {
      final images = analysisImages(text: '（系统解剖学P87）', legacyBaseUrl: prefix);

      expect(images.single.reference, '系统解剖学P87');
      expect(images.single.urls, isEmpty);
    }
  });

  test('full reference filename takes precedence over mismatched ordinal', () {
    const stored = 'https://images.example/系统解剖学P87-2.jpg';
    final images = analysisImages(
      text: '（系统解剖学P87）和（内科学P217）',
      storedImages: stored,
      legacyBaseUrl: base,
    );

    expect(images[0].urls.first, stored);
    expect(images[1].urls, [legacy('内科学P217', 2)]);
  });
}
