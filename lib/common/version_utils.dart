/// 版本号解析与比较工具类
class VersionUtils {
  /// 清洗版本字符串：去除前导 v/V、构建号 (+204)、预发布标识 (-beta 等) 及多余空白字符
  static String cleanVersion(String version) {
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    if (v.contains('+')) {
      v = v.split('+').first.trim();
    }
    if (v.contains('-')) {
      v = v.split('-').first.trim();
    }
    return v;
  }

  /// 比较两个版本号：
  /// - 返回 1 表示 v1 > v2 (v1 较新)
  /// - 返回 0 表示 v1 == v2
  /// - 返回 -1 表示 v1 < v2 (v1 较旧)
  ///
  /// 该方法在任意版本号格式异常或空串时均不会抛出异常。
  static int compareVersions(String v1, String v2) {
    final clean1 = cleanVersion(v1);
    final clean2 = cleanVersion(v2);

    final parts1 = clean1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = clean2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final length =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < length; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// 判断 targetVersion 是否高于 currentVersion
  static bool hasNewerVersion(String targetVersion, String currentVersion) {
    return compareVersions(targetVersion, currentVersion) > 0;
  }
}
