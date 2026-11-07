import 'package:flutter/material.dart';

import '../services/bank_creation_service.dart';
import 'common/info_card.dart';

/// Selection covers complete subtrees. Only fully selected parents enter the
/// service's selectedRoots contract; a mixed parent cannot include skipped leaves.
class BankIdentityTree extends StatelessWidget {
  const BankIdentityTree({
    super.key,
    required this.nodes,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final List<BankIdentityNode> nodes;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  bool _hasSelection(BankIdentityNode node) =>
      selected.contains(node.id) || node.children.any(_hasSelection);

  bool? _value(BankIdentityNode node) => selected.contains(node.id)
      ? true
      : node.children.any(_hasSelection)
      ? null
      : false;

  void _toggle(BankIdentityNode node) {
    final next = {...selected};
    final include = _value(node) != true;
    void setSubtree(BankIdentityNode current) {
      if (include) {
        next.add(current.id);
      } else {
        next.remove(current.id);
      }
      current.children.forEach(setSubtree);
    }

    void updateParents(BankIdentityNode current) {
      current.children.forEach(updateParents);
      if (current.children.isEmpty) return;
      if (current.children.every((child) => next.contains(child.id))) {
        next.add(current.id);
      } else {
        next.remove(current.id);
      }
    }

    setSubtree(node);
    nodes.forEach(updateParents);
    onChanged(next);
  }

  Widget _node(BuildContext context, BankIdentityNode node) {
    final checkbox = CheckboxListTile(
      key: ValueKey('bank-identity-${node.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Flexible(
            child: Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(node.id),
            labelStyle: Theme.of(context).textTheme.labelSmall,
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ],
      ),
      value: _value(node),
      tristate: node.children.isNotEmpty,
      onChanged: enabled ? (_) => _toggle(node) : null,
    );
    if (node.children.isEmpty) return checkbox;
    return ExpansionTile(
      key: PageStorageKey('create-identity-${node.id}'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.only(right: 8),
      childrenPadding: const EdgeInsets.only(left: 16),
      maintainState: true,
      title: checkbox,
      children: node.children.map((child) => _node(context, child)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      InfoCard(children: nodes.map((node) => _node(context, node)).toList());
}
