import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/perf.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'motion.dart';

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.radius = 14, this.width, this.height});
  final String? url;
  final BoxFit fit;
  final double radius;
  final double? width, height;

  /// Widget tests turn this off (no network/cache plugins there).
  static bool enabled = true;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget placeholder(IconData i) => Container(
      width: width,
      height: height,
      color: p.fieldFill,
      alignment: Alignment.center,
      child: Icon(i, color: p.subtext, size: 22),
    );
    if (url == null || !enabled) {
      return ClipRRect(borderRadius: BorderRadius.circular(radius), child: placeholder(CupertinoIcons.photo));
    }
    // Decode at display size (dpr-aware, capped) instead of the full-size source bitmap.
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final w = (width == null || !width!.isFinite) ? MediaQuery.sizeOf(context).width : width!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 100),
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        memCacheWidth: (w * dpr).round(),
        placeholder: (_, _) => placeholder(CupertinoIcons.photo),
        errorWidget: (_, _, _) => placeholder(CupertinoIcons.exclamationmark_triangle),
      ),
    );
  }
}

/// Rebuilds only this subtree when an optimistic show/hide toggle for ([kind], [id]) changes;
/// [builder] gets the displayed Active flag (the pending toggle wins over [server]).
class OptimisticActive extends StatelessWidget {
  const OptimisticActive({
    super.key,
    required this.kind,
    required this.id,
    required this.server,
    required this.builder,
  });
  final String kind;
  final int id;
  final bool server;
  final Widget Function(BuildContext context, bool active) builder;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: app.optimisticListenable,
      builder: (context, _, _) => builder(context, app.activeOf(kind, id, server)),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.active, {super.key});
  final bool active;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? AppColors.green : AppColors.red,
      boxShadow: [BoxShadow(color: (active ? AppColors.green : AppColors.red).withValues(alpha: 0.5), blurRadius: 6)],
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.color, this.onTap});
  final String text;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.saffron;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.25), width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small round glass icon button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton(this.icon, {super.key, required this.onTap, this.color, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final b = CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      onPressed: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.glassFill,
          border: Border.all(color: p.glassBorder, width: 0.7),
        ),
        child: Icon(icon, size: 19, color: color ?? AppColors.saffron),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: onPressed == null ? 0.5 : 1,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: busy ? null : onPressed,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [AppColors.saffron, AppColors.saffronDeep]),
            boxShadow: [
              BoxShadow(color: AppColors.saffron.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: busy
                ? const CupertinoActivityIndicator(color: Colors.white)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                      Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(40), child: CupertinoActivityIndicator(radius: 14)),
  );
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.title, this.subtitle, this.onRetry});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: p.subtext),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.subtext),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              CupertinoButton(onPressed: onRetry, child: const Text('फिर कोशिश करें / Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Glass text field with a label.
class GlassField extends StatefulWidget {
  const GlassField({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.maxLines = 1,
    this.keyboardType,
    this.required = false,
    this.obscure = false,
    this.prefix,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });
  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool required;
  final bool obscure;
  final IconData? prefix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  @override
  State<GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<GlassField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final label = widget.label, controller = widget.controller, placeholder = widget.placeholder;
    final maxLines = widget.maxLines, keyboardType = widget.keyboardType, required = widget.required;
    final obscure = widget.obscure, prefix = widget.prefix, textInputAction = widget.textInputAction;
    final onSubmitted = widget.onSubmitted, autofillHints = widget.autofillHints;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              required ? '$label *' : label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext),
            ),
          ),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            minLines: maxLines > 1 ? 2 : 1,
            maxLines: obscure ? 1 : maxLines,
            obscureText: obscure && !_show,
            keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            autofillHints: autofillHints,
            suffix: obscure
                ? CupertinoButton(
                    key: const ValueKey('toggle-password'),
                    padding: const EdgeInsets.only(right: 12),
                    minimumSize: Size.zero,
                    onPressed: () => setState(() => _show = !_show),
                    child: Icon(_show ? CupertinoIcons.eye_slash : CupertinoIcons.eye, color: p.subtext, size: 20),
                  )
                : null,
            prefix: prefix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(prefix, color: p.subtext, size: 20),
                  ),
            style: TextStyle(color: p.text, fontFamily: kFont, fontSize: 16, height: 1.45),
            placeholderStyle: TextStyle(color: p.subtext.withValues(alpha: 0.6), fontFamily: kFont, fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: p.fieldFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.glassBorder, width: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row that opens a picker, showing the selected value.
class PickerRow extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.required = false,
    this.onClear,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool required;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              required ? '$label *' : label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: p.fieldFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.glassBorder, width: 0.8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? '— चुनें / Select —',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: value == null ? p.subtext : p.text, fontSize: 15),
                    ),
                  ),
                  if (value != null && onClear != null)
                    GestureDetector(
                      onTap: onClear,
                      child: Icon(CupertinoIcons.xmark_circle_fill, color: p.subtext, size: 18),
                    ),
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_up_chevron_down, color: p.subtext, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active / In-Active switch row.
class ActiveSwitch extends StatelessWidget {
  const ActiveSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        radius: 14,
        child: Row(
          children: [
            StatusDot(value),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ? 'सक्रिय / Active (दिखेगा)' : 'निष्क्रिय / In-Active (छिपा)',
                style: TextStyle(color: p.text, fontSize: 15),
              ),
            ),
            CupertinoSwitch(value: value, activeTrackColor: AppColors.green, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Image chooser (gallery / camera) with preview of new or existing image.
class ImagePickField extends StatelessWidget {
  const ImagePickField({
    super.key,
    required this.label,
    required this.file,
    required this.onPicked,
    this.existingUrl,
    this.required = false,
  });
  final String label;
  final XFile? file;
  final String? existingUrl;
  final ValueChanged<XFile?> onPicked;
  final bool required;

  Future<void> _pick(BuildContext context) async {
    final picker = ImagePicker();
    Future<void> go(ImageSource s) async {
      try {
        final f = await picker.pickImage(source: s, imageQuality: 88, maxWidth: 2400);
        if (f != null) onPicked(f);
      } catch (_) {
        // permission denied or cancelled
      }
    }

    await showActions(
      context,
      title: label,
      actions: [
        SheetAction('गैलरी से चुनें / Gallery', CupertinoIcons.photo_on_rectangle, () => go(ImageSource.gallery)),
        SheetAction('कैमरा / Camera', CupertinoIcons.camera, () => go(ImageSource.camera)),
        if (file != null) SheetAction('हटाएँ / Remove', CupertinoIcons.trash, () => onPicked(null), destructive: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget preview;
    if (file != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(File(file!.path), height: 180, width: double.infinity, fit: BoxFit.cover),
      );
    } else if (existingUrl != null) {
      preview = Stack(
        children: [
          NetImage(existingUrl, height: 180, width: double.infinity),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: const Text('वर्तमान / Current', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ],
      );
    } else {
      preview = SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.camera_on_rectangle, size: 34, color: AppColors.saffron.withValues(alpha: 0.9)),
              const SizedBox(height: 6),
              Text('टैप करके चुनें / Tap to choose', style: TextStyle(color: p.subtext, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              required ? '$label *' : label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext),
            ),
          ),
          GestureDetector(
            onTap: () => _pick(context),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: p.fieldFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.glassBorder, width: 0.8),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: KeyedSubtree(key: ValueKey(file?.path ?? existingUrl ?? 'none'), child: preview),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field with datalist-like suggestions (title matches from the cache).
class SuggestSearchField extends StatefulWidget {
  const SuggestSearchField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.onChanged,
    required this.onSubmitted,
    this.placeholder = 'खोजें / Search',
  });
  final TextEditingController controller;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final String placeholder;
  @override
  State<SuggestSearchField> createState() => _SuggestSearchFieldState();
}

class _SuggestSearchFieldState extends State<SuggestSearchField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final q = widget.controller.text.trim().toLowerCase();
    final matches = (!_focus.hasFocus || q.isEmpty)
        ? const <String>[]
        : widget.suggestions.where((s) => s.toLowerCase().contains(q) && s.toLowerCase() != q).take(6).toList();
    return Column(
      children: [
        CupertinoSearchTextField(
          controller: widget.controller,
          focusNode: _focus,
          placeholder: widget.placeholder,
          style: TextStyle(color: p.text, fontFamily: kFont),
          backgroundColor: p.fieldFill,
          borderRadius: BorderRadius.circular(14),
          onChanged: (v) {
            setState(() {});
            widget.onChanged(v);
          },
          onSubmitted: (v) {
            _focus.unfocus();
            widget.onSubmitted(v);
          },
          onSuffixTap: () {
            widget.controller.clear();
            setState(() {});
            widget.onChanged('');
            widget.onSubmitted('');
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: matches.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Glass(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    radius: 14,
                    strong: true,
                    child: Column(
                      children: [
                        for (final m in matches)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                            onPressed: () {
                              widget.controller.text = m;
                              _focus.unfocus();
                              widget.onChanged(m);
                              widget.onSubmitted(m);
                            },
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.search, size: 15, color: p.subtext),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m.replaceAll('\n', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.text, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Generic searchable picker sheet. Returns the chosen item.
Future<T?> pickFromList<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
}) {
  return showGlassSheet<T>(
    context,
    (ctx) => _PickerSheet<T>(title: title, items: items, labelOf: labelOf, subtitleOf: subtitleOf),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({required this.title, required this.items, required this.labelOf, this.subtitleOf});
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String q = '';
  final _debounce = Debouncer();
  final _filtered = Memo<String, List<T>>();

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final list = _filtered.get(
      q.toLowerCase(),
      () => q.isEmpty
          ? widget.items
          : widget.items.where((e) => widget.labelOf(e).toLowerCase().contains(q.toLowerCase())).toList(),
    );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                  ),
                ),
                CupertinoButton(onPressed: () => Navigator.pop(context), child: const Text('बंद / Close')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CupertinoSearchTextField(
              autofocus: false,
              style: TextStyle(color: p.text, fontFamily: kFont),
              backgroundColor: p.fieldFill,
              onChanged: (v) => _debounce(() {
                if (mounted) setState(() => q = v.trim());
              }),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.separator),
              itemBuilder: (_, i) {
                final e = list[i];
                return CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  onPressed: () => Navigator.pop(context, e),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.labelOf(e).replaceAll('\n', ' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.text, fontSize: 15),
                            ),
                            if (widget.subtitleOf != null)
                              Text(widget.subtitleOf!(e), style: TextStyle(color: p.subtext, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(CupertinoIcons.chevron_right, size: 14, color: p.subtext),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header text.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.subtext),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
