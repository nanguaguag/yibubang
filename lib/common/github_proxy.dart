import 'package:shared_preferences/shared_preferences.dart';

/// GitHub 镜像代理配置管理
class GitHubProxyConfig {
  static const String keySelectedProxy = 'github_proxy_prefix';

  /// 官方 GitHub Raw 主源
  static const String rawBaseUrl =
      'https://raw.githubusercontent.com/nanguaguag/yibubang/main/yibubang_update.json';

  /// 预设镜像加速列表
  static const List<Map<String, String>> presets = [
    {
      'name': 'GitHub直连',
      'prefix': '',
      'description': '直接访问官方服务器（海外或开启代理推荐）',
    },
    {
      'name': 'ghproxy.net',
      'prefix': 'https://ghproxy.net/',
      'description': '常用稳定 GitHub 镜像加速站',
    },
    {
      'name': 'ghps.cc',
      'prefix': 'https://ghps.cc/',
      'description': '常用 GitHub 镜像加速站',
    },
    {
      'name': 'mirror.ghproxy.com',
      'prefix': 'https://mirror.ghproxy.com/',
      'description': '备用镜像加速站',
    },
  ];

  /// 获取当前已配置的代理前缀（默认为空：直连）
  static Future<String> getSelectedPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keySelectedProxy) ?? '';
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

  /// 包装下载 URL（如 Release 安装包）
  static Future<String> resolveDownloadUrl(String url) async {
    final prefix = await getSelectedPrefix();
    return applyProxy(url, prefix);
  }
}
