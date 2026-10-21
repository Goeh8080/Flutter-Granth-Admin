import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ViewerImage {
  final String url;
  final String label;
  final String? heroTag;
  const ViewerImage(this.url, this.label, {this.heroTag});
}

/// Full-screen zoomable viewer (web: openPopup(praman image, editor image)).
void openImageViewer(BuildContext context, List<ViewerImage> images, {int initial = 0}) {
  if (images.isEmpty) return;
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => _Viewer(images: images, initial: initial),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.images, required this.initial});
  final List<ViewerImage> images;
  final int initial;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_drag.abs() / 400)).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
            onVerticalDragEnd: (d) {
              if (_drag.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 900) {
                Navigator.pop(context);
              } else {
                setState(() => _drag = 0);
              }
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: _drag == 0 ? 250 : 0),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, _drag, 0),
              child: PageView.builder(
                controller: _pc,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final img = widget.images[i];
                  Widget w = CachedNetworkImage(
                    imageUrl: img.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(child: CupertinoActivityIndicator(color: Colors.white)),
                    errorWidget: (_, _, _) => const Center(
                      child: Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white54, size: 40),
                    ),
                  );
                  if (img.heroTag != null && i == widget.initial) w = Hero(tag: img.heroTag!, child: w);
                  return InteractiveViewer(minScale: 1, maxScale: 6, child: Center(child: w));
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white70, size: 32),
                  ),
                  Expanded(
                    child: Text(
                      '${widget.images[_index].label}${widget.images.length > 1 ? '  ${_index + 1}/${widget.images.length}' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 64),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
