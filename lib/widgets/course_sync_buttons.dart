import 'package:flutter/material.dart';
import '../services/course_sync_actions.dart';

class CourseSyncButtons extends StatelessWidget {
  const CourseSyncButtons({super.key, this.onCompleted});
  final VoidCallback? onCompleted;

  Future<void> _run(BuildContext context, CourseSyncAction action) async {
    await CourseSyncActions.instance.run(context, action);
    if (context.mounted) onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CourseSyncActions.instance,
    builder: (context, _) {
      final actions = CourseSyncAction.values
          .where(CourseSyncActions.instance.isVisible)
          .toList();
      if (actions.isEmpty) return const SizedBox.shrink();
      if (MediaQuery.sizeOf(context).width < 600) {
        return PopupMenuButton<CourseSyncAction>(
          tooltip: '同步操作',
          enabled: !CourseSyncActions.instance.busy,
          icon: const Icon(Icons.sync),
          onSelected: (action) => _run(context, action),
          itemBuilder: (_) => actions
              .map(
                (action) => PopupMenuItem(
                  value: action,
                  child: Row(
                    children: [
                      Icon(action.icon),
                      const SizedBox(width: 12),
                      Text(action.label),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            IconButton(
              tooltip: action.label,
              icon: Icon(action.icon),
              onPressed: CourseSyncActions.instance.busy
                  ? null
                  : () => _run(context, action),
            ),
        ],
      );
    },
  );
}
