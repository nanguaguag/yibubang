import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/github_proxy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GitHubProxyConfig Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default prefix should be empty (direct)', () async {
      final prefix = await GitHubProxyConfig.getSelectedPrefix();
      expect(prefix, '');
    });

    test('migrates dead presets (ghps.cc, mirror.ghproxy.com) to gh-proxy.com', () async {
      SharedPreferences.setMockInitialValues({
        GitHubProxyConfig.keySelectedProxy: 'https://ghps.cc/',
      });
      final migrated1 = await GitHubProxyConfig.getSelectedPrefix();
      expect(migrated1, 'https://gh-proxy.com/');

      SharedPreferences.setMockInitialValues({
        GitHubProxyConfig.keySelectedProxy: 'https://mirror.ghproxy.com/',
      });
      final migrated2 = await GitHubProxyConfig.getSelectedPrefix();
      expect(migrated2, 'https://gh-proxy.com/');
    });

    test('applyProxy applies prefix correctly without duplicate slashes', () {
      const url = 'https://raw.githubusercontent.com/test/repo/main/file.json';
      expect(GitHubProxyConfig.applyProxy(url, ''), url);
      expect(
        GitHubProxyConfig.applyProxy(url, 'https://gh-proxy.com/'),
        'https://gh-proxy.com/$url',
      );
      expect(
        GitHubProxyConfig.applyProxy(url, 'https://gh-proxy.com'),
        'https://gh-proxy.com/$url',
      );
      expect(
        GitHubProxyConfig.applyProxy('https://gh-proxy.com/$url', 'https://gh-proxy.com/'),
        'https://gh-proxy.com/$url',
      );
    });

    test('getCandidateManifestUrls returns multi-source fallback chain', () async {
      final candidates = await GitHubProxyConfig.getCandidateManifestUrls();
      expect(candidates.isNotEmpty, true);
      expect(candidates.contains(GitHubProxyConfig.rawBaseUrl), true);
      expect(candidates.contains(GitHubProxyConfig.jsdelivrManifestUrl), true);
      expect(
        candidates.any((url) => url.contains('https://gh-proxy.com/')),
        true,
      );
    });
  });
}
