import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pageforge/platform/backend_process.dart';

class FakeBackendProcess implements Process {
  FakeBackendProcess({this.exitOnClose = true}) {
    stdin = IOSink(
      _Input(() {
        inputCloses++;
        if (exitOnClose) finish();
      }),
    );
  }
  final bool exitOnClose;
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exited = Completer<int>();
  int inputCloses = 0, kills = 0;
  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exited.future;
  @override
  int get pid => 1234;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    finish();
    return true;
  }

  void finish() {
    if (exited.isCompleted) return;
    exited.complete(0);
    unawaited(output.close());
    unawaited(errors.close());
  }

  void ready({String origin = 'http://127.0.0.1:12345', String? token}) {
    final json = jsonEncode({
      'origin': origin,
      'token': token ?? List.filled(64, '1').join(),
    });
    final frame = utf8.encode('$json\n');
    output.add(frame.sublist(0, 7));
    output.add(frame.sublist(7));
  }
}

class _Input implements StreamConsumer<List<int>> {
  _Input(this.closed);
  final void Function() closed;
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<void> close() async => closed();
}

/// The executable is a placeholder; launch is always injected in these tests.
class BackendFixture {
  BackendFixture() {
    Directory('${root.path}/bin').createSync();
    File('${root.path}/bin/pageforge-backend.exe').writeAsStringSync('');
  }
  final root = Directory.systemTemp.createTempSync('pageforge-startup-');
  Future<BackendProcess> start(
    FakeBackendProcess child, {
    void Function()? announce,
  }) => BackendProcess.start(
    root: root.path,
    launch: (executable, args) async {
      if (!args.contains('--parent-pipe')) {
        throw StateError('missing parent pipe');
      }
      scheduleMicrotask(announce ?? child.ready);
      return child;
    },
  );
  void dispose() {
    final location = root.absolute.path;
    final parent = Directory.systemTemp.absolute.path;
    if (!location.startsWith('$parent${Platform.pathSeparator}') ||
        !root.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('pageforge-startup-')) {
      throw StateError('invalid temporary fixture path');
    }
    root.deleteSync(recursive: true);
  }
}
