import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/features/reader/reader_view_model.dart';
import 'package:pageforge/features/reader/views/editor_view.dart';
import 'package:pageforge/features/reader/views/text_document_view.dart';
import 'package:pageforge/ui/theme.dart';

import 'fake_repository.dart';
import 'support/legacy_editor_control.dart';

// Diagnostic wall times in the widget-test engine. Not native release FPS or RSS.
// Run one size/view per process to bound resource use and isolate large layouts.
void main() {
  const enabled = bool.fromEnvironment('PAGEFORGE_LONG_DOCUMENT_PROBE');
  const editorControl = bool.fromEnvironment('PAGEFORGE_PROBE_EDITOR_CONTROL');
  const characters = int.fromEnvironment(
    'PAGEFORGE_PROBE_CHARACTERS',
    defaultValue: 100000,
  );
  const view = String.fromEnvironment(
    'PAGEFORGE_PROBE_VIEW',
    defaultValue: 'editor',
  );
  testWidgets(
    'long document diagnostic: $view / $characters runes',
    (tester) async {
      expect(characters, inInclusiveRange(1000, 5000000));
      expect(view, isIn(['editor', 'plain', 'markdown']));
      final content = syntheticText(characters);
      final repository = FakeRepository();
      final revisions = repository.data['revisions'] as List;
      (revisions.first as Map)['content'] = content;
      repository.data['format'] = view == 'markdown' ? 'markdown' : 'text';
      final model = ReaderViewModel(
        repository,
        repository.data['id'] as String,
      );
      await model.load();
      addTearDown(model.dispose);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final samples = <String, Object>{
        'view': view,
        'editorControl': editorControl,
        'characters': content.runes.length,
        'utf8Bytes': utf8.encode(content).length,
        'utf16Units': content.length,
      };
      final clock = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          theme: pageforgeTheme(),
          home: Scaffold(
            body: view == 'editor'
                ? (editorControl
                      ? LegacyEditorView(model: model)
                      : EditorView(model: model))
                : TextDocumentView(
                    content: content,
                    markdown: view == 'markdown',
                    fontSize: 18,
                    position: model.position!,
                    onQuote: (_) {},
                  ),
          ),
        ),
      );
      samples['firstPumpMs'] = clock.elapsedMicroseconds / 1000;
      clock.reset();
      await tester.pump();
      samples['idlePumpMs'] = clock.elapsedMicroseconds / 1000;
      if (view == 'editor') {
        if (find.byTooltip('最後一節').evaluate().isNotEmpty) {
          clock.reset();
          await tester.tap(find.byTooltip('最後一節'));
          await tester.pump();
          samples['openLastSectionMs'] = clock.elapsedMicroseconds / 1000;
        }
        final field = tester.widget<TextField>(find.byType(TextField));
        samples['activeSectionUnits'] = field.controller!.text.length;
        final controller = field.controller!;
        final edits = <double>[];
        for (var i = 0; i < 5; i++) {
          clock.reset();
          final value = '${controller.text}改';
          controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
          field.onChanged!(value);
          await tester.pump();
          edits.add(clock.elapsedMicroseconds / 1000);
        }
        samples['appendPumpMs'] = edits;
        expect(model.working!.content, endsWith('改改改改改'));
        expect(repository.saves, 0);
      } else {
        final scroll = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).first,
        );
        clock.reset();
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pump();
        samples['jumpToEndPumpMs'] = clock.elapsedMicroseconds / 1000;
      }
      clock.stop();
      expect(tester.takeException(), isNull);
      debugPrint('PAGEFORGE_UI_PROBE ${jsonEncode(samples)}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}

String syntheticText(int characters) {
  final pool =
      '文件閱讀段落版本筆記線索測試創作保存歷史中文 '
              'abcdefghijklmnopqrstuvwxyz0123456789🌿✨'
          .runes
          .toList();
  final random = Random(42);
  final text = StringBuffer();
  for (var i = 0; i < characters; i++) {
    if (i % 160 == 158 || i % 160 == 159) {
      text.write('\n');
    } else {
      text.writeCharCode(pool[random.nextInt(pool.length)]);
    }
  }
  return text.toString();
}
