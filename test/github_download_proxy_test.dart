import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yibubang/common/github_proxy.dart';

void main() {
  test(
    'GitHub download proxy leaves Gitee, R2 and signed subscription URLs untouched',
    () async {
      SharedPreferences.setMockInitialValues({
        GitHubProxyConfig.keySelectedProxy: 'https://gh-proxy.com/',
      });
      for (final url in [
        'https://gitee.com/pumpkin_melon/yibubang/releases/download/database-3.0.0/clinical_final.sqlite.zip',
        'https://yibubang-r2.melonhu.com/databases/%E5%8F%A3%E8%85%94.sqlite.zip',
        'https://example.org/bank.zip?signature=a%2Fb',
      ]) {
        expect(await GitHubProxyConfig.resolveDownloadUrl(url), url);
      }
      const github =
          'https://github.com/nanguaguag/yibubang/releases/download/v1/bank.zip';
      expect(
        await GitHubProxyConfig.resolveDownloadUrl(github),
        'https://gh-proxy.com/$github',
      );
      const raw =
          'https://raw.githubusercontent.com/nanguaguag/yibubang/main/bank.json';
      expect(
        await GitHubProxyConfig.resolveDownloadUrl(raw),
        'https://gh-proxy.com/$raw',
      );
    },
  );
}
