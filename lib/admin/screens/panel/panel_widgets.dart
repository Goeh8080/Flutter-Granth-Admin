import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/panel_state.dart';
import '../../core/perf.dart';
import '../../models/panel_models.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import '../../../admin_ui/admin_data.dart';
import '../../../admin_ui/folder_picker.dart';

// ------------------------------------------------------------------ formatting

/// 3725 -> "1 घं 2 मि", 45 -> "45 से", 0 -> "0 से".
String fmtDur(int s) {
  if (s <= 0) return '0 से';
  if (s < 60) return '$s से';
  final m = s ~/ 60;
  if (m < 60) return '$m मि';
  final h = m ~/ 60;
  final rm = m % 60;
  if (h < 100) return rm == 0 ? '$h घं' : '$h घं $rm मि';
  return '$h घं';
}

/// 12345 -> "12,345".
String fmtNum(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// Friendly screen names for the analytics `scr` keys; unknown keys are shown as they are.
String screenLabel(String k) => switch (k) {
  'home' => 'होम',
  'topic' => 'विषय',
  'topics' => 'विषय',
  'granth' => 'ग्रंथ',
  'granths' => 'ग्रंथ',
  'praman' => 'प्रमाण',
  'pramans' => 'प्रमाण',
  'search' => 'खोज',
  'ai' => 'AI',
  'settings' => 'सेटिंग्स',
  'favourites' || 'favorites' => 'पसंदीदा',
  'pdf' => 'PDF',
  _ => k,
};

String shortTs(String iso) {
  if (iso.length >= 16)
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)}';
  return iso;
}

// ------------------------------------------------------------------ navigation

/// Pushes a control-server screen (counted, so session expiry knows to pop it).
Future<T?> pushPanel<T>(BuildContext context, Widget page) {
  final panel = AppScope.of(context).panel;
  panel.panelDepth++;
  return Navigator.of(context)
      .push<T>(
        CupertinoPageRoute<T>(
          settings: const RouteSettings(name: kPanelRouteName),
          builder: (_) => page,
        ),
      )
      .whenComplete(
        () =>
            panel.panelDepth = panel.panelDepth > 0 ? panel.panelDepth - 1 : 0,
      );
}

PanelState panelOf(BuildContext context) => AppScope.of(context).panel;
PanelApi apiOf(BuildContext context) => AppScope.of(context).panel.api;

// ------------------------------------------------------------------ loading page

/// A glass page that loads one value from the control server, shows loading / error / content,
/// supports pull-to-refresh and reloads itself after any edit ([PanelState.revision] changes).
class PanelPage<T> extends StatefulWidget {
  const PanelPage({
    super.key,
    required this.title,
    required this.load,
    required this.builder,
    this.trailing,
    this.floatingBuilder,
    this.previousPageTitle,
    this.bottomInset = 0,
    this.leading,
    this.header,
  });
  final String title;
  final Future<T> Function(PanelApi api) load;
  final List<Widget> Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;
  final Widget? trailing;
  final Widget? leading;
  final Widget? Function(BuildContext context, T? data)? floatingBuilder;
  final String? previousPageTitle;
  final double bottomInset;

  /// Sliver shown above the content in every state (e.g. a segment control).
  final Widget? header;

  @override
  State<PanelPage<T>> createState() => _PanelPageState<T>();
}

class _PanelPageState<T> extends State<PanelPage<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _rev = -1;
  int _seq = 0;
  late final PanelState _panel = AppScope.of(context).panel;
  // What the page body can show from the panel state; a change rebuilds, nothing else does.
  (bool, Object?, int) _sig = (false, null, 0);

  (bool, Object?, int) _signature() =>
      (_panel.loggedIn, _panel.me, _panel.alertCount);

  @override
  void initState() {
    super.initState();
    // Listens to the control-server state only (not to every AppState notification).
    _panel.addListener(_onPanel);
    _sig = _signature();
    _rev = _panel.revision;
    Future.microtask(() {
      if (mounted) unawaited(_run(_panel.api));
    });
  }

  void _onPanel() {
    if (!mounted) return;
    if (_panel.revision != _rev && _panel.loggedIn) {
      _rev = _panel.revision;
      unawaited(_run(_panel.api, silent: true));
    }
    final s = _signature();
    if (s != _sig) {
      _sig = s;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _panel.removeListener(_onPanel);
    super.dispose();
  }

  Future<void> _run(PanelApi api, {bool silent = false}) async {
    final my = ++_seq;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final d = await widget.load(api);
      if (!mounted || my != _seq) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reload() {
    final panel = AppScope.of(context).panel;
    _rev = panel.revision;
    return _run(panel.api, silent: _data != null);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> slivers;
    if (_data != null) {
      slivers = widget.builder(context, _data as T, _reload);
    } else if (_loading) {
      slivers = const [
        SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      ];
    } else {
      final e = _error;
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MessageView(
            icon: e is PanelApiException && e.isNetwork
                ? CupertinoIcons.wifi_slash
                : CupertinoIcons.exclamationmark_triangle,
            title: e is PanelApiException
                ? e.message
                : 'कुछ गलत हुआ / Something went wrong',
            subtitle: e is PanelApiException && e.errors.isNotEmpty
                ? e.errors.take(3).join('\n')
                : null,
            onRetry: _reload,
          ),
        ),
      ];
    }
    return GlassPage(
      title: widget.title,
      trailing: widget.trailing,
      leading: widget.leading,
      previousPageTitle: widget.previousPageTitle,
      bottomInset: widget.bottomInset,
      onRefresh: _reload,
      floating: widget.floatingBuilder?.call(context, _data),
      slivers: [?widget.header, ...slivers],
    );
  }
}

// ------------------------------------------------------------------ small widgets

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.color,
    this.onTap,
  });
  final IconData icon;
  final String label, value;
  final String? sub;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? AppColors.saffron;
    return PressableGlass(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: c),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.subtext),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: p.text,
                height: 1.15,
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.subtext),
            ),
        ],
      ),
    );
  }
}

/// Two-column grid of equal-height cards that never overflows on narrow phones.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.spacing = 10});
  final List<Widget> children;
  final double spacing;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

/// Horizontal bar list: label, proportional bar and a value text.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.rows, this.color, this.maxRows = 10});
  final List<BarRow> rows;
  final Color? color;
  final int maxRows;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? AppColors.saffron;
    final list = rows.take(maxRows).toList();
    final mx = list.fold<double>(0, (m, r) => r.value > m ? r.value : m);
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == list.length - 1 ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: p.subtext,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        list[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: p.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      list[i].text,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.subtext,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 6, color: p.separator),
                        FractionallySizedBox(
                          widthFactor: mx <= 0
                              ? 0
                              : (list[i].value / mx).clamp(0.02, 1.0),
                          child: Container(height: 6, color: c),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class BarRow {
  const BarRow(this.label, this.value, this.text);
  final String label;
  final double value;
  final String text;
}

/// Tiny column chart for a per-day series.
class MiniChart extends StatelessWidget {
  const MiniChart({
    super.key,
    required this.values,
    this.color,
    this.height = 64,
  });
  final List<int> values;
  final Color? color;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? AppColors.saffron;
    final mx = values.fold<int>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.6),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: mx == 0 ? 0.04 : (v / mx).clamp(0.04, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: v == 0 ? p.separator : c,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Glass card with a heading, used for dashboard sections.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.saffron),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon = CupertinoIcons.chart_bar});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.subtext),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: p.subtext, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row-style glass button used in menus.
class MenuRow extends StatelessWidget {
  const MenuRow(
    this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.sub,
    this.badge = 0,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final String? sub;
  final int badge;
  final bool destructive;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableGlass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        radius: 16,
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              icon,
              color: destructive ? AppColors.red : AppColors.saffron,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: destructive ? AppColors.red : p.text,
                      fontSize: 15.5,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      style: TextStyle(color: p.subtext, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Icon(CupertinoIcons.chevron_right, size: 15, color: p.subtext),
          ],
        ),
      ),
    );
  }
}

/// Selectable chip (filters).
class FilterChipX extends StatelessWidget {
  const FilterChipX(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? AppColors.saffron.withValues(alpha: 0.2)
              : p.fieldFill,
          border: Border.all(
            color: selected ? AppColors.saffron : p.glassBorder,
            width: 0.8,
          ),
        ),
        child: Text(
          count == null ? label : '$label · $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.saffron : p.text,
          ),
        ),
      ),
    );
  }
}

/// Cupertino-style segmented control with glass colours.
class Segments<T extends Object> extends StatelessWidget {
  const Segments({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: p.fieldFill,
        thumbColor: p.dark ? const Color(0xFF3A3340) : Colors.white,
        children: {
          for (final e in items.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                e.value,
                style: TextStyle(color: p.text, fontSize: 14),
              ),
            ),
        },
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ folder picker

/// Groups leaves by religion for pickers. `other` goes in its own "अन्य" group.
List<(String, List<PanelLeaf>)> groupLeaves(List<PanelLeaf> leaves) {
  final m = <String, List<PanelLeaf>>{};
  final order = <String>[];
  for (final l in leaves) {
    final k = l.isOther ? 'अन्य' : (l.religion.isEmpty ? 'अन्य' : l.religion);
    if (!m.containsKey(k)) order.add(k);
    (m[k] ??= []).add(l);
  }
  return [for (final k in order) (k, m[k]!)];
}

/// Label without the leading religion (shown under the religion heading).
String leafRest(PanelLeaf l) {
  if (l.isOther) return l.label;
  final parts = l.label.split('›').map((e) => e.trim()).toList();
  if (parts.length > 1 && parts.first == l.religion)
    return parts.sublist(1).join(' › ');
  return l.label;
}

/// Picks a folder (leaf) from a grouped Religion > Group list. Returns the leaf key.
Future<String?> pickLeaf(
  BuildContext context,
  List<PanelLeaf> leaves, {
  String? current,
  String title = 'फ़ोल्डर चुनें / Choose folder',
}) {
  // Round 2: the same file-manager style drill-down as the Granth tab (religion → group →
  // sub-folder, "यहाँ रखें" inside); the flat list below is only the fallback when the
  // folder structure is not loaded.
  if (AdminData.isSet && AdminData.I.structure.religions.isNotEmpty) {
    return showFolderPicker(
      context,
      structure: AdminData.I.structure,
      granthTitle: title,
      current: current,
    );
  }
  return showGlassSheet<String>(
    context,
    (ctx) => _LeafSheet(leaves: leaves, current: current, title: title),
  );
}

class _LeafSheet extends StatefulWidget {
  const _LeafSheet({required this.leaves, required this.title, this.current});
  final List<PanelLeaf> leaves;
  final String? current;
  final String title;
  @override
  State<_LeafSheet> createState() => _LeafSheetState();
}

class _LeafSheetState extends State<_LeafSheet> {
  String q = '';
  final _debounce = Debouncer();
  final _rows = Memo<String, List<Object>>();

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  /// Flat list of group headers (String) and leaves, so the ListView can build rows lazily.
  List<Object> _flat() => _rows.get(q.toLowerCase(), () {
    final ql = q.toLowerCase();
    final filtered = ql.isEmpty
        ? widget.leaves
        : widget.leaves
              .where((l) => l.label.toLowerCase().contains(ql))
              .toList();
    return [
      for (final g in groupLeaves(filtered)) ...[g.$1, ...g.$2],
    ];
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final rows = _flat();
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('बंद / Close'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CupertinoSearchTextField(
              style: TextStyle(color: p.text, fontFamily: kFont),
              backgroundColor: p.fieldFill,
              onChanged: (v) => _debounce(() {
                if (mounted) setState(() => q = v.trim());
              }),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? const MessageView(
                    icon: CupertinoIcons.folder,
                    title: 'कोई फ़ोल्डर नहीं मिला / No folder found',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      if (r is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.saffron,
                            ),
                          ),
                        );
                      }
                      final l = r as PanelLeaf;
                      return CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: 4,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.pop(context, l.key),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                leafRest(l) + (l.visible ? '' : '  (छिपा)'),
                                style: TextStyle(color: p.text, fontSize: 15),
                              ),
                            ),
                            if (l.key == widget.current)
                              const Icon(
                                CupertinoIcons.checkmark_alt,
                                color: AppColors.saffron,
                                size: 18,
                              ),
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

// ------------------------------------------------------------------ diff view

class DiffView extends StatelessWidget {
  const DiffView({
    super.key,
    required this.diff,
    this.leafLabels = const {},
    this.maxGranths = 40,
  });
  final PanelDiff diff;
  final Map<String, String> leafLabels;
  final int maxGranths;

  String _l(String k) => leafLabels[k] ?? k;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: p.subtext,
        ),
      ),
    );
    if (diff.isEmpty) {
      return const EmptyNote(
        'कोई बदलाव नहीं / No changes',
        icon: CupertinoIcons.checkmark_circle,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (diff.folders.isNotEmpty) ...[
          head('फ़ोल्डर / Folders (${diff.folders.length})'),
          for (final f in diff.folders)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Tag(
                        switch (f.change) {
                          'added' => 'नया',
                          'removed' => 'हटाया',
                          _ => 'बदला',
                        },
                        color: switch (f.change) {
                          'added' => AppColors.green,
                          'removed' => AppColors.red,
                          _ => AppColors.blue,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.title.isEmpty ? f.path : '${f.title}  (${f.path})',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.text, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  for (final x in f.fields)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Text(
                        '${x.field}: ${x.from} → ${x.to}',
                        style: TextStyle(color: p.subtext, fontSize: 12.5),
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (diff.granths.isNotEmpty) ...[
          head('ग्रंथ / Granths (${diff.granths.length})'),
          for (final g in diff.granths.take(maxGranths))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.title.isEmpty ? g.id : g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 14),
                  ),
                  if (g.leaf != null)
                    Text(
                      'फ़ोल्डर: ${_l(g.leaf!.from)} → ${_l(g.leaf!.to)}',
                      style: TextStyle(color: p.subtext, fontSize: 12.5),
                    ),
                  if (g.hidden != null)
                    Text(
                      'छिपा: ${g.hidden!.from} → ${g.hidden!.to}',
                      style: TextStyle(color: p.subtext, fontSize: 12.5),
                    ),
                ],
              ),
            ),
          if (diff.granths.length > maxGranths)
            Text(
              '+ ${diff.granths.length - maxGranths} और / more',
              style: TextStyle(color: p.subtext, fontSize: 12.5),
            ),
        ],
        if (diff.settings.isNotEmpty) ...[
          head('सेटिंग्स / Settings (${diff.settings.length})'),
          for (final s in diff.settings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${s.field}: ${s.from} → ${s.to}',
                style: TextStyle(color: p.text, fontSize: 13.5),
              ),
            ),
        ],
        if (diff.catalogTotal > 0) ...[
          const SizedBox(height: 10),
          Text(
            'छिपे ग्रंथ: ${diff.hiddenCount} / ${diff.catalogTotal}',
            style: TextStyle(color: p.subtext, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

Map<String, String> leafLabelMap(List<PanelLeaf> leaves) => {
  for (final l in leaves) l.key: l.label,
};

// ------------------------------------------------------------------ preview + publish

/// Opens the "Preview → Publish" sheet for the shared server draft.
/// Returns true when something was published (or the draft was discarded).
Future<bool> showPublishSheet(BuildContext context) async {
  final r = await showGlassSheet<bool>(context, (_) => const _PublishSheet());
  return r ?? false;
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet();
  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  final _note = TextEditingController();
  PanelDraft? _draft;
  Map<String, String> _labels = const {};
  Object? _error;
  bool _loading = true, _busy = false, _force = false, _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = apiOf(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await api.draft();
      Map<String, String> labels = const {};
      try {
        labels = leafLabelMap((await api.structure()).leaves);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _draft = d;
        _labels = labels;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _publish() async {
    final d = _draft;
    if (d == null) return;
    final panel = panelOf(context);
    final needsForce = d.diff.needsForce;
    if (needsForce && !_force) {
      showToast(
        '50% से ज़्यादा ग्रंथ छिप रहे हैं — "फ़ोर्स" चालू करें / Turn on force',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await panel.api.publish(
        note: _note.text,
        force: needsForce && _force,
      );
      panel.bump();
      if (!mounted) return;
      showToast(
        'प्रकाशित हुआ / Published v${r.version}${r.warnings.isEmpty ? '' : ' • ${r.warnings.first}'}',
      );
      Navigator.pop(context, true);
    } on PanelApiException catch (e) {
      if (e.code == 'no_changes') {
        panel.bump();
        showError(e);
      } else {
        showError(e);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(
      context,
      title: 'ड्राफ्ट रद्द करें? / Discard draft?',
      message: 'सभी बिना-प्रकाशित बदलाव हट जाएँगे। ऐप में कोई बदलाव नहीं होगा।',
      confirm: 'रद्द करें / Discard',
    );
    if (!ok || !mounted) return;
    final panel = panelOf(context);
    setState(() => _busy = true);
    try {
      await panel.api.discardDraft();
      panel.bump();
      if (!mounted) return;
      showToast('ड्राफ्ट रद्द / Draft discarded');
      Navigator.pop(context, true);
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final d = _draft;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('बंद'),
                  ),
                  Expanded(
                    child: Text(
                      'प्रीव्यू और प्रकाशन / Preview & Publish',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    onPressed:
                        (_busy || d == null || !d.exists || d.diff.isEmpty)
                        ? null
                        : _publish,
                    child: _busy
                        ? const CupertinoActivityIndicator()
                        : const Text(
                            'प्रकाशित',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: CupertinoActivityIndicator(radius: 14),
                    )
                  : _error != null
                  ? MessageView(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: _error is PanelApiException
                          ? (_error as PanelApiException).message
                          : 'कुछ गलत हुआ',
                      onRetry: _load,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Glass(
                            radius: 16,
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              d == null || !d.exists
                                  ? 'कोई ड्राफ्ट नहीं — सब कुछ पहले से प्रकाशित है।'
                                  : 'ये बदलाव अभी सिर्फ़ ड्राफ्ट में हैं। "प्रकाशित" दबाने पर v${d.nextVersion} बनेगा और यूज़र ऐप को मिलेगा।',
                              style: TextStyle(color: p.subtext, fontSize: 13),
                            ),
                          ),
                          if (d != null)
                            DiffView(diff: d.diff, leafLabels: _labels),
                          if (d != null && d.diff.warnings.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (final w in d.diff.warnings)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      CupertinoIcons
                                          .exclamationmark_triangle_fill,
                                      size: 15,
                                      color: AppColors.gold,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        w,
                                        style: TextStyle(
                                          color: p.text,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          if (d != null && d.exists && !d.diff.isEmpty) ...[
                            const SizedBox(height: 14),
                            GlassField(
                              label: 'नोट / Note (वैकल्पिक)',
                              controller: _note,
                              placeholder: 'जैसे: नए ग्रंथ जोड़े',
                            ),
                            if (d.diff.needsForce)
                              Glass(
                                radius: 14,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                tint: AppColors.red.withValues(alpha: 0.12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'फ़ोर्स: 50% से ज़्यादा ग्रंथ छिप जाएँगे — पक्का?',
                                        style: TextStyle(
                                          color: p.text,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    CupertinoSwitch(
                                      value: _force,
                                      activeTrackColor: AppColors.red,
                                      onChanged: (v) =>
                                          setState(() => _force = v),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          if (d != null && d.exists) ...[
                            const SizedBox(height: 10),
                            CupertinoButton(
                              onPressed: _busy ? null : _discard,
                              child: const Text(
                                'ड्राफ्ट रद्द करें / Discard draft',
                                style: TextStyle(color: AppColors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown when the shared draft has unpublished edits.
class DraftBanner extends StatelessWidget {
  const DraftBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final panel = AppScope.of(context).panel;
    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) => _banner(context, panel),
    );
  }

  Widget _banner(BuildContext context, PanelState panel) {
    final me = panel.me;
    final p = Palette.of(context);
    if (me == null || !me.hasDraft) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableGlass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () async {
          await showPublishSheet(context);
        },
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.doc_text_search,
              color: AppColors.gold,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ड्राफ्ट में बिना-प्रकाशित बदलाव हैं — देखें और प्रकाशित करें',
                style: TextStyle(color: p.text, fontSize: 14),
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 15, color: p.subtext),
          ],
        ),
      ),
    );
  }
}

/// Asks before logging out of the control server.
Future<bool> confirmLogout(BuildContext context) => confirmDialog(
  context,
  title: 'कंट्रोल से लॉगआउट? / Log out?',
  message: 'वेबसाइट वाला लॉगिन चालू रहेगा।',
  confirm: 'लॉगआउट / Logout',
);
