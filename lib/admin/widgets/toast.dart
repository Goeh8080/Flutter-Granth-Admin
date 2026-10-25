import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../services/panel_api.dart' show PanelApiException;
import '../theme/app_theme.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

OverlayEntry? _current;
Timer? _timer;

/// Glass toast that slides down from the top.
void showToast(String message, {bool error = false, BuildContext? context}) {
  final overlay =
      (context != null ? Overlay.maybeOf(context, rootOverlay: true) : null) ??
      rootNavKey.currentState?.overlay;
  if (overlay == null) return;
  _timer?.cancel();
  _current?.remove();
  final entry = OverlayEntry(
    builder: (_) => _Toast(message: message, error: error),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 3200), () {
    if (_current == entry) {
      entry.remove();
      _current = null;
    }
  });
}

void showError(Object e, {BuildContext? context}) {
  final msg = e is PanelApiException
      ? e.fullMessage
      : e is ApiException
      ? e.message
      : 'कुछ गलत हुआ / Something went wrong';
  showToast(msg, error: true, context: context);
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.error});
  final String message;
  final bool error;
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();
  late final CurvedAnimation _anim = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -1.4),
    end: Offset.zero,
  ).animate(_anim);
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) _c.reverse();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _c,
            child: Center(
              // No BackdropFilter (a live blur under a sliding toast); an almost opaque fill instead.
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: p.dark
                      ? const Color(0xF22A2530)
                      : const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.error
                          ? CupertinoIcons.exclamationmark_circle_fill
                          : CupertinoIcons.checkmark_circle_fill,
                      color: widget.error ? AppColors.red : AppColors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 14,
                            fontFamily: kFont,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
