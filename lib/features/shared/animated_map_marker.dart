import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Interpolates a marker's position between GPS updates so movement reads as
/// continuous rather than teleporting.
///
/// Positions arrive every 10 m of travel, which at tricycle speed is a couple
/// of seconds apart. Animating between them trades about a second of lag for
/// movement that looks real — at these speeds the lag is not perceptible.
///
/// `MarkerLayer` places every marker in its list from a single static build
/// pass, so nothing in that list can move on its own between rebuilds — a
/// marker can only move by being repositioned every frame. This widget does
/// that itself, projecting [target] through the same `MapCamera` that
/// `MarkerLayer` uses internally, so it can sit directly in `FlutterMap`'s
/// `children` and run its own animation independent of any other marker.
class AnimatedMapMarker extends StatefulWidget {
  /// The marker's real (non-interpolated) position. Changing this animates
  /// the rendered marker toward it rather than snapping.
  final LatLng target;

  /// Builds the marker's visual content for the current interpolated
  /// position — the same widget you'd otherwise pass as `Marker.child`.
  final Widget Function(BuildContext context, LatLng position) builder;

  final double width;
  final double height;
  final Duration duration;

  const AnimatedMapMarker({
    super.key,
    required this.target,
    required this.builder,
    required this.width,
    required this.height,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<AnimatedMapMarker> createState() => _AnimatedMapMarkerState();
}

class _AnimatedMapMarkerState extends State<AnimatedMapMarker> {
  @override
  Widget build(BuildContext context) {
    // TweenAnimationBuilder (not a manual AnimationController) because its
    // built-in "retarget" behaviour is exactly what's needed here: when a
    // widget update changes the tween's end value mid-flight, it evaluates
    // the tween at its current position, makes that the new begin, and
    // restarts toward the new end — so a target change while the marker is
    // still moving continues from wherever it actually is, never jumping
    // back to the previous target first. A manual controller would have to
    // reimplement that "sample current position, restart from there" logic
    // by hand.
    return MobileLayerTransformer(
      child: Stack(
        children: [
          TweenAnimationBuilder<LatLng>(
            tween: _LatLngTween(end: widget.target),
            duration: widget.duration,
            curve: Curves.linear,
            builder: (context, position, _) {
              final camera = MapCamera.of(context);
              final offset = camera.getOffsetFromOrigin(position);
              return Positioned(
                left: offset.dx - widget.width / 2,
                top: offset.dy - widget.height / 2,
                width: widget.width,
                height: widget.height,
                child: widget.builder(context, position),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Interpolates latitude and longitude independently. Fine over the short
/// distances a tricycle covers between updates — no need for great circle
/// interpolation.
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng super.end});

  @override
  LatLng lerp(double t) {
    final b = begin!;
    final e = end!;
    return LatLng(
      b.latitude + (e.latitude - b.latitude) * t,
      b.longitude + (e.longitude - b.longitude) * t,
    );
  }
}
