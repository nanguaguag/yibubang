import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../common/app_shapes.dart';
import '../models/bank_identity_selection.dart';
import '../services/bank_creation_service.dart';

/// Only visible rows are mounted; collapsed descendants retain selection in the
/// model rather than thousands of offstage widgets and animation controllers.
class BankIdentityTree extends StatefulWidget {
  const BankIdentityTree({
    super.key,
    required this.nodes,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.header,
  });
  final List<BankIdentityNode> nodes;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final Widget? header;
  @override
  State<BankIdentityTree> createState() => _BankIdentityTreeState();
}

class _BankIdentityTreeState extends State<BankIdentityTree> {
  late BankIdentitySelection _selection;
  final _expanded = <String>{};
  final _rows = <(BankIdentityNode, int)>[];
  @override
  void initState() {
    super.initState();
    _selection = BankIdentitySelection(widget.nodes, widget.selected);
    _flatten();
  }

  @override
  void didUpdateWidget(BankIdentityTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes)) {
      _selection.dispose();
      _selection = BankIdentitySelection(widget.nodes, widget.selected);
      _flatten();
    } else if (!setEquals(widget.selected, _selection.selected)) {
      _selection.replace(widget.selected);
    }
  }

  void _flatten() {
    _rows.clear();
    void append(BankIdentityNode node, int depth) {
      _rows.add((node, depth));
      if (_expanded.contains(node.id)) {
        for (final child in node.children) {
          append(child, depth + 1);
        }
      }
    }

    for (final node in widget.nodes) {
      append(node, 0);
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Widget _row(BuildContext context, int index) {
    final (node, depth) = _rows[index];
    final theme = Theme.of(context);
    final label = Row(
      children: [
        Flexible(
          child: Text(node.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Chip(
          label: Text(node.id),
          labelStyle: theme.textTheme.labelSmall,
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ],
    );
    final first = index == 0, last = index == _rows.length - 1;
    final radius = BorderRadius.vertical(
      top: first ? Radius.circular(AppShapes.largeIncreased) : Radius.zero,
      bottom: last ? Radius.circular(AppShapes.largeIncreased) : Radius.zero,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.only(left: (depth * 16.0).clamp(0, 64)),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<bool?>(
                  valueListenable: _selection.value(node.id),
                  child: label,
                  builder: (_, value, child) => CheckboxListTile(
                    key: ValueKey('bank-identity-${node.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: child,
                    value: value,
                    tristate: node.children.isNotEmpty,
                    onChanged: widget.enabled
                        ? (_) {
                            _selection.toggle(node.id);
                            widget.onChanged(_selection.selected);
                          }
                        : null,
                  ),
                ),
              ),
              if (node.children.isNotEmpty)
                IconButton(
                  key: ValueKey('bank-identity-expand-${node.id}'),
                  tooltip: _expanded.contains(node.id)
                      ? '收起${node.name}'
                      : '展开${node.name}',
                  icon: Icon(
                    _expanded.contains(node.id)
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  onPressed: () => setState(() {
                    if (!_expanded.add(node.id)) {
                      _expanded.remove(node.id);
                    }
                    _flatten();
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const PageStorageKey('bank-identity-scroll'),
    padding: const EdgeInsets.all(16),
    itemCount: _rows.length + (widget.header == null ? 0 : 1),
    itemBuilder: (context, index) => widget.header != null && index == 0
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: widget.header,
          )
        : _row(context, index - (widget.header == null ? 0 : 1)),
  );
}
