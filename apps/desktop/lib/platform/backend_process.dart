import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BackendProcess {
  BackendProcess._(this.process, this.origin, this.token, this.root);
  final Process process;
  final Uri origin;
  final String token, root;

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

  static Future<BackendProcess> start() async {
    final root = findRoot();
    final alongside =
        '${File(Platform.resolvedExecutable).parent.path}/pageforge-backend.exe';
    final executable = File(alongside).existsSync()
        ? alongside
        : '$root/bin/pageforge-backend.exe';
    if (!File(executable).existsSync()) {
      throw StateError('Go 後端尚未建置，請先執行 scripts/build.ps1。');
    }
    final process = await Process.start(executable, [
      '--root',
      root,
      '--parent-pipe',
    ]);
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    try {
      final line = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      final info = jsonDecode(line) as Map<String, dynamic>;
      final origin = Uri.parse(info['origin'] as String);
      if (origin.scheme != 'http' || origin.host != '127.0.0.1') {
        throw StateError('後端位址無效。');
      }
      return BackendProcess._(process, origin, info['token'] as String, root);
    } catch (_) {
      await process.stdin.close();
      process.kill();
      throw StateError(
        errors.isEmpty ? 'Go 後端無法啟動。' : errors.toString().trim(),
      );
    }
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }
}
