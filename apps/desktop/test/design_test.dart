import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/design/design_controller.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'package:pageforge/features/design/design_repository.dart';
import 'package:pageforge/features/design/studio_screen.dart';
import 'package:pageforge/features/design/studio_view_model.dart';
import 'package:pageforge/features/library/library_screen.dart';
import 'package:pageforge/ui/design_theme.dart';
import 'package:pageforge/ui/theme.dart';
import 'fake_repository.dart';

class MemoryDesigns implements DesignRepository {
  DesignSnapshot snapshot = DesignSnapshot(DesignDocument.defaults, 'initial');
  int writes = 0;
  bool fail = false;
  @override
  Future<DesignSnapshot> load() async => snapshot;
  @override
  Future<DesignSnapshot> save(
    DesignDocument document,
    String expectedRevision,
  ) async {
    if (fail || expectedRevision != snapshot.revision) {
      throw Exception('conflict');
    }
    writes++;
    final json = document.toJson();
    json['library']['cardWidth'] = document
        .number('library', 'cardWidth')
        .toInt();
    json['library']['gap'] = document.number('library', 'gap').toInt();
    return snapshot = DesignSnapshot(
      DesignDocument.parse(jsonEncode(json)),
      'revision-$writes',
    );
  }
}

void main() {
  test('design codec rejects unknown, oversized and out of range values', () {
    final json = DesignDocument.defaults.toJson();
    json['script'] = 'run()';
    expect(() => DesignDocument.parse(jsonEncode(json)), throwsFormatException);
    expect(
      () => DesignDocument.defaults.change('reader', 'lineHeight', 900),
      throwsFormatException,
    );
    expect(() => DesignDocument.parse(' ' * 16385), throwsFormatException);
    final copy = DesignDocument.defaults.toJson();
    copy['theme']['ink'] = '#ffffff';
    expect(DesignDocument.defaults.get<String>('theme', 'ink'), '#343a32');
  });
  testWidgets(
    'invalid JSON keeps last valid preview; only Apply changes live design',
    (tester) async {
      final repository = MemoryDesigns();
      final live = DesignController(repository);
      await live.load();
      final studio = StudioViewModel(live);
      studio.change('theme', 'accent', '#335577');
      expect(live.document.get<String>('theme', 'accent'), '#a84b36');
      studio.editJson('{');
      await tester.pump(const Duration(milliseconds: 210));
      expect(studio.error, isNotEmpty);
      expect(studio.document.get<String>('theme', 'accent'), '#335577');
      expect(await studio.apply(), false);
      expect(repository.writes, 0);
      studio.editJson(studio.document.source);
      await tester.pump(const Duration(milliseconds: 210));
      repository.fail = true;
      expect(await studio.apply(), false);
      expect(studio.dirty, true);
      expect(live.document.get<String>('theme', 'accent'), '#a84b36');
      repository.fail = false;
      expect(await studio.apply(), true);
      expect(live.document.get<String>('theme', 'accent'), '#335577');
      studio.undo();
      expect(studio.document.get<String>('theme', 'accent'), '#a84b36');
      studio.redo();
      expect(studio.document.get<String>('theme', 'accent'), '#335577');
      studio.dispose();
      live.dispose();
    },
  );
  testWidgets(
    'Apply uses the saved canonical design and clears dirty slider values',
    (tester) async {
      final repo = MemoryDesigns();
      final live = DesignController(repo);
      await live.load();
      final studio = StudioViewModel(live);
      studio.change('library', 'gap', 32.0);
      expect(studio.dirty, true);
      expect(await studio.apply(), true);
      expect(studio.dirty, false);
      expect(studio.document.source, live.document.source);
      studio.dispose();
      live.dispose();
    },
  );
  for (final width in [1440.0, 960.0, 600.0]) {
    testWidgets('studio inspector, JSON and preview at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryDesigns();
      final live = DesignController(repo);
      await live.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: StudioScreen(controller: live),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('書架'));
      await tester.pumpAndSettle();
      if (width < 720) {
        await tester.ensureVisible(find.byType(Switch));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('慢一點，\n把一頁讀進心裡。'), findsNothing);
      await tester.ensureVisible(find.text('JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('design-json')), '{');
      await tester.pump(const Duration(milliseconds: 210));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '套用並保存'))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('design-preview')), findsOneWidget);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      live.dispose();
    });
  }
  testWidgets('saved theme applies to live shelf and reopening controller', (
    tester,
  ) async {
    final repo = MemoryDesigns();
    final live = DesignController(repo);
    await live.load();
    await live.apply(
      live.document
          .change('theme', 'paper', '#e8eef4')
          .change('library', 'showInvitation', false),
    );
    final reopened = DesignController(repo);
    await reopened.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: pageforgeTheme(reopened.document),
        home: LibraryScreen(
          repository: FakeRepository(),
          designController: reopened,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LibraryScreen));
    expect(context.design.paper, const Color(0xffe8eef4));
    expect(find.text('慢一點，\n把一頁讀進心裡。'), findsNothing);
    expect(find.byTooltip('外觀工作室'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    live.dispose();
    reopened.dispose();
  });
}
