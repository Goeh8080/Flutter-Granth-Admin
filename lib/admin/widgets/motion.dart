import '../../widgets/overlays.dart' show confirmPopTitled;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass.dart';

/// Spring scale + fade dialog (iOS alert feel).
Future<T?> showGlassDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'dialog',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, a, b) => SafeArea(child: Center(child: builder(ctx))),
    transitionBuilder: (ctx, a, b, child) {
      final fade = CurvedAnimation(
        parent: a,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      final scale = CurvedAnimation(
        parent: a,
        curve: const SpringCurve(),
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween(begin: 0.86, end: 1.0).animate(scale),
          child: child,
        ),
      );
    },
  );
}

/// Bottom sheet that rises with a spring and fades/scales the content in.
Future<T?> showGlassSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool fullHeight = true,
}) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(_GlassSheetRoute<T>(builder, fullHeight));
}

class _GlassSheetRoute<T> extends PageRoute<T> {
  _GlassSheetRoute(this.builder, this.fullHeight);
  final WidgetBuilder builder;
  final bool fullHeight;

  @override
  bool get opaque => false;
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.3);
  @override
  String? get barrierLabel => 'sheet';
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: size.height - top - (fullHeight ? 12 : 120),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          // No BackdropFilter: a 30-sigma blur over a near-full-screen sheet re-rendered the whole
          // page behind it on every frame of the slide-in. A denser fill looks the same.
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: p.dark ? const Color(0xF21A1720) : const Color(0xF7FFF8F2),
              border: Border(top: BorderSide(color: p.glassBorder)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: p.separator,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Flexible(child: builder(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
    Widget child,
  ) {
    final slide = CurvedAnimation(
      parent: a,
      curve: const SpringCurve(damping: 0.82),
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(slide),
      child: FadeTransition(
        opacity: Tween(begin: 0.4, end: 1.0).animate(a),
        child: child,
      ),
    );
  }
}

/// Confirm dialog: Round 1 uses the user app's `confirmPop` card style (paper card, brown text,
/// OK / रद्द करें buttons). Returns true when confirmed. Every delete / destructive action goes
/// through here.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'हटाएँ / Delete',
  bool destructive = true,
}) => confirmPopTitled(
  context,
  title: title,
  message: message,
  confirm: confirm,
  destructive: destructive,
);

/// Asks for a number (used for "move to position").
Future<int?> numberDialog(
  BuildContext context, {
  required String title,
  String? hint,
  int? max,
}) async {
  final c = TextEditingController();
  final r = await showGlassDialog<int>(context, (ctx) {
    final p = Palette.of(ctx);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Glass(
        blur: 0,
        tint: Palette.of(ctx).dark
            ? const Color(0xF21F1B26)
            : const Color(0xF7FFF8F2),
        strong: true,
        radius: 24,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(fontSize: 13, color: p.subtext),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 14),
              CupertinoTextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                placeholder: max == null ? 'Position' : '1 – $max',
                style: TextStyle(color: p.text, fontFamily: kFont),
                decoration: BoxDecoration(
                  color: p.fieldFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  Expanded(
                    child: CupertinoButton.filled(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final v = int.tryParse(c.text.trim());
                        if (v == null || v < 1 || (max != null && v > max))
                          return;
                        Navigator.pop(ctx, v);
                      },
                      child: const Text('Move'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  });
  return r;
}

/// iOS-style action sheet with glass look.
class SheetAction {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback onTap;
  const SheetAction(
    this.label,
    this.icon,
    this.onTap, {
    this.destructive = false,
  });
}

Future<void> showActions(
  BuildContext context, {
  String? title,
  required List<SheetAction> actions,
}) {
  return showGlassSheet<void>(context, fullHeight: false, (ctx) {
    final p = Palette.of(ctx);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.subtext, fontSize: 13),
                ),
              ),
            for (final a in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PressableGlass(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  radius: 16,
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                  child: Row(
                    children: [
                      Icon(
                        a.icon,
                        color: a.destructive
                            ? AppColors.red
                            : AppColors.saffron,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          a.label,
                          style: TextStyle(
                            fontSize: 16,
                            color: a.destructive ? AppColors.red : p.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  });
}
