import 'dart:async';
import 'package:flutter/material.dart';
import 'app_session.dart';
import 'features/library/library_screen.dart';
import 'platform/close_boundary.dart';
import 'ui/theme.dart';

class PageforgeBootstrap extends StatefulWidget {
  const PageforgeBootstrap({this.openSession = AppSession.open, super.key});
  final Future<AppSession> Function() openSession;
  @override
  State<PageforgeBootstrap> createState() => _PageforgeBootstrapState();
}

class _PageforgeBootstrapState extends State<PageforgeBootstrap> {
  AppSession? session;
  Future<AppSession>? _pending;
  bool _starting = false, _stopping = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(start());
  }

  Future<void> start() async {
    if (_starting || _stopping || session != null) return;
    _starting = true;
    setState(() => error = '');
    try {
      final opening = widget.openSession();
      _pending = opening;
      final ready = await opening;
      if (!mounted || _stopping) {
        await ready.close();
        return;
      }
      setState(() => session = ready);
    } catch (e) {
      if (mounted && !_stopping) setState(() => error = e.toString());
    } finally {
      _starting = false;
      _pending = null;
    }
  }

  Future<void> stop() async {
    _stopping = true;
    if (session != null) {
      await session!.close();
      return;
    }
    final pending = _pending;
    if (pending == null) return;
    AppSession ready;
    try {
      ready = await pending;
    } catch (_) {
      // A failed open has already released its resources.
      return;
    }
    await ready.close();
  }

  @override
  void dispose() {
    // The window is gone; still close any session completing in the background.
    unawaited(stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CloseBoundary(
    beforeClose: stop,
    builder: (context, navigator) => ListenableBuilder(
      listenable: session?.design ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, _) => MaterialApp(
        navigatorKey: navigator,
        title: 'Pageforge',
        debugShowCheckedModeBanner: false,
        theme: pageforgeTheme(session?.design.document),
        home: session != null
            ? LibraryScreen(
                repository: session!.library,
                designController: session!.design,
              )
            : Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pageforge.',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 24),
                        if (error.isEmpty)
                          const CircularProgressIndicator()
                        else ...[
                          SelectableText(
                            error,
                            style: const TextStyle(color: rust),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: start,
                            child: const Text('重新啟動'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
