import 'package:flutter/material.dart';

/// 统一风格的信息提示横幅
///
/// 视觉规范：
/// - 背景色：surfaceContainerHighest (alpha: 0.4)
/// - 边框：outlineVariant (alpha: 0.5)，圆角 12px
/// - 图标：Icons.info_outline，尺寸 20px，配色 primary
/// - 文字：正文 13px，配色 onSurfaceVariant，行高 1.35
class InfoHintBanner extends StatelessWidget {
  final String message;
  final Widget? trailing;

  const InfoHintBanner({
    super.key,
    required this.message,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
