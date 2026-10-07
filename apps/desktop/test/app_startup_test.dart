import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/app.dart';
import 'package:pageforge/app_session.dart';
import 'package:pageforge/features/design/design_controller.dart';
import 'package:pageforge/features/design/design_document.dart';
import 'package:pageforge/features/design/design_repository.dart';
import 'package:pageforge/features/library/library_screen.dart';
import 'fake_repository.dart';
import 'close_boundary_test.dart' show requestClose;

class _Settings implements DesignRepository {
  @override
  Future<DesignSnapshot> load() async =>
      DesignSnapshot(DesignDocument.defaults, 'saved');
  @override
  Future<DesignSnapshot> save(DesignDocument document, String revision) async =>
      DesignSnapshot(document, 'next');
}

AppSession session(Future<void> Function() disconnect) => AppSession(
  library: FakeRepository(),
  design: DesignController(_Settings()),
  disconnect: disconnect,
);

void main() {
  testWidgets(
    'retry is guarded and a late session is released after disposal',
    (tester) async {
      final pending = Completer<AppSession>();
      var opens = 0, closes = 0;
      await tester.pumpWidget(
        PageforgeBootstrap(
          openSession: () {
            if (++opens == 1) return Future.error(StateError('startup failed'));
            return pending.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('startup failed'), findsOneWidget);
      final retry = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      retry();
      retry();
      expect(opens, 2);
      await tester.pumpWidget(const SizedBox());
      pending.complete(
        session(() async {
          closes++;
        }),
      );
      await tester.pump();
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'closing during startup waits for acquired resources and their release',
    (tester) async {
      final pending = Completer<AppSession>(), released = Completer<void>();
      var closes = 0, approved = false;
      await tester.pumpWidget(
        PageforgeBootstrap(openSession: () => pending.future),
      );
      final response = requestClose(tester).then((value) => approved = value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(approved, false);
      pending.complete(
        session(() {
          closes++;
          return released.future;
        }),
      );
      await tester.pump();
      expect(closes, 1);
      expect(approved, false);
      expect(find.byType(LibraryScreen), findsNothing);
      released.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await response;
      expect(approved, true);
      await tester.pumpWidget(const SizedBox());
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
