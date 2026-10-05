import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/library/book_tile.dart';
import 'package:pageforge/ui/motion.dart';
import 'package:pageforge/ui/theme.dart';

void main() {
  testWidgets('reduced motion cancels delayed entrance and disables routes', (
    tester,
  ) async {
    var reduced = false;
    late StateSetter update;
    late BuildContext routeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Builder(
                builder: (context) {
                  routeContext = context;
                  return const MotionEntrance(
                    delay: Duration(milliseconds: 180),
                    child: Text('Ready'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(MotionEntrance),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      0,
    );
    final child = tester.element(find.text('Ready'));
    update(() => reduced = true);
    await tester.pump();
    expect(tester.element(find.text('Ready')), same(child));
    expect(
      find.descendant(
        of: find.byType(MotionEntrance),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );
    final route = PageforgeMotion.route<void>(
      routeContext,
      builder: (_) => const Text('Reader'),
    );
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrance does not replay or recreate child on parent update', (
    tester,
  ) async {
    var revision = 1;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MotionEntrance(child: Text('Version $revision'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(MotionEntrance));
    update(() => revision++);
    await tester.pump();
    expect(tester.state(find.byType(MotionEntrance)), same(state));
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(MotionEntrance),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      1,
    );
    expect(find.text('Version 2'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('book hover and keyboard focus lift the cover then settle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pageforgeTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 230,
              height: 320,
              child: BookTile(
                book: BookSummary({
                  'id': '10000000-0000-4000-8000-000000000001',
                  'title': 'Motion study',
                  'filename': 'study.md',
                  'format': 'markdown',
                  'revisionCount': 1,
                  'progress': 0,
                }),
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('Motion study').first;
    final resting = tester.getTopLeft(title).dy;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(BookTile)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(resting - 6, .1));
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(resting, .1));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(resting - 6, .1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.removePointer();
  });
}
