import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/github_proxy.dart';
import '../common/version_utils.dart';

/// 应用检查更新与下载安装管理服务
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  int? _cachedBuildNumber;
  int? get cachedBuildNumber => _cachedBuildNumber;

  /// 检测当前 Android 运行环境 ABI 架构
  /// 优先使用 dart:ffi Abi.current() 探测，若无法直接获得，结合 split-per-abi buildNumber 偏移判定：
  /// - 2000+: arm64-v8a
  /// - 1000+: armeabi-v7a
  /// - 3000+: x86_64
  static String? detectAndroidAbi({Abi? currentAbi, int? buildNumber}) {
    Abi? abi = currentAbi;
    if (abi == null) {
      try {
        abi = Abi.current();
      } catch (_) {
        abi = null;
      }
    }

    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';

    if (buildNumber != null) {
      if (buildNumber >= 3000 && buildNumber < 4000) return 'x86_64';
      if (buildNumber >= 2000 && buildNumber < 3000) return 'arm64-v8a';
      if (buildNumber >= 1000 && buildNumber < 2000) return 'armeabi-v7a';
    }

    return null;
  }

  /// 检查是否存在新版本
  Future<Map<String, dynamic>?> checkUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    _cachedBuildNumber = int.tryParse(info.buildNumber);

    Map<String, dynamic>? manifest;
    // 多源轮询容错：优先使用用户配置的源，若受限或失败自动尝试备用镜像、jsDelivr CDN 与官方直连
    final candidateUrls = await GitHubProxyConfig.getCandidateManifestUrls();
    for (final url in candidateUrls) {
      try {
        manifest = await _fetchManifest(url);
        debugPrint('[AppUpdateService] 成功通过清单源拉取更新: $url');
        break;
      } catch (e) {
        debugPrint('[AppUpdateService] 清单源拉取失败 ($url): $e，尝试备用源...');
      }
    }

    if (manifest == null) return null;

    final latestVersion = manifest['latest_app']?.toString();
    if (latestVersion == null || latestVersion.isEmpty) return null;

    if (VersionUtils.hasNewerVersion(latestVersion, currentVersion)) {
      return manifest;
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetchManifest(String url) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: GitHubProxyConfig.defaultHeaders,
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('更新清单格式不合法');
    }
    return decoded;
  }

  /// 获取对应平台的直链下载地址（支持 Android 架构智能选择 arm64-v8a / armeabi-v7a / x86_64 专用包）
  static String resolvePlatformDownloadUrl(
    Map<String, dynamic> updateData, {
    String? androidAbiOverride,
    bool? isAndroidOverride,
    bool? isWindowsOverride,
    bool? isMacOSOverride,
    bool? isLinuxOverride,
    int? buildNumber,
  }) {
    final version = VersionUtils.cleanVersion(
        updateData['latest_app']?.toString() ?? 'latest');
    final assets = updateData['assets'] as Map<String, dynamic>?;

    final bool isAndroid;
    final bool isWindows;
    final bool isMacOS;
    final bool isLinux;

    if (isAndroidOverride != null ||
        isWindowsOverride != null ||
        isMacOSOverride != null ||
        isLinuxOverride != null) {
      isAndroid = isAndroidOverride ?? false;
      isWindows = isWindowsOverride ?? false;
      isMacOS = isMacOSOverride ?? false;
      isLinux = isLinuxOverride ?? false;
    } else {
      isAndroid = Platform.isAndroid;
      isWindows = Platform.isWindows;
      isMacOS = Platform.isMacOS;
      isLinux = Platform.isLinux;
    }

    String? directUrl;
    if (isAndroid) {
      final abi =
          androidAbiOverride ?? detectAndroidAbi(buildNumber: buildNumber);
      if (abi == 'arm64-v8a') {
        directUrl = assets?['android_arm64']?.toString() ??
            assets?['android']?.toString() ??
            'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-android-arm64-v8a.apk';
      } else if (abi == 'armeabi-v7a') {
        directUrl = assets?['android_armv7']?.toString() ??
            assets?['android']?.toString() ??
            'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-android-armeabi-v7a.apk';
      } else if (abi == 'x86_64') {
        directUrl = assets?['android_x86_64']?.toString() ??
            assets?['android']?.toString() ??
            'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-android-x86_64.apk';
      } else {
        directUrl = assets?['android']?.toString() ??
            'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-android.apk';
      }
    } else if (isWindows) {
      directUrl = assets?['windows']?.toString() ??
          'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-windows-x64.zip';
    } else if (isMacOS) {
      directUrl = assets?['macos']?.toString() ??
          'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-macos.zip';
    } else if (isLinux) {
      directUrl = assets?['linux']?.toString() ??
          'https://github.com/nanguaguag/yibubang/releases/download/v$version/yibubang-v$version-linux-x64.tar.gz';
    } else {
      directUrl = updateData['latest_app_url']?.toString() ??
          'https://github.com/nanguaguag/yibubang/releases/';
    }

    return directUrl;
  }

  /// 下载安装包并在完成后拉起安装程序
  Future<void> downloadAndInstall({
    required Map<String, dynamic> updateData,
    required void Function(int received, int? total) onProgress,
  }) async {
    final rawUrl = resolvePlatformDownloadUrl(
      updateData,
      buildNumber: _cachedBuildNumber,
    );
    final acceleratedUrl = await GitHubProxyConfig.resolveDownloadUrl(rawUrl);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(acceleratedUrl));
      request.headers.addAll(GitHubProxyConfig.defaultHeaders);
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('下载失败：HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      final uriPath = Uri.parse(rawUrl).path;
      final extension = p.extension(uriPath);
      final rawBaseName = p.basename(uriPath);
      final fileName = rawBaseName.isNotEmpty
          ? rawBaseName
          : 'yibubang_v${updateData['latest_app']}$extension';

      Directory tempDir;
      if (Platform.isAndroid) {
        tempDir = await getTemporaryDirectory();
      } else {
        tempDir = (await getDownloadsDirectory()) ??
            (await getApplicationDocumentsDirectory());
      }

      final filePath = p.join(tempDir.path, fileName);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      var received = 0;
      onProgress(0, contentLength);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, contentLength);
      }
      await sink.flush();
      await sink.close();

      // 拉起安装程序或打开下载的文件
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        debugPrint('[AppUpdateService] 拉起安装返回结果: ${result.message}');
      }
    } finally {
      client.close();
    }
  }

  /// 弹出统一的应用更新对话框（包含「取消」、「应用内下载」、「浏览器打开」三个按钮）
  Future<void> showUpdateDialog(
    BuildContext context,
    Map<String, dynamic> updateData,
  ) async {
    final latestVersion = updateData['latest_app'] ?? '';
    final updateInfo = updateData['update_info']?.toString() ?? '发现新版本，请及时更新。';
    final browserUrl = updateData['latest_app_url']?.toString() ??
        'https://github.com/nanguaguag/yibubang/releases/';

    final targetAbi = Platform.isAndroid
        ? detectAndroidAbi(buildNumber: _cachedBuildNumber)
        : null;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        bool isDownloading = false;
        double progress = 0.0;
        String downloadBtnText =
            targetAbi != null ? '应用内下载 ($targetAbi)' : '应用内下载';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('应用更新 (v$latestVersion)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(updateInfo),
                    if (targetAbi != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.memory,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '适配架构包: $targetAbi',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isDownloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                          value: progress > 0 ? progress : null),
                      const SizedBox(height: 6),
                      Text(
                        '下载进度: ${(progress * 100).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                // 按钮 1：取消
                TextButton(
                  onPressed: isDownloading
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消'),
                ),
                // 按钮 2：应用内下载 (带 0% -> 100% 动态变化)
                ElevatedButton(
                  onPressed: isDownloading
                      ? null
                      : () async {
                          setDialogState(() {
                            isDownloading = true;
                            progress = 0.0;
                            downloadBtnText = '0%';
                          });

                          try {
                            await downloadAndInstall(
                              updateData: updateData,
                              onProgress: (received, total) {
                                if (total != null && total > 0) {
                                  final p = received / total;
                                  setDialogState(() {
                                    progress = p.clamp(0.0, 1.0);
                                    downloadBtnText =
                                        '${(progress * 100).toInt()}%';
                                  });
                                }
                              },
                            );
                            setDialogState(() {
                              downloadBtnText = '100% (拉起安装)';
                              isDownloading = false;
                            });
                          } catch (e) {
                            debugPrint('[AppUpdateService] 应用内下载异常: $e');
                            setDialogState(() {
                              isDownloading = false;
                              downloadBtnText = '重试下载';
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('下载失败：$e')),
                              );
                            }
                          }
                        },
                  child: Text(downloadBtnText),
                ),
                // 按钮 3：浏览器打开
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogCtx).pop();
                    final uri = Uri.parse(browserUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  child: const Text('浏览器打开'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
