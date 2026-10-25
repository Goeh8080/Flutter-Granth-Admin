import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// Flat cream page background (Round 1: same as the user app; no blobs, no gradient).
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: GColors.cream, child: child);
}

/// Paper card with the user app's border. [blur] is accepted for old call sites and ignored:
/// there is no BackdropFilter anywhere in the app.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.blur = 0,
    this.radius = 14,
    this.padding = const EdgeInsets.all(16),
    this.strong = false,
    this.tint,
  });
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: tint ?? GColors.paper,
      border: Border.all(color: GColors.creamDark, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: GColors.shadow(0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

/// Tappable glass card that shrinks slightly while pressed (spring back).
class PressableGlass extends StatefulWidget {
  const PressableGlass({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.radius = 14,
    this.blur = 0,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  State<PressableGlass> createState() => _PressableGlassState();
}

class _PressableGlassState extends State<PressableGlass> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Duration(milliseconds: _down ? 90 : 380),
        curve: _down ? Curves.easeOut : const SpringCurve(),
        // RepaintBoundary: the card is rasterised once; the press animation only scales that layer.
        child: RepaintBoundary(
          child: Glass(
            padding: widget.padding,
            radius: widget.radius,
            blur: widget.blur,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Under-damped spring as a Curve (slight overshoot, iOS-like).
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.72, this.stiffness = 9.5});
  final double damping;
  final double stiffness;
  @override
  double transformInternal(double t) {
    final w = stiffness;
    final z = damping;
    final wd = w * math.sqrt(1 - z * z);
    return 1 -
        math.exp(-z * w * t) *
            (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
  }
}
