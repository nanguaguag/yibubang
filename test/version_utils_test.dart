import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/common/version_utils.dart';

void main() {
  group('VersionUtils Tests', () {
    test('handles standard semver comparisons', () {
      expect(VersionUtils.compareVersions('2.0.5', '2.0.4'), 1);
      expect(VersionUtils.compareVersions('2.0.4', '2.0.5'), -1);
      expect(VersionUtils.compareVersions('2.0.4', '2.0.4'), 0);
    });

    test('handles v/V prefixes correctly', () {
      expect(VersionUtils.compareVersions('v2.0.5', '2.0.4'), 1);
      expect(VersionUtils.compareVersions('V2.0.5', 'v2.0.5'), 0);
      expect(VersionUtils.compareVersions('v2.0.3', '2.0.4'), -1);
    });

    test('handles build metadata (+204) and prerelease (-beta)', () {
      expect(VersionUtils.compareVersions('2.0.4+204', '2.0.4'), 0);
      expect(VersionUtils.compareVersions('2.0.5+205', '2.0.4+204'), 1);
      expect(VersionUtils.compareVersions('v2.0.5-beta', '2.0.4'), 1);
    });

    test('handles unequal part lengths', () {
      expect(VersionUtils.compareVersions('2.1', '2.0.4'), 1);
      expect(VersionUtils.compareVersions('2.0.4.1', '2.0.4'), 1);
      expect(VersionUtils.compareVersions('2.0', '2.0.0'), 0);
    });

    test('handles empty or malformed strings gracefully without throwing', () {
      expect(VersionUtils.compareVersions('', '2.0.4'), -1);
      expect(VersionUtils.compareVersions('invalid', '2.0.4'), -1);
      expect(VersionUtils.compareVersions('', ''), 0);
    });

    test('hasNewerVersion helper works correctly', () {
      expect(VersionUtils.hasNewerVersion('v2.0.5', '2.0.4'), isTrue);
      expect(VersionUtils.hasNewerVersion('2.0.4', '2.0.4'), isFalse);
      expect(VersionUtils.hasNewerVersion('2.0.3', '2.0.4'), isFalse);
    });
  });
}
