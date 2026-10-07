import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef ProcessLauncher = Future<Process> Function(String, List<String>);

class BackendProcess {
  BackendProcess._(
    this.process,
    this.origin,
    this.token,
    this.root,
    this._errors,
  );
  final Process process;
  final Uri origin;
  final String token, root;
  final StreamSubscription<String> _errors;
  Future<void>? _closing;

  static String findRoot() {
    const configured = String.fromEnvironment('PAGEFORGE_PROJECT_ROOT');
    var path = configured.isNotEmpty
        ? configured
        : Platform.environment['PAGEFORGE_PROJECT_ROOT'] ??
              Directory.current.path;
    for (var i = 0; i < 8; i++) {
      if (File('$path/pageforge.config.json').existsSync()) return path;
      final parent = Directory(path).parent.path;
      if (parent == path) break;
      path = parent;
    }
    final packaged = File(Platform.resolvedExecutable).parent.path;
    if (File('$packaged/pageforge.config.json').existsSync()) return packaged;
    throw StateError(
      '找不到 pageforge.config.json，請從專案啟動或設定 PAGEFORGE_PROJECT_ROOT。',
    );
  }

  static Future<BackendProcess> start({
    String? root,
    ProcessLauncher launch = Process.start,
  }) async {
    final projectRoot = root ?? findRoot();
    final packaged = File(Platform.resolvedExecutable).parent.path;
    final alongside = '$packaged/pageforge-backend.exe';
    final executable = File(alongside).existsSync()
        ? alongside
        : '$projectRoot/bin/pageforge-backend.exe';
    if (!File(executable).existsSync()) {
      throw StateError('Go 後端尚未建置，請先執行 scripts/build.ps1。');
    }
    final process = await launch(executable, [
      '--root',
      projectRoot,
      '--parent-pipe',
    ]);
    final errors = StringBuffer();
    var remaining = 16 * 1024;
    final diagnostics = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (text) {
            final count = text.length < remaining ? text.length : remaining;
            errors.write(text.substring(0, count));
            remaining -= count;
          },
          // Diagnostics are optional; readiness and exit determine lifecycle.
          onError: (Object _) {},
        );
    try {
      final line = await _readyLine(
        process.stdout,
      ).timeout(const Duration(seconds: 15));
      final info = jsonDecode(line);
      if (info is! Map ||
          info['origin'] is! String ||
          info['token'] is! String) {
        throw StateError('Go 後端回報無效的連線資訊。');
      }
      final origin = Uri.parse(info['origin'] as String);
      final token = info['token'] as String;
      if (origin.scheme != 'http' ||
          origin.host != '127.0.0.1' ||
          !origin.hasPort ||
          origin.port < 1 ||
          origin.port > 65535 ||
          origin.userInfo.isNotEmpty ||
          origin.path.isNotEmpty ||
          origin.hasQuery ||
          origin.hasFragment ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        throw StateError('Go 後端回報無效的連線資訊。');
      }
      return BackendProcess._(process, origin, token, projectRoot, diagnostics);
    } catch (error) {
      await _stopProcess(process, diagnostics);
      final message = errors.toString().trim();
      throw StateError(
        message.isNotEmpty
            ? message
            : error is TimeoutException
            ? 'Go 後端啟動逾時。'
            : 'Go 後端無法啟動。',
      );
    }
  }

  static Future<String> _readyLine(Stream<List<int>> stdout) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stdout) {
      final newline = chunk.indexOf(10);
      final data = newline < 0 ? chunk : chunk.sublist(0, newline);
      if (bytes.length + data.length > 4096) {
        throw StateError('Go 後端啟動資訊超過容量。');
      }
      bytes.add(data);
      if (newline >= 0) return utf8.decode(bytes.takeBytes());
    }
    throw StateError('Go 後端未提供連線資訊。');
  }

  Future<void> close() => _closing ??= _stopProcess(process, _errors);

  static Future<void> _stopProcess(
    Process process,
    StreamSubscription<String> errors,
  ) async {
    try {
      try {
        await process.stdin.close();
      } catch (_) {
        // A child that already exited may have closed its input pipe.
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2));
      }
    } finally {
      await errors.cancel();
    }
  }
}
