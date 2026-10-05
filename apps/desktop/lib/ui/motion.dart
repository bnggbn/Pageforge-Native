import 'dart:async';
import 'package:flutter/material.dart';

abstract final class PageforgeMotion {
  static const quick = Duration(milliseconds: 180);
  static const entrance = Duration(milliseconds: 360);
  static const page = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }

  static PageRouteBuilder<T> route<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final reduced = PageforgeMotion.reduced(context);
    return PageRouteBuilder<T>(
      transitionDuration: reduced ? Duration.zero : page,
      reverseTransitionDuration: reduced ? Duration.zero : quick,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduced = PageforgeMotion.reduced(context);
        final eased = reduced
            ? const AlwaysStoppedAnimation<double>(1)
            : animation.drive(CurveTween(curve: curve));
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: reduced
                ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
                : eased.drive(
                    Tween(begin: const Offset(.025, 0), end: Offset.zero),
                  ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Animates a mounted view once. Parent rebuilds keep its state and child.
/// Key mode changes to animate the incoming pane without retaining the old one.
class MotionEntrance extends StatefulWidget {
  const MotionEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, .035),
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: PageforgeMotion.entrance,
  );
  late final CurvedAnimation eased = CurvedAnimation(
    parent: controller,
    curve: PageforgeMotion.curve,
  );
  Timer? timer;
  bool started = false;
  bool reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = PageforgeMotion.reduced(context);
    if (reduced) {
      timer?.cancel();
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      if (widget.delay == Duration.zero) {
        controller.forward();
      } else {
        timer = Timer(widget.delay, () {
          if (mounted) controller.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    eased.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: reduced ? const AlwaysStoppedAnimation<double>(1) : eased,
      child: SlideTransition(
        position: reduced
            ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
            : eased.drive(Tween(begin: widget.offset, end: Offset.zero)),
        child: widget.child,
      ),
    );
  }
}
