import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Owns the gesture on the card body; pins and buttons live outside this area.
class EvidenceDragSurface extends StatefulWidget {
  const EvidenceDragSurface({
    required this.child,
    required this.onTap,
    required this.onPressed,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap, onEnd, onCancel;
  final ValueChanged<bool> onPressed;
  final ValueChanged<Offset> onStart, onUpdate;

  @override
  State<EvidenceDragSurface> createState() => _EvidenceDragSurfaceState();
}

class _EvidenceDragSurfaceState extends State<EvidenceDragSurface> {
  int? pointer;

  void release() {
    if (pointer == null) return;
    pointer = null;
    setState(() {});
    widget.onPressed(false);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: pointer == null
        ? SystemMouseCursors.grab
        : SystemMouseCursors.grabbing,
    child: Listener(
      onPointerDown: (event) {
        if (pointer != null || event.buttons != kPrimaryButton) return;
        pointer = event.pointer;
        setState(() {});
        widget.onPressed(true);
      },
      onPointerUp: (event) {
        if (pointer == event.pointer) release();
      },
      onPointerCancel: (event) {
        if (pointer != event.pointer) return;
        // Cancel the transient position before the pan recognizer ends it.
        widget.onCancel();
        release();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) => widget.onStart(details.globalPosition),
        onPanUpdate: (details) => widget.onUpdate(details.globalPosition),
        onPanEnd: (_) => widget.onEnd(),
        onPanCancel: widget.onCancel,
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          mouseCursor: pointer == null
              ? SystemMouseCursors.grab
              : SystemMouseCursors.grabbing,
          child: widget.child,
        ),
      ),
    ),
  );
}
