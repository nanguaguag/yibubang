import 'package:flutter/material.dart';

/// Compact, non-interactive labels keep bank metadata below the title hierarchy.
class BankTag extends StatelessWidget {
  const BankTag(this.label, {super.key, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: highlighted
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: highlighted
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
