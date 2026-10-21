import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Soft gradient + colour blobs drawn behind every screen (no blur filter, cheap to paint).
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.backdrop),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _BlobPainter(p.dark))),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    final a = dark ? 0.35 : 0.55;
    blob(Offset(size.width * 0.1, size.height * 0.08), size.width * 0.75, AppColors.saffron.withValues(alpha: a));
    blob(Offset(size.width * 0.95, size.height * 0.35), size.width * 0.7, AppColors.maroon.withValues(alpha: a * 0.6));
    blob(
      Offset(size.width * 0.2, size.height * 0.85),
      size.width * 0.8,
      (dark ? AppColors.blue : AppColors.gold).withValues(alpha: a * 0.5),
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.dark != dark;
}

/// Frosted glass surface. [blur] > 0 uses a BackdropFilter; keep it for a few
/// large surfaces (bars, sheets, hero cards). List cards pass blur: 0 for 60fps.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.blur = 0,
    this.radius = 22,
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
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final br = BorderRadius.circular(radius);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: br,
        color: tint ?? (strong ? p.glassFillStrong : p.glassFill),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: p.dark ? 0.10 : 0.45),
            Colors.white.withValues(alpha: p.dark ? 0.02 : 0.10),
          ],
        ),
        border: Border.all(color: p.glassBorder, width: 0.8),
      ),
      child: child,
    );
    if (blur > 0) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [BoxShadow(color: p.glassShadow, blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(borderRadius: br, child: body),
    );
  }
}

/// Tappable glass card that shrinks slightly while pressed (spring back).
class PressableGlass extends StatefulWidget {
  const PressableGlass({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Duration(milliseconds: _down ? 90 : 380),
        curve: _down ? Curves.easeOut : const SpringCurve(),
        child: Glass(padding: widget.padding, radius: widget.radius, blur: widget.blur, child: widget.child),
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
    return 1 - math.exp(-z * w * t) * (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
  }
}
