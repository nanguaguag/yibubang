import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/question_bank_repository.dart';
import 'ykb_bank_smart_sync_service.dart';
import 'ykb_bank_sync_service.dart';
import 'ykb_pull_service.dart';

enum CourseSyncAction {
  smart('smart', '智能增量同步题库', Icons.auto_awesome_outlined),
  records('records', '拉取医考帮做题记录', Icons.cloud_download_outlined),
  rebuild('rebuild', '全量重建题库', Icons.download_for_offline_outlined);

  const CourseSyncAction(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
  String get preferenceKey => 'course_sync_button_$id';
}

class CourseSyncActions extends ChangeNotifier {
  static final instance = CourseSyncActions();
  final Map<CourseSyncAction, bool> _visible = {};
  bool busy = false;

  bool isVisible(CourseSyncAction action) => _visible[action] ?? true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final action in CourseSyncAction.values) {
      _visible[action] = prefs.getBool(action.preferenceKey) ?? true;
    }
    notifyListeners();
  }

  Future<void> setVisible(CourseSyncAction action, bool visible) async {
    await (await SharedPreferences.getInstance()).setBool(
      action.preferenceKey,
      visible,
    );
    _visible[action] = visible;
    notifyListeners();
  }

  Future<void> run(BuildContext context, CourseSyncAction action) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<String>('正在准备…');
    DialogRoute<void>? dialog;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('loggedin') ?? false)) {
        messenger.showSnackBar(const SnackBar(content: Text('请先登录医考帮')));
        return;
      }
      final repository = QuestionBankRepository();
      final bank = await repository.find(await repository.activeBankId());
      if (!context.mounted) return;
      if (bank == null || !bank.isInstalled) {
        messenger.showSnackBar(const SnackBar(content: Text('请先启用并下载题库')));
        return;
      }
      if (action == CourseSyncAction.rebuild) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('全量重建题库？'),
            content: Text(
              '将重新下载并替换「${bank.name}」的全部题目，耗时较长。'
              '本地作答记录会保留。通常使用智能增量同步即可。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('开始重建'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      dialog = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(action.label),
            content: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, text, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(text),
                ],
              ),
            ),
          ),
        ),
      );
      navigator.push(dialog);
      String message;
      switch (action) {
        case CourseSyncAction.records:
          progress.value = '正在拉取记录；本地已作答的题目会保留…';
          final result = await YkbPullService.pullForBank(
            bank,
            pacing: SyncPacing(
              jitterEnabled: prefs.getBool('sync_ykb_jitter_enabled') ?? false,
              pacingEnabled: prefs.getBool('sync_ykb_pacing_enabled') ?? false,
            ),
          );
          message = result.summary;
        case CourseSyncAction.smart:
          progress.value = '正在检查远端章节，只处理有变化的章节…';
          final result = await YkbBankSmartSyncService.instance.run(
            bank: bank,
            manual: true,
            forceManifest: true,
            maxChapters: 16,
          );
          message = result.summary;
        case CourseSyncAction.rebuild:
          await YkbBankSyncService.syncBank(
            bank,
            pacing: SyncPacing(
              jitterEnabled: prefs.getBool('sync_ykb_jitter_enabled') ?? false,
              pacingEnabled: prefs.getBool('sync_ykb_pacing_enabled') ?? false,
            ),
            onProgress: (stage, done, total) =>
                progress.value = '$stage（$done/$total）',
          );
          message = '题库「${bank.name}」重建完成';
      }
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } catch (error) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${action.label}失败：$error')),
        );
      }
    } finally {
      if (dialog != null && dialog.isActive && navigator.mounted) {
        navigator.removeRoute(dialog);
        await dialog.completed;
      }
      progress.dispose();
      busy = false;
      notifyListeners();
    }
  }
}
