import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/evidence/evidence_canvas.dart';
import 'package:pageforge/features/evidence/evidence_card.dart';
import 'package:pageforge/features/evidence/evidence_wall_view_model.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';
import 'evidence_wall_test.dart' show seed;

void main() {
  for (final scale in [.5, 1.0, 2.0]) {
    testWidgets('card follows rapid pointer updates at zoom $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      seed(repo, 100);
      final wall = EvidenceWallViewModel(
        repo,
        await repo.load(repo.data['id'] as String),
        {},
      );
      await wall.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: wall,
              builder: (_, _) =>
                  EvidenceCanvas(model: wall, onOpen: (_) {}, onReveal: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(
        scale,
        scale,
        1,
      );
      await tester.pumpAndSettle();
      final id = wall.cards[0]['noteId'] as String;
      final card = find.byKey(ValueKey('evidence-card-$id'));
      final before = tester.getTopLeft(card);
      var notifications = 0;
      wall.addListener(() => notifications++);
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('move-$id'))),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveBy(const Offset(20, 0));
      await tester.pump();
      final neighbor = find.byKey(
        ValueKey('evidence-card-40000000-0000-4000-8000-000000000001'),
      );
      final neighborWidget = tester.widget<EvidenceCard>(neighbor);
      await pointer.moveBy(const Offset(10, 7));
      await pointer.moveBy(const Offset(15, 8));
      await pointer.moveBy(const Offset(12, 5));
      await tester.pump();
      final after = tester.getTopLeft(card);
      expect(after.dx - before.dx, closeTo(57, .1));
      expect(after.dy - before.dy, closeTo(20, .1));
      expect(
        notifications,
        0,
        reason: 'pointer updates must not rebuild the whole wall',
      );
      expect(tester.widget<EvidenceCard>(neighbor), same(neighborWidget));
      await tester.pump(const Duration(seconds: 1));
      expect(
        repo.savedWall,
        isNull,
        reason: 'only the released position is persisted',
      );
      await pointer.up();
      await tester.pump();
      expect(wall.card(id)!['x'], closeTo(40 + 57 / scale, .1));
      expect(wall.card(id)!['y'], closeTo(40 + 20 / scale, .1));
      expect(notifications, 1);
      await wall.flush();
      expect(
        repo.savedWall!['topics'][0]['cards'][0]['x'],
        closeTo(40 + 57 / scale, .1),
      );
      await pointer.removePointer();
      final saved = repo.savedWall;
      final released = tester.getTopLeft(card);
      notifications = 0;
      final cancelled = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('move-$id'))),
        kind: PointerDeviceKind.mouse,
      );
      await cancelled.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(tester.getTopLeft(card).dx - released.dx, closeTo(50, .1));
      await cancelled.cancel();
      await tester.pump();
      expect(tester.getTopLeft(card), released);
      expect(notifications, 0);
      expect(repo.savedWall, same(saved));
      await cancelled.removePointer();
      await tester.pumpWidget(const SizedBox());
      wall.dispose();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
