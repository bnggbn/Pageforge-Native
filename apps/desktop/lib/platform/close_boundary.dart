import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CloseTask {
  CloseTask({
    required this.dirty,
    required this.busy,
    required this.save,
    required this.discard,
    required this.description,
    required this.error,
  });
  final bool Function() dirty, busy;
  final Future<bool> Function() save, discard;
  final String description;
  final String Function() error;
}

/// UI-independent participants let reader and studio retain separate persistence logic.
class CloseController {
  final tasks = <CloseTask>[];
  bool get busy => tasks.any((task) => task.busy());
  bool get dirty => tasks.any((task) => task.dirty());
  Future<bool> prepare({bool discard = false}) async {
    if (busy) return false;
    for (final task in List<CloseTask>.of(tasks).reversed) {
      if (!await (discard ? task.discard() : task.save())) return false;
    }
    return true;
  }
}

class CloseBoundary extends StatefulWidget {
  const CloseBoundary({required this.builder, this.beforeClose, super.key});
  final Widget Function(BuildContext, GlobalKey<NavigatorState>) builder;
  final Future<void> Function()? beforeClose;
  static const channel = MethodChannel('pageforge/window');
  @override
  State<CloseBoundary> createState() => _CloseBoundaryState();
}

class _CloseBoundaryState extends State<CloseBoundary> {
  final controller = CloseController();
  final navigator = GlobalKey<NavigatorState>();
  bool pending = false, closing = false;
  @override
  void initState() {
    super.initState();
    CloseBoundary.channel.setMethodCallHandler((call) async {
      if (call.method != 'requestClose') throw MissingPluginException();
      return requestClose();
    });
  }

  Future<bool> requestClose() async {
    if (closing) return true;
    if (pending) return false;
    final context = navigator.currentContext;
    if (context == null) return false;
    pending = true;
    try {
      if (controller.busy) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('正在處理文件'),
            content: const Text('請等載入或保存完成後再關閉。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('繼續使用'),
              ),
            ],
          ),
        );
        return false;
      }
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CloseDialog(
          controller: controller,
          beforeClose: widget.beforeClose,
        ),
      );
      closing = approved == true;
      return closing;
    } finally {
      pending = false;
    }
  }

  @override
  void dispose() {
    CloseBoundary.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CloseScope(
    controller: controller,
    child: widget.builder(context, navigator),
  );
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog({required this.controller, required this.beforeClose});
  final CloseController controller;
  final Future<void> Function()? beforeClose;
  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  bool saving = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    if (!widget.controller.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => finish(false));
    }
  }

  Future<void> finish(bool discard) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      if (!await widget.controller.prepare(discard: discard)) {
        throw StateError(
          widget.controller.tasks
              .map((t) => t.error())
              .where((e) => e.isNotEmpty)
              .join('\n'),
        );
      }
      await widget.beforeClose?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '無法完成保存，視窗已保留。\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: Text(widget.controller.dirty ? '還有尚未保存的內容' : '正在關閉'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final task in widget.controller.tasks.where((t) => t.dirty()))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(task.description),
              ),
            if (saving) const LinearProgressIndicator(),
            if (error.isNotEmpty) SelectableText(error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: saving ? null : () => finish(true),
          child: const Text('捨棄草稿並關閉'),
        ),
        FilledButton(
          onPressed: saving ? null : () => finish(false),
          child: const Text('保存並關閉'),
        ),
      ],
    ),
  );
}

class _CloseScope extends InheritedWidget {
  const _CloseScope({required this.controller, required super.child});
  final CloseController controller;
  @override
  bool updateShouldNotify(_CloseScope old) => controller != old.controller;
}

class CloseParticipant extends StatefulWidget {
  const CloseParticipant({required this.task, required this.child, super.key});
  final CloseTask task;
  final Widget child;
  @override
  State<CloseParticipant> createState() => _CloseParticipantState();
}

class _CloseParticipantState extends State<CloseParticipant> {
  CloseController? controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_CloseScope>()
        ?.controller;
    if (next == controller) return;
    controller?.tasks.remove(widget.task);
    controller = next;
    controller?.tasks.add(widget.task);
  }

  @override
  void didUpdateWidget(CloseParticipant old) {
    super.didUpdateWidget(old);
    controller?.tasks.remove(old.task);
    controller?.tasks.add(widget.task);
  }

  @override
  void dispose() {
    controller?.tasks.remove(widget.task);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
