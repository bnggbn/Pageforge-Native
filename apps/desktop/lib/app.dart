import 'dart:async';
import 'package:flutter/material.dart';
import 'data/library_repository.dart';
import 'features/library/library_screen.dart';
import 'platform/backend_process.dart';
import 'ui/theme.dart';
import 'features/design/design_controller.dart';
import 'features/design/design_repository.dart';

class PageforgeBootstrap extends StatefulWidget {
  const PageforgeBootstrap({super.key});
  @override
  State<PageforgeBootstrap> createState() => _PageforgeBootstrapState();
}

class _PageforgeBootstrapState extends State<PageforgeBootstrap> {
  BackendProcess? backend;
  HttpLibraryRepository? repository;
  HttpDesignRepository? designRepository;
  DesignController? designController;
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
      final designs = HttpDesignRepository(process.origin, process.token);
      final controller = DesignController(designs);
      await controller.load();
      if (!mounted) {
        controller.dispose();
        designs.close();
        await process.close();
        return;
      }
      setState(() {
        designRepository = designs;
        designController = controller;
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
    designController?.dispose();
    designRepository?.close();
    repository?.close();
    if (backend != null) unawaited(backend!.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: designController ?? const AlwaysStoppedAnimation<double>(0),
    builder: (context, _) => MaterialApp(
      title: 'Pageforge',
      debugShowCheckedModeBanner: false,
      theme: pageforgeTheme(designController?.document),
      home: repository != null
          ? LibraryScreen(
              repository: repository!,
              designController: designController,
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
  );
}
