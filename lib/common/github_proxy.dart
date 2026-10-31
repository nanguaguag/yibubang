import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 镜像代理配置管理
class GitHubProxyConfig {
  static const String keySelectedProxy = 'github_proxy_prefix';

  /// 官方 GitHub Raw 主源
  static const String rawBaseUrl =
      'https://raw.githubusercontent.com/nanguaguag/yibubang/main/yibubang_update.json';

  /// jsDelivr CDN 备份源（仅支持清单文件，全球多节点高可用）
  static const String jsdelivrManifestUrl =
      'https://cdn.jsdelivr.net/gh/nanguaguag/yibubang@main/yibubang_update.json';

  /// 默认 HTTP 请求头，避免被 Cloudflare/WAF 误判为恶意 Bot 导致 403
  static const Map<String, String> defaultHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  /// 预设镜像加速列表
  static const List<Map<String, String>> presets = [
    {
      'name': 'GitHub直连',
      'prefix': '',
      'description': '直接访问官方服务器（海外或开启代理推荐）',
    },
    {
      'name': 'gh-proxy.com',
      'prefix': 'https://gh-proxy.com/',
      'description': '推荐稳定 GitHub 镜像加速站（支持清单与安装包下载）',
    },
    {
      'name': 'ghproxy.net',
      'prefix': 'https://ghproxy.net/',
      'description': '常用备用 GitHub 镜像加速站',
    },
  ];

  /// 获取当前已配置的代理前缀（默认为空：直连）
  static Future<String> getSelectedPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(keySelectedProxy);
    // 自动清理已知失效或开启了全站盾拦截的旧镜像配置
    if (saved == 'https://ghps.cc/' || saved == 'https://mirror.ghproxy.com/') {
      await prefs.setString(keySelectedProxy, 'https://gh-proxy.com/');
      return 'https://gh-proxy.com/';
    }
    return saved ?? '';
  }

  /// 设置代理前缀
  static Future<void> setSelectedPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySelectedProxy, prefix.trim());
  }

  /// 获取当前镜像站展示名称
  static Future<String> getSelectedName() async {
    final prefix = await getSelectedPrefix();
    for (final item in presets) {
      if (item['prefix'] == prefix) return item['name']!;
    }
    return prefix.isEmpty ? '直连 (官方 GitHub)' : '自定义: $prefix';
  }

  /// 将给定的 GitHub 原生 URL 包装为经过镜像加速的 URL
  static String applyProxy(String url, String prefix) {
    if (prefix.isEmpty) return url;
    // 如果 URL 已经包含了镜像前缀，则不重复添加
    if (url.startsWith(prefix)) return url;
    final cleanPrefix = prefix.endsWith('/') ? prefix : '$prefix/';
    return '$cleanPrefix$url';
  }

  /// 获取根据用户当前配置代理包装后的 yibubang_update.json 请求地址
  static Future<String> getManifestUrl() async {
    final prefix = await getSelectedPrefix();
    return applyProxy(rawBaseUrl, prefix);
  }

  /// 获取清单拉取的多源候选地址链（用户选定源 -> 推荐镜像源 -> jsDelivr CDN -> 官方直连）
  static Future<List<String>> getCandidateManifestUrls() async {
    final primaryUrl = await getManifestUrl();
    final candidates = <String>[primaryUrl];
    const recommendedProxy = 'https://gh-proxy.com/';
    final recommendedUrl = applyProxy(rawBaseUrl, recommendedProxy);
    if (!candidates.contains(recommendedUrl)) {
      candidates.add(recommendedUrl);
    }
    if (!candidates.contains(jsdelivrManifestUrl)) {
      candidates.add(jsdelivrManifestUrl);
    }
    if (!candidates.contains(rawBaseUrl)) {
      candidates.add(rawBaseUrl);
    }
    return candidates;
  }

  /// 包装下载 URL（如 Release 安装包）
  static Future<String> resolveDownloadUrl(String url) async {
    final prefix = await getSelectedPrefix();
    return applyProxy(url, prefix);
  }
}
