import 'package:http/http.dart' as http;
import 'data/library_repository.dart';
import 'features/design/design_controller.dart';
import 'features/design/design_repository.dart';
import 'platform/backend_process.dart';

/// One owner releases the live design, HTTP clients and backend together.
class AppSession {
  AppSession({
    required this.library,
    required this.design,
    required Future<void> Function() disconnect,
  }) : _disconnect = disconnect;
  final LibraryRepository library;
  final DesignController design;
  final Future<void> Function() _disconnect;
  Future<void>? _closing;

  static Future<AppSession> open({
    Future<BackendProcess> Function() startBackend = BackendProcess.start,
    http.Client Function() createClient = http.Client.new,
  }) async {
    final backend = await startBackend();
    HttpLibraryRepository? library;
    HttpDesignRepository? settings;
    DesignController? design;
    Future<void> disconnect() async {
      library?.close();
      settings?.close();
      await backend.close();
    }

    try {
      final books = HttpLibraryRepository(
        backend.origin,
        backend.token,
        client: createClient(),
      );
      library = books;
      final designs = HttpDesignRepository(
        backend.origin,
        backend.token,
        client: createClient(),
      );
      settings = designs;
      final controller = DesignController(designs);
      design = controller;
      await controller.load();
      return AppSession(
        library: books,
        design: controller,
        disconnect: disconnect,
      );
    } catch (_) {
      design?.dispose();
      await disconnect();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _release();

  Future<void> _release() async {
    design.dispose();
    await _disconnect();
  }
}
