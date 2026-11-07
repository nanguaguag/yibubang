import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/services/bank_creation_service.dart';
import 'package:yibubang/widgets/bank_identity_tree.dart';

void main() {
  for (final width in [390.0, 1000.0]) {
    testWidgets(
      'parent selection cascades, mixed selection survives collapse and IDs stay inline at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final nodes = BankIdentityNode.parse([
          {
            'identity_id': '20101',
            'title': '临床期末',
            'children': [
              {'identity_id': '20102', 'title': '大一'},
              {
                'identity_id': '20103',
                'title': '大二',
                'children': [
                  {'identity_id': '20104', 'title': '大二上学期'},
                  {'identity_id': '20105', 'title': '大二下学期'},
                ],
              },
            ],
          },
        ]);
        var selected = <String>{};
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: BankIdentityTree(
                    nodes: nodes,
                    selected: selected,
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              ),
            ),
          ),
        );
        Finder checkbox(String id) => find.byKey(ValueKey('bank-identity-$id'));
        bool? value(String id) =>
            tester.widget<CheckboxListTile>(checkbox(id)).value;
        Finder arrow(String id) => find
            .descendant(
              of: find.byKey(PageStorageKey('create-identity-$id')),
              matching: find.byType(Icon),
            )
            .last;
        await tester.tap(arrow('20101'));
        await tester.pumpAndSettle();
        await tester.tap(arrow('20103'));
        await tester.pumpAndSettle();
        await tester.tap(checkbox('20101'));
        await tester.pump();
        expect(selected, {'20101', '20102', '20103', '20104', '20105'});
        for (final id in selected) {
          expect(value(id), isTrue);
        }
        expect(nodes.single.selectedRoots(selected).map((n) => n.id), [
          '20101',
        ]);

        await tester.tap(checkbox('20105'));
        await tester.pump();
        expect(value('20101'), isNull);
        expect(value('20103'), isNull);
        expect(value('20105'), isFalse);
        expect(nodes.single.selectedRoots(selected).map((n) => n.id), [
          '20102',
          '20104',
        ]);
        await tester.tap(arrow('20103'));
        await tester.pumpAndSettle();
        await tester.tap(arrow('20103'));
        await tester.pumpAndSettle();
        expect(value('20103'), isNull);
        await tester.tap(checkbox('20103'));
        await tester.pump();
        expect(value('20101'), isTrue);
        expect(value('20105'), isTrue);
        await tester.tap(checkbox('20101'));
        await tester.pump();
        expect(selected, isEmpty);

        await tester.tap(checkbox('20102'));
        await tester.pump();
        await tester.tap(checkbox('20104'));
        await tester.pump();
        await tester.tap(checkbox('20105'));
        await tester.pump();
        expect(value('20101'), isTrue);
        expect(nodes.single.selectedRoots(selected).length, 1);
        final tag = find.descendant(
          of: checkbox('20101'),
          matching: find.byType(Chip),
        );
        expect(tester.widget<Chip>(tag).shape, isA<StadiumBorder>());
        expect(
          tester.widget<CheckboxListTile>(checkbox('20101')).subtitle,
          isNull,
        );
        expect(
          tester.getCenter(find.text('临床期末')).dy,
          tester.getCenter(tag).dy,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
