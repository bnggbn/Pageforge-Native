import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/evidence/evidence_wall_view_model.dart';
import 'package:pageforge/features/evidence/evidence_topic_bar.dart';
import 'package:pageforge/features/evidence/evidence_canvas.dart';
import 'package:pageforge/features/evidence/evidence_card.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';
import 'package:pageforge/features/evidence/evidence_topics.dart';
import 'evidence_wall_test.dart' show seed;

void main() {
  test('integer coordinates loaded from Go reserve their grid positions', () {
    final topic = {
      'id': allEvidenceTopic,
      'name': '全部線索',
      'cards': [
        {'noteId': 'first', 'x': 40, 'y': 40},
      ],
      'edges': <Map<String, dynamic>>[],
    };
    final result = reconcileTopic(topic, {'first', 'second'}, 6400, 6400, 500);
    final cards = result['cards'] as List;
    expect(cards[0]['x'], 40);
    expect(cards[1]['x'], 360);
  });
  test(
    'topic membership, layout and red lines are independent and survive reopening',
    () async {
      final repo = FakeRepository();
      seed(repo, 3);
      final wall = EvidenceWallViewModel(
        repo,
        await repo.load(repo.data['id'] as String),
        {},
      );
      await wall.load();
      final all = wall.activeTopicId;
      final a = wall.cards[0]['noteId'] as String,
          b = wall.cards[1]['noteId'] as String;
      wall.move(a, 100, 100);
      wall.beginLink(a);
      wall.connect(b);
      expect(wall.createTopic('人物關係'), true);
      final people = wall.activeTopicId;
      expect(wall.cards, isEmpty);
      expect(wall.edges, isEmpty);
      expect(wall.setTopicNotes({a, b}), true);
      wall.move(a, 500, 300);
      wall.beginLink(a);
      wall.connect(b);
      expect(wall.createTopic('待查證'), true);
      final questions = wall.activeTopicId;
      expect(wall.setTopicNotes({a}), true);
      wall.move(a, 850, 200);
      wall.selectTopic(people);
      expect(wall.card(a)!['x'], 500);
      expect(wall.edges, hasLength(1));
      expect(wall.renameTopic('人物與動機'), true);
      expect(wall.createTopic('人物與動機'), false);
      wall.selectTopic(all);
      expect(wall.card(a)!['x'], 100);
      expect(wall.edges, hasLength(1));
      wall.selectTopic(questions);
      expect(wall.edges, isEmpty);
      await wall.flush();
      final reopened = EvidenceWallViewModel(
        repo,
        await repo.load(repo.data['id'] as String),
        {},
      );
      await reopened.load();
      expect(reopened.activeTopicId, questions);
      expect(reopened.card(a)!['x'], 850);
      reopened.selectTopic(people);
      reopened.setTopicNotes({a});
      expect(reopened.edges, isEmpty);
      reopened.selectTopic(all);
      expect(reopened.edges, hasLength(1));
      reopened.selectTopic(questions);
      reopened.deleteTopic();
      expect(reopened.topics, hasLength(2));
      expect(reopened.notes, hasLength(3));
      reopened.focus(a);
      expect(reopened.cards.any((c) => c['noteId'] == a), true);
      await reopened.flush();
      wall.dispose();
      reopened.dispose();
    },
  );
  testWidgets(
    'create a named topic and pick only relevant notes through the UI',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      seed(repo, 3);
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
              builder: (context, _) => Column(
                children: [
                  EvidenceTopicBar(model: wall, disabled: false),
                  Expanded(
                    child: EvidenceCanvas(
                      key: ValueKey(wall.activeTopicId),
                      model: wall,
                      onOpen: (_) {},
                      onReveal: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增主題'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('evidence-topic-name')),
        '人物關係',
      );
      await tester.tap(find.text('保存主題'));
      await tester.pumpAndSettle();
      expect(wall.cards, isEmpty);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('保存選擇（1）'));
      await tester.pumpAndSettle();
      expect(find.byType(EvidenceCard), findsOneWidget);
      expect(wall.activeTopicName, '人物關係');
      await tester.tap(find.text('挑選線索'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('evidence-note-search')),
        '想法 2',
      );
      await tester.pump();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(wall.cards, hasLength(1));
      expect(tester.takeException(), isNull);
      await wall.flush();
      await tester.pumpWidget(const SizedBox());
      wall.dispose();
      await tester.pumpAndSettle();
    },
  );
}
