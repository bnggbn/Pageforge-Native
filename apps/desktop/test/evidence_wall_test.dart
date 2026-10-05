import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/evidence/evidence_wall_view_model.dart';
import 'package:pageforge/features/evidence/evidence_canvas.dart';
import 'package:pageforge/features/evidence/evidence_card.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

void seed(FakeRepository repo, int count) {
  repo.data['revisions'][0]['notes'] = [
    for (var i = 0; i < count; i++)
      {
        'id': '40000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
        'body': '想法 $i',
        'quote': '引用 $i',
        'location': '全文筆記',
        'createdAt': '2026-10-05T00:00:00Z',
      },
  ];
}

void main() {
  test(
    'wall positions and edges persist; failed save retains local state',
    () async {
      final repo = FakeRepository();
      seed(repo, 2);
      final wall = EvidenceWallViewModel(
        repo,
        await repo.load(repo.data['id'] as String),
        {},
      );
      await wall.load();
      final a = wall.cards[0]['noteId'] as String,
          b = wall.cards[1]['noteId'] as String;
      wall.move(a, 180, 240);
      wall.beginLink(a);
      wall.connect(b);
      await wall.flush();
      final next = EvidenceWallViewModel(
        repo,
        await repo.load(repo.data['id'] as String),
        {},
      );
      await next.load();
      expect(next.card(a)!['x'], 180);
      expect(next.edges.single['from'], a);
      repo.failWall = true;
      next.move(a, 500, 600);
      await expectLater(next.flush(), throwsException);
      expect(next.card(a)!['x'], 500);
      expect(next.dirty, true);
      expect(repo.savedWall!['cards'][0]['x'], 180);
      repo.failWall = false;
      await next.flush();
      expect(next.dirty, false);
      wall.dispose();
      next.dispose();
    },
  );
  testWidgets('drag cards and pins; visible cards are culled', (tester) async {
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
            builder: (context, _) =>
                EvidenceCanvas(model: wall, onOpen: (_) {}, onReveal: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EvidenceCard).evaluate().length, lessThan(30));
    final a = wall.cards[0]['noteId'] as String,
        b = wall.cards[1]['noteId'] as String;
    await tester.drag(find.byKey(ValueKey('move-$a')), const Offset(70, 60));
    await tester.pumpAndSettle();
    expect(wall.card(a)!['x'], closeTo(110, .1));
    expect(wall.card(a)!['y'], closeTo(100, .1));
    final from = tester.getCenter(find.byKey(ValueKey('pin-$a'))),
        to = tester.getCenter(find.byKey(ValueKey('pin-$b')));
    await tester.dragFrom(from, to - from);
    await tester.pumpAndSettle();
    expect(wall.edges, hasLength(1));
    await wall.flush();
    expect(repo.savedWall!['edges'], hasLength(1));
    await tester.pumpWidget(const SizedBox());
    wall.dispose();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
