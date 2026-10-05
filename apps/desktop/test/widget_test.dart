import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/library/library_screen.dart';
import 'package:pageforge/ui/theme.dart';
import 'package:pageforge/features/reader/views/editor_view.dart';
import 'fake_repository.dart';

void main() {
  testWidgets('native shelf opens reader, edits and saves a new version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: pageforgeTheme(),
        home: LibraryScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的書架 · 1'), findsOneWidget);
    await tester.tap(find.text('A place for words').first);
    await tester.pumpAndSettle();
    expect(find.text('First draft'), findsOneWidget);
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '# A new version');
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller;
    await tester.tap(find.byTooltip('放大字級'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller,
      same(controller),
    );
    await tester.tap(find.text('筆記'));
    await tester.pump();
    expect(find.byType(EditorView), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '# A new version',
    );
    await tester.tap(find.text('保存為新版本'));
    await tester.pumpAndSettle();
    expect(find.text('A new version'), findsOneWidget);
    expect(find.text('2 個版本'), findsOneWidget);
    await tester.tap(find.text('版本'));
    await tester.pumpAndSettle();
    expect(find.text('New thought'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
