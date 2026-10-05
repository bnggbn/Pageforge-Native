import 'dart:async';
import 'package:flutter/material.dart';
import 'data/library_repository.dart';
import 'features/library/library_screen.dart';
import 'platform/backend_process.dart';
import 'ui/theme.dart';

class PageforgeBootstrap extends StatefulWidget {
  const PageforgeBootstrap({super.key});
  @override
  State<PageforgeBootstrap> createState() => _PageforgeBootstrapState();
}

class _PageforgeBootstrapState extends State<PageforgeBootstrap> {
  BackendProcess? backend;
  HttpLibraryRepository? repository;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(start());
  }

  Future<void> start() async {
    setState(() {
      error = '';
    });
    try {
      final process = await BackendProcess.start();
      if (!mounted) {
        await process.close();
        return;
      }
      setState(() {
        backend = process;
        repository = HttpLibraryRepository(process.origin, process.token);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    repository?.close();
    if (backend != null) unawaited(backend!.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pageforge',
    debugShowCheckedModeBanner: false,
    theme: pageforgeTheme(),
    home: repository != null
        ? LibraryScreen(repository: repository!)
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
                      FilledButton(onPressed: start, child: const Text('重新啟動')),
                    ],
                  ],
                ),
              ),
            ),
          ),
  );
}
