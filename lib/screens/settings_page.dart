import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/adaptive_route.dart';
import '../common/app_strings.dart';
import '../db/data_transfer.dart';
import '../db/record_sync_service.dart';
import '../repositories/question_search_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/note_service.dart';
import '../services/ykb_sync_service.dart';
import '../widgets/common/info_card.dart';
import '../widgets/common/styled_tile.dart';
import '../widgets/theme_controller.dart';
import 'about_page.dart';
import 'cloud_sync_page.dart';
import 'developer_page.dart';
import 'question_sections_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SharedPreferences _prefs;
  bool _loaded = false;

  // 通用设置
  bool acceptUpdate = true;
  bool autoResume = false;
  int mode = 0; // 默认刷题模式，对应 AppStrings.modesList
  double fontScale = 1.0; // 刷题字号缩放比例
  bool developerModeEnabled = false;

  // 医考帮云端同步设置
  bool syncAnswersToYkb = true;
  bool syncCutToYkb = true;
  bool syncNotesToYkb = true;
  bool syncRedoToYkb = true;

  static const String keyAcceptUpdate = 'accept_update';
  static const String keySyncQuestionBank = 'sync_question_bank';
  static const String keyAutoResume = 'autoResume';
  static const String keySyncAnswersToYkb = 'sync_answers_to_ykb';
  static const String keySyncCutToYkb = 'sync_cut_to_ykb';
  static const String keySyncNotesToYkb = 'sync_notes_to_ykb';
  static const String keySyncRedoToYkb = 'sync_redo_to_ykb';

  static const List<double> _fontScales = [0.85, 1.0, 1.15, 1.3];
  static const List<String> _fontScaleLabels = ['小', '标准', '大', '特大'];

  String _currentVersion = '0.0.0';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();

    acceptUpdate = _prefs.getBool(keyAcceptUpdate) ?? true;
    autoResume = _prefs.getBool(keyAutoResume) ?? false;
    syncNotesToYkb = _prefs.getBool(keySyncNotesToYkb) ?? true;
    syncCutToYkb = _prefs.getBool(keySyncCutToYkb) ?? true;
    syncRedoToYkb = _prefs.getBool(keySyncRedoToYkb) ?? true;
    syncAnswersToYkb = _prefs.getBool(keySyncAnswersToYkb) ??
        _prefs.getBool('questionUpload') ??
        _prefs.getBool(keySyncQuestionBank) ??
        true;
    mode = _prefs.getInt('mode') ?? 0;
    fontScale = _normalizeFontScale(_prefs.getDouble('fontScale') ?? 1.0);
    developerModeEnabled =
        _prefs.getBool(AppStrings.keyDeveloperModeEnabled) ?? false;
    await CloudSyncService.instance.init();

    if (!mounted) return;
    setState(() {
      _loaded = true;
    });
  }

  double _normalizeFontScale(double value) {
    double closest = _fontScales.first;
    double minDiff = (_fontScales.first - value).abs();
    for (final s in _fontScales) {
      final diff = (s - value).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = s;
      }
    }
    return closest;
  }

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  // ------------------------------------------------------------------
  // 重新统计
  // ------------------------------------------------------------------
  Future<void> _confirmRebuild() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("重新统计"),
          content: const Text(
            "由于开发者之前对数据库的了解非常稀烂，"
            "2.0.0版本的刷题数出现了各种各样的问题（详见issue#9）"
            "如果出现章节正确数和错误数不正确，请点击下方的确认按钮，统计完后请重启本应用。"
            "确认按钮也会同步修复统计页缺失的历史刷题记录（作答时间将平均分摊到一年内）。",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await rebuildQuestionCount();
                  await repairActivities();
                } catch (error, stack) {
                  debugPrint('[重新统计] 异常: $error');
                  debugPrint('$stack');
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('做题数量与统计已更新'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: const Text("确认"),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // 做题记录导出 / 导入
  // ------------------------------------------------------------------
  Future<void> _exportRecords() async {
    try {
      final path = await RecordSyncService.exportRecords();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path == null ? '导出已取消' : '已导出到：$path'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[record-sync] 导出异常: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _importRecords() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入做题记录',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // 用户取消

      var bytes = result.files.single.bytes;
      if (bytes == null) {
        final path = result.files.single.path;
        if (path == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取所选文件')),
          );
          return;
        }
        bytes = await File(path).readAsBytes();
      }
      if (!mounted) return;

      final action = await _askImportMode();
      if (action == null || !mounted) return;

      if (action == 'replace') {
        await RecordSyncService.importReplace(bytes);
      } else {
        await RecordSyncService.importMerge(bytes);
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'replace' ? '已替换做题记录' : '已合并做题记录'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[record-sync] 导入异常: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<String?> _askImportMode() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入方式'),
        content: const Text(
          '替换：用导入文件完全覆盖本地做题记录。\n'
          '合并：将导入的做题记录并入本地（本地已做的题优先保留）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('merge'),
            child: const Text('合并'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('replace'),
            child: const Text('替换'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 清空搜索历史 / 清空全部做题记录
  // ------------------------------------------------------------------
  Future<void> _clearSearchHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空所有搜索历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await QuestionSearchRepository().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('搜索历史已清空')),
    );
  }

  Future<void> _clearAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部做题记录'),
        content: const Text(
          '将删除所有题目的作答状态、收藏、斩题记录以及刷题流水，且无法恢复。确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await clearAllRecords();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空全部做题记录')),
    );
  }

  // ------------------------------------------------------------------
  // 手动检查更新
  // ------------------------------------------------------------------
  Future<void> _checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;

      final response = await http
          .get(
            Uri.parse('https://files.melonhu.cn/yibubang/yibubang_update.json'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw HttpException('更新清单请求失败：HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('更新清单格式不正确');
      }
      if (!mounted) return;

      final latest = decoded['latest_app']?.toString() ?? _currentVersion;
      if (_compareVersions(latest, _currentVersion) > 0) {
        _showUpdateDialog(decoded);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    } catch (e) {
      debugPrint('[check-update] 检查更新异常: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateData) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('应用更新'),
        content: Text(updateData['update_info']?.toString() ?? '检测到新版本，请及时更新'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final url = updateData['latest_app_url']?.toString() ??
                  'https://github.com/nanguaguag/yibubang/releases/';
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  int _compareVersions(String v1, String v2) {
    final a = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final b = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av > bv ? 1 : -1;
    }
    return 0;
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          const _SectionTitle(title: '外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildThemeSelector(),
          ),
          const SizedBox(height: 10),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.view_quilt_outlined,
                label: '题目页板块设置',
                value: '排序与显隐',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    adaptivePageRoute(
                      builder: (context) => const QuestionSectionsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _SectionTitle(title: '通用'),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.system_update_alt,
                label: '接受应用更新',
                trailing: Switch(
                  value: acceptUpdate,
                  onChanged: (v) {
                    setState(() => acceptUpdate = v);
                    _setBool(keyAcceptUpdate, v);
                  },
                ),
              ),
              IconTile(
                icon: Icons.play_circle_outline,
                label: '启动自动继续上次进度',
                trailing: Switch(
                  value: autoResume,
                  onChanged: (v) {
                    setState(() => autoResume = v);
                    _setBool(keyAutoResume, v);
                  },
                ),
              ),
              IconTile(
                icon: Icons.style,
                label: '默认刷题模式',
                trailing: DropdownButton<int>(
                  value: mode,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => mode = v);
                    _prefs.setInt('mode', v);
                  },
                  items: [
                    for (var i = 0; i < AppStrings.modesList.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(AppStrings.modesList[i]),
                      ),
                  ],
                ),
              ),
              IconTile(
                icon: Icons.format_size,
                label: '刷题字号',
                trailing: DropdownButton<double>(
                  value: fontScale,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => fontScale = v);
                    _prefs.setDouble('fontScale', v);
                  },
                  items: [
                    for (var i = 0; i < _fontScales.length; i++)
                      DropdownMenuItem(
                        value: _fontScales[i],
                        child: Text(_fontScaleLabels[i]),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _SectionTitle(title: '医考帮'),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.cloud_upload_outlined,
                label: '做题同步到医考帮',
                trailing: Switch(
                  value: syncAnswersToYkb,
                  onChanged: (v) {
                    setState(() => syncAnswersToYkb = v);
                    _setBool(keySyncAnswersToYkb, v);
                    _setBool(keySyncQuestionBank, v);
                    _setBool('questionUpload', v);
                    if (v) {
                      YkbSyncService.instance.processQueue();
                    }
                  },
                ),
              ),
              IconTile(
                icon: Icons.content_cut,
                label: '同步斩题到医考帮',
                trailing: Switch(
                  value: syncCutToYkb,
                  onChanged: (v) {
                    setState(() => syncCutToYkb = v);
                    _setBool(keySyncCutToYkb, v);
                    if (v) {
                      YkbSyncService.instance.processQueue();
                    }
                  },
                ),
              ),
              IconTile(
                icon: Icons.note_alt_outlined,
                label: '同步笔记到医考帮',
                trailing: Switch(
                  value: syncNotesToYkb,
                  onChanged: (v) {
                    setState(() => syncNotesToYkb = v);
                    _setBool(keySyncNotesToYkb, v);
                    if (v) {
                      NoteService.instance.processQueue();
                    }
                  },
                ),
              ),
              IconTile(
                icon: Icons.replay,
                label: '章节重做同步到医考帮',
                //value: '仅整章重做时同步，重做错题不同步',
                trailing: Switch(
                  value: syncRedoToYkb,
                  onChanged: (v) {
                    setState(() => syncRedoToYkb = v);
                    _setBool(keySyncRedoToYkb, v);
                    if (v) {
                      YkbSyncService.instance.processQueue();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _SectionTitle(title: '做题记录'),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.cloud_sync,
                label: '多端做题记录同步',
                value: CloudSyncService.instance.isConfigured ? '已开启' : '未开启',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CloudSyncPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              IconTile(
                icon: Icons.build,
                label: '重新统计',
                onTap: _confirmRebuild,
              ),
              IconTile(
                icon: Icons.ios_share,
                label: '导出做题记录',
                onTap: _exportRecords,
              ),
              IconTile(
                icon: Icons.download,
                label: '导入做题记录',
                onTap: _importRecords,
              ),
              IconTile(
                icon: Icons.history,
                label: '清空搜索历史',
                onTap: _clearSearchHistory,
              ),
              IconTile(
                icon: Icons.delete_forever,
                label: '清空全部做题记录',
                iconColor: colorScheme.error,
                labelColor: colorScheme.error,
                onTap: _clearAllRecords,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _SectionTitle(title: '关于'),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.info_outline,
                label: '关于医不帮',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    adaptivePageRoute(
                      builder: (context) => const AboutPage(),
                    ),
                  );
                  if (mounted) {
                    setState(() {
                      developerModeEnabled =
                          _prefs.getBool(AppStrings.keyDeveloperModeEnabled) ??
                              false;
                    });
                  }
                },
              ),
              if (developerModeEnabled)
                IconTile(
                  icon: Icons.developer_mode,
                  label: '开发者模式',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      adaptivePageRoute(
                        builder: (context) => const DeveloperPage(),
                      ),
                    );
                  },
                ),
              IconTile(
                icon: Icons.system_update,
                label: '检查更新',
                onTap: _checkForUpdate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('浅色'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('深色'),
              icon: Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('跟随系统'),
              icon: Icon(Icons.brightness_auto),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              ThemeController.instance.setTheme(selection.first),
          showSelectedIcon: false,
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
