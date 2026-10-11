import 'package:flutter/material.dart';
import 'package:yibubang/common/app_shapes.dart';

/// Base tile with padding and optional InkWell tap.
class BaseTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const BaseTile({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: child,
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        child: tile,
      );
    }
    return tile;
  }
}

/// Icon container (36x36, rounded, primary tint).
class TileIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const TileIcon({super.key, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final primaryColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppShapes.medium),
      ),
      child: Icon(icon, color: primaryColor, size: 20),
    );
  }
}

/// Common tile: icon + label + optional value + optional trailing.
class IconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? value;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;

  const IconTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.value,
    this.trailing,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BaseTile(
      onTap: onTap,
      child: Row(
        children: [
          TileIcon(icon: icon, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(color: labelColor),
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (trailing != null) ...[
            if (value != null) const SizedBox(width: 8),
            trailing!,
          ],
          if (onTap != null && trailing == null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ],
      ),
    );
  }
}