import 'package:flutter/material.dart';

/// Highest release velocity (px/s) a flick may carry. Like the reader app's
/// `BoundedScrollPhysics`: one swipe never throws a long list from top to bottom, and the
/// ballistic simulation stays short (less work per frame). Dragging follows the finger exactly.
const double kMaxFling = 6500;

/// iOS-style bouncing physics (the admin look) with a capped fling velocity.
class SmoothScrollPhysics extends BouncingScrollPhysics {
  const SmoothScrollPhysics({super.parent});

  @override
  SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) => SmoothScrollPhysics(parent: buildParent(ancestor));

  @override
  double get maxFlingVelocity => kMaxFling;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      super.createBallisticSimulation(position, velocity.clamp(-kMaxFling, kMaxFling));
}

/// App-wide scroll behaviour: every scrollable gets [SmoothScrollPhysics] and no glow/stretch
/// indicator layer on top of the bounce.
class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const SmoothScrollPhysics();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
