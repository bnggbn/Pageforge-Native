import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/design/design_controller.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'package:pageforge/features/design/design_repository.dart';
import 'package:pageforge/features/design/studio_view_model.dart';

class PendingDesigns implements DesignRepository {
  final loading = Completer<DesignSnapshot>();
  final saving = Completer<DesignSnapshot>();
  @override
  Future<DesignSnapshot> load() => loading.future;
  @override
  Future<DesignSnapshot> save(
    DesignDocument document,
    String expectedRevision,
  ) => saving.future;
}

void main() {
  test('decoded values and exported JSON cannot mutate a saved design', () {
    final input = DesignDocument.defaults.toJson();
    (input['reader'] as Json).remove('paragraphGapLines');
    final document = DesignDocument.fromJson(input);
    final source = document.source;
    expect((input['reader'] as Json).containsKey('paragraphGapLines'), false);
    input['theme']['ink'] = '#ffffff';
    input['library']['gap'] = 40;
    input['reader']['lineHeight'] = 2.3;
    final exported = document.toJson();
    exported['theme']['paper'] = '#ffffff';
    exported['reader']['paragraphGapLines'] = 0;
    expect(document.source, source);
    expect(document.get<String>('theme', 'ink'), '#343a32');
    expect(document.number('library', 'gap'), 28);
    expect(document.number('reader', 'lineHeight'), 1.95);
    expect(document.number('reader', 'paragraphGapLines'), 1);
    for (final value in [double.nan, double.infinity]) {
      final invalid = document.toJson();
      invalid['reader']['lineHeight'] = value;
      expect(() => DesignDocument.fromJson(invalid), throwsFormatException);
    }
  });

  test('a preset is atomic and one undo returns to the previous design', () {
    final live = DesignController(PendingDesigns());
    final studio = StudioViewModel(live);
    addTearDown(studio.dispose);
    addTearDown(live.dispose);
    final before = studio.source;
    studio.preset({'accent': '#335577', 'paper': 'invalid'});
    expect(studio.source, before);
    expect(studio.document.source, before);
    expect(studio.error, isNotEmpty);
    expect(studio.canUndo, false);
    studio.preset({'accent': '#335577', 'paper': '#ffffff'});
    expect(studio.error, isEmpty);
    final preset = studio.source;
    studio.undo();
    expect(studio.source, before);
    studio.redo();
    expect(studio.source, preset);
  });

  test(
    'completing a load or save after disposal cannot publish live state',
    () async {
      final next = DesignSnapshot(
        DesignDocument.defaults.change('theme', 'accent', '#335577'),
        'saved',
      );
      for (final save in [false, true]) {
        final repo = PendingDesigns();
        final live = DesignController(repo);
        final before = live.document.source;
        final pending = save ? live.apply(next.document) : live.load();
        live.dispose();
        (save ? repo.saving : repo.loading).complete(next);
        await pending;
        expect(live.document.source, before);
        expect(live.revision, '');
      }
    },
  );

  testWidgets('reload cancels pending JSON preview and restores saved state', (
    tester,
  ) async {
    final repo = PendingDesigns();
    final live = DesignController(repo);
    final studio = StudioViewModel(live);
    addTearDown(studio.dispose);
    addTearDown(live.dispose);
    studio.editJson('{');
    final reload = studio.reload();
    repo.loading.complete(DesignSnapshot(DesignDocument.defaults, 'saved'));
    await reload;
    await tester.pump(const Duration(milliseconds: 250));
    expect(studio.error, isEmpty);
    expect(studio.source, DesignDocument.defaults.source);
    expect(studio.busy, false);
    expect(studio.dirty, false);
  });

  test(
    'closing a studio during save does not notify a disposed view model',
    () async {
      final repo = PendingDesigns();
      final live = DesignController(repo);
      final studio = StudioViewModel(live);
      studio.change('theme', 'accent', '#335577');
      final saved = DesignSnapshot(studio.document, 'saved');
      final apply = studio.apply();
      studio.dispose();
      repo.saving.complete(saved);
      expect(await apply, false);
      expect(live.revision, 'saved');
      live.dispose();
    },
  );
}
