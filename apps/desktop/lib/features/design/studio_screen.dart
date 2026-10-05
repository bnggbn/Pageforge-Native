import 'package:flutter/material.dart';
import 'design_controller.dart';
import 'studio_inspector.dart';
import 'studio_json_editor.dart';
import 'studio_preview.dart';
import 'studio_view_model.dart';
import 'studio_toolbar.dart';
import 'studio_scene_list.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({required this.controller, super.key});
  final DesignController controller;
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final model = StudioViewModel(widget.controller);
  bool json = false, leaving = false;
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> back() async {
    if (model.busy) return;
    if (model.dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('離開外觀工作室？'),
          content: const Text('尚未套用的外觀調整會捨棄。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('繼續調整'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('捨棄並離開'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => leaving = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              StudioToolbar(model: model, onBack: back),
              if (model.error.isNotEmpty || model.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: SelectableText(
                    model.error.isNotEmpty ? model.error : model.message,
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final scenes = StudioSceneList(
                      model: model,
                      compact: bounds.maxWidth < 1100,
                    );
                    final inspector = Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('屬性')),
                              ButtonSegment(value: true, label: Text('JSON')),
                            ],
                            selected: {json},
                            onSelectionChanged: (value) =>
                                setState(() => json = value.first),
                          ),
                        ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: model.busy,
                            child: json
                                ? StudioJsonEditor(
                                    source: model.source,
                                    onChanged: model.editJson,
                                  )
                                : StudioInspector(model: model),
                          ),
                        ),
                      ],
                    );
                    final preview = StudioPreview(
                      document: model.document,
                      scene: model.scene,
                    );
                    if (bounds.maxWidth < 720) {
                      return Column(
                        children: [
                          scenes,
                          Expanded(
                            child: ListView(
                              children: [
                                SizedBox(height: 520, child: preview),
                                SizedBox(height: 480, child: inspector),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (bounds.maxWidth >= 1100)
                          SizedBox(width: 165, child: scenes),
                        Expanded(
                          child: Column(
                            children: [
                              if (bounds.maxWidth < 1100) scenes,
                              Expanded(child: preview),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 300, child: inspector),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '即時預覽 · 套用後才改變你的 Pageforge',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
