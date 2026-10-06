import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/evidence/evidence_card.dart';
import 'package:pageforge/ui/theme.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('press, tap and drag across the card body with $kind', (
      tester,
    ) async {
      var opened = 0, starts = 0, ends = 0, cancelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 240,
                child: EvidenceCard(
                  note: const {
                    'id': 'test',
                    'body': '卡片裡的想法',
                    'quote': '引用的段落',
                    'location': '全文筆記',
                  },
                  number: 1,
                  selected: false,
                  onTap: () => opened++,
                  onReveal: () {},
                  onDragStart: (_) => starts++,
                  onDragUpdate: (_) {},
                  onDragEnd: () => ends++,
                  onDragCancel: () => cancelled++,
                  onPinTap: () {},
                  onPinStart: () {},
                  onPinUpdate: (_) {},
                  onPinEnd: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final material = find
          .descendant(
            of: find.byType(EvidenceCard),
            matching: find.byType(Material),
          )
          .first;
      final origin = tester.getTopLeft(find.byType(EvidenceCard));
      final body = tester.getCenter(find.text('卡片裡的想法'));
      final press = await tester.startGesture(body, kind: kind);
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(material).elevation, 16);
      expect(find.byIcon(Icons.open_with), findsOneWidget);
      expect(starts, 0, reason: 'holding should lift without moving the card');
      expect(tester.getTopLeft(find.byType(EvidenceCard)), origin);
      await press.up();
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(ends, 0);
      expect(tester.widget<Material>(material).elevation, 2);

      // The empty margin beside the body also belongs to the drag area.
      final surface = tester.getRect(find.byKey(const ValueKey('move-test')));
      final drag = await tester.startGesture(
        Offset(surface.right - 3, surface.center.dy),
        kind: kind,
      );
      await drag.moveBy(const Offset(50, 40));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(tester.widget<Material>(material).elevation, 16);
      await drag.up();
      await tester.pumpAndSettle();
      expect(ends, 1);
      expect(opened, 1, reason: 'dragging must not also open the note');
      expect(tester.widget<Material>(material).elevation, 2);

      final cancel = await tester.startGesture(body, kind: kind);
      await cancel.moveBy(const Offset(50, 0));
      await tester.pump();
      await cancel.cancel();
      await tester.pumpAndSettle();
      expect(cancelled, greaterThan(0));
      expect(tester.widget<Material>(material).elevation, 2);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pins and return button keep their own gestures; reduced motion',
    (tester) async {
      var revealed = 0, pinTaps = 0, pinStarts = 0, cardStarts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  height: 240,
                  child: EvidenceCard(
                    note: const {
                      'id': 'test',
                      'body': '卡片裡的想法',
                      'quote': '',
                      'location': '全文筆記',
                    },
                    number: 1,
                    selected: false,
                    onTap: () {},
                    onReveal: () => revealed++,
                    onDragStart: (_) => cardStarts++,
                    onDragUpdate: (_) {},
                    onDragEnd: () {},
                    onDragCancel: () {},
                    onPinTap: () => pinTaps++,
                    onPinStart: () => pinStarts++,
                    onPinUpdate: (_) {},
                    onPinEnd: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final material = find
          .descendant(
            of: find.byType(EvidenceCard),
            matching: find.byType(Material),
          )
          .first;
      await tester.tap(find.text('回到原文'));
      await tester.tap(find.byKey(const ValueKey('pin-test')));
      await tester.drag(
        find.byKey(const ValueKey('pin-test')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(revealed, 1);
      expect(pinTaps, 1);
      expect(pinStarts, 1);
      expect(cardStarts, 0);
      expect(tester.widget<Material>(material).elevation, 2);

      final secondary = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('move-test'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(material).elevation, 2);
      await secondary.up();
      final held = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('move-test'))),
      );
      await tester.pump();
      expect(tester.widget<Material>(material).elevation, 16);
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 1);
      expect(scale.duration, Duration.zero);
      await held.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
