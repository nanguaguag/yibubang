import 'dart:convert';
import 'dart:io';

/// 替换日志只描述固定的用户库相邻文件；未完成的替换在开库前恢复旧快照。
/// 日志删除为提交点。恢复过程保留 backup，进程再次中断仍可重试。
Future<void> recoverUserDatabaseReplacement(String path) async {
  final journal = File('$path.replace.json');
  if (!await journal.exists()) return;
  final state =
      jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
  final backup = File('$path.backup');
  final current = File(path);
  if (state['had_original'] == true) {
    if (await backup.exists()) {
      final restoring = await backup.copy('$path.restore');
      final handle = await restoring.open(mode: FileMode.append);
      await handle.flush();
      await handle.close();
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      await restoring.rename(path);
    } else if (!await current.exists()) {
      throw StateError('用户库替换恢复失败：原库与备份均缺失');
    }
  } else {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }
  await journal.delete();
}
