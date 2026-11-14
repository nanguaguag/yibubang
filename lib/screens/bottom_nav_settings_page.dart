import 'package:flutter/material.dart';
import '../models/bottom_nav_config.dart';
import '../widgets/info_hint_banner.dart';

/// 底栏导航项排序与显隐设置页面
class BottomNavSettingsPage extends StatefulWidget {
  const BottomNavSettingsPage({super.key});

  @override
  State<BottomNavSettingsPage> createState() => _BottomNavSettingsPageState();
}

class _BottomNavSettingsPageState extends State<BottomNavSettingsPage> {
  List<BottomNavItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await BottomNavConfig.loadConfig();
    if (mounted) {
      setState(() {
        _items = List.from(list);
        _loading = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    await BottomNavConfig.saveConfig(_items);
  }

  void _onToggle(BottomNavItem item, bool value) async {
    if (item.id == 'profile' && !value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('「我的」页面包含设置入口，不可隐藏'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 至少保留两个页面（Material 3 NavigationBar 原生要求至少 2 个 Destination）
    final enabledCount = _items.where((i) => i.enabled).length;
    if (!value && enabledCount <= 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('底栏导航至少需要保留 2 个页面'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      item.enabled = value;
    });
    await BottomNavConfig.saveConfig(_items);
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要将底栏页面顺序与显隐恢复为默认状态吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await BottomNavConfig.resetToDefault();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复默认底栏设置')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('底栏设置'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: InfoHintBanner(
                    message: '长按并拖动右侧手柄可调整底栏显示顺序；使用开关可按需隐藏底栏 Tab（至少保留 2 个）。',
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _items.length,
                    // ignore: deprecated_member_use
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final enabledCount = _items.where((i) => i.enabled).length;
                      final isProfile = item.id == 'profile';
                      final isOnlyEnabled = item.enabled && enabledCount <= 2;

                      return Card(
                        key: ValueKey(item.id),
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        color: scheme.surface,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Icon(
                            item.selectedIcon,
                            color: item.enabled
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: item.enabled
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              if (isProfile) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '常驻',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            isProfile ? '个人中心、账号与偏好设置（包含设置入口，不可隐藏）' : item.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: item.enabled,
                                onChanged: (isProfile || isOnlyEnabled)
                                    ? null
                                    : (val) => _onToggle(item, val),
                              ),
                              const SizedBox(width: 4),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
