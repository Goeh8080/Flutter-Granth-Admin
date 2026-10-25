import 'package:flutter/material.dart';

import '../models/structure.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/group_icon.dart';
import '../widgets/overlays.dart';
import '../widgets/religion_symbol.dart';

/// File-manager style folder picker (Granth tab → "फ़ोल्डर बदलें").
///
/// Level 0 lists every religion (+ अन्य) as icon cards; a tap goes INSIDE (groups, then
/// sub-folders, as deep as the structure goes). The folder you are in is shown as a
/// breadcrumb; "पीछे" goes up one level (only at the top does it close the sheet). A granth can
/// only live in a leaf folder (a group without sub-groups, a sub-group, or अन्य), so the
/// "यहाँ रखें" bar appears whenever the open folder is such a leaf.
///
/// Returns the chosen leaf key (`religion/group[/sub]` or [kOtherId]), or null when closed.
Future<String?> showFolderPicker(
  BuildContext context, {
  required Structure structure,
  required String granthTitle,
  required String? current,
  int Function(List<String> path)? countFor,
}) => showPop<String>(
  context,
  (ctx) => FolderPickerSheet(
    structure: structure,
    granthTitle: granthTitle,
    current: current,
    countFor: countFor,
    onPick: (k) => Navigator.pop(ctx, k),
    onClose: () => Navigator.pop(ctx),
  ),
);

/// One folder in the list.
class FolderEntry {
  const FolderEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.isLeaf,
    this.religion,
    this.tone = 'maroon',
  });
  final String id;
  final String title;
  final String icon;

  /// A folder granths can be placed in (it has no sub-folders).
  final bool isLeaf;

  /// Set for the top level (drawn with the religion symbol).
  final ShelfReligion? religion;
  final String tone;
}

/// The folder-tree maths of the picker (pure, so it is unit-tested).
class FolderTree {
  const FolderTree(this.structure);
  final Structure structure;

  /// Children of the folder at [path] (empty path = the top level).
  List<FolderEntry> children(List<String> path) {
    if (path.isEmpty) {
      return [
        for (final r in structure.religions)
          FolderEntry(
            id: r.id,
            title: r.title,
            icon: r.icon,
            isLeaf: false,
            religion: r,
            tone: r.tone,
          ),
        FolderEntry(
          id: kOtherId,
          title: structure.other.title,
          icon: structure.other.icon,
          isLeaf: true,
        ),
      ];
    }
    final g = _group(path);
    if (path.first == kOtherId) return const [];
    final List<ShelfGroup> groups = path.length == 1
        ? (structure.religion(path.first)?.groups ?? const [])
        : (g?.subgroups ?? const []);
    return [
      for (final e in groups)
        FolderEntry(
          id: e.id,
          title: e.title,
          icon: e.icon,
          isLeaf: !e.hasSubgroups,
        ),
    ];
  }

  ShelfGroup? _group(List<String> path) {
    if (path.length < 2) return null;
    ShelfGroup? g = structure
        .religion(path.first)
        ?.groups
        .where((e) => e.id == path[1])
        .firstOrNull;
    for (var i = 2; i < path.length && g != null; i++) {
      g = g.subgroups.where((e) => e.id == path[i]).firstOrNull;
    }
    return g;
  }

  /// Display names along [path] (religion, group, sub-group).
  List<String> titles(List<String> path) {
    if (path.isEmpty) return const [];
    if (path.first == kOtherId) return [structure.other.title];
    final r = structure.religion(path.first);
    final out = <String>[r?.title ?? path.first];
    ShelfGroup? g;
    for (var i = 1; i < path.length; i++) {
      final list = i == 1
          ? (r?.groups ?? const [])
          : (g?.subgroups ?? const []);
      g = list.where((e) => e.id == path[i]).firstOrNull;
      out.add(g?.title ?? path[i]);
    }
    return out;
  }

  /// True when granths can be placed in the folder at [path].
  bool isLeaf(List<String> path) {
    if (path.isEmpty) return false;
    if (path.first == kOtherId) return true;
    if (path.length == 1) return false;
    final g = _group(path);
    return g != null && !g.hasSubgroups;
  }

  /// The leaf key of a leaf folder at [path] (`other`, `r/g`, `r/g/s`).
  String keyOf(List<String> path) =>
      path.first == kOtherId ? kOtherId : path.join('/');

  /// The path of a leaf key (the inverse of [keyOf]).
  List<String> pathOf(String? key) => key == null || key.isEmpty
      ? const []
      : key == kOtherId
      ? const [kOtherId]
      : key.split('/');
}

class FolderPickerSheet extends StatefulWidget {
  const FolderPickerSheet({
    super.key,
    required this.structure,
    required this.granthTitle,
    required this.current,
    required this.onPick,
    required this.onClose,
    this.countFor,
    this.startAtCurrent = false,
  });
  final Structure structure;
  final String granthTitle;
  final String? current;
  final void Function(String key) onPick;
  final VoidCallback onClose;
  final int Function(List<String> path)? countFor;

  /// Open inside the folder the granth is in now (default: the religions level).
  final bool startAtCurrent;

  @override
  State<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<FolderPickerSheet> {
  late final FolderTree tree = FolderTree(widget.structure);
  late List<String> path = widget.startAtCurrent
      ? tree.pathOf(widget.current)
      : const [];

  List<String> get _cur => tree.pathOf(widget.current);

  bool _onCurrentPath(List<String> p) {
    final c = _cur;
    if (p.length > c.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (p[i] != c[i]) return false;
    }
    return true;
  }

  void _go(List<String> p) => setState(() => path = p);

  void _back() {
    if (path.isEmpty) {
      widget.onClose();
    } else {
      _go(path.sublist(0, path.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = tree.titles(path);
    final leaf = tree.isLeaf(path);
    final here = leaf && widget.current == tree.keyOf(path);
    final kids = tree.children(path);
    return SheetCard(
      children: [
        SheetHead(title: 'फ़ोल्डर चुनें', onBack: _back),
        Text(
          widget.granthTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GText.sans(size: 14, color: GColors.muted),
        ),
        const SizedBox(height: 8),
        _Crumbs(
          key: const ValueKey('fp-crumbs'),
          titles: titles,
          onTap: (i) => _go(i < 0 ? const [] : path.sublist(0, i + 1)),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: KeyedSubtree(
              key: ValueKey('fp-level-${path.join('/')}'),
              child: kids.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        leaf
                            ? (here
                                  ? 'ग्रंथ अभी इसी फ़ोल्डर में है'
                                  : 'इस फ़ोल्डर में ग्रंथ रखने के लिए नीचे का बटन दबाएँ')
                            : 'इसके अंदर कोई फ़ोल्डर नहीं',
                        textAlign: TextAlign.center,
                        style: GText.sans(size: 14, color: GColors.muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: kids.length,
                      itemBuilder: (context, i) {
                        final e = kids[i];
                        final p = [...path, e.id];
                        return _Row(
                          key: ValueKey('fp-row-${p.join('/')}'),
                          entry: e,
                          here: _onCurrentPath(p),
                          count: widget.countFor?.call(p),
                          onTap: () => _go(p),
                        );
                      },
                    ),
            ),
          ),
        ),
        if (leaf) ...[
          const SizedBox(height: 10),
          Pill(
            key: const ValueKey('fp-paste'),
            icon: 'check',
            label: here ? 'अभी यहीं है' : 'यहाँ रखें  (${titles.join(' › ')})',
            tone: here ? PillTone.plain : PillTone.maroon,
            fontSize: 14,
            minHeight: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            weight: FontWeight.w800,
            maxLines: 2,
            onTap: () => widget.onPick(tree.keyOf(path)),
          ),
        ],
      ],
    );
  }
}

class _Crumbs extends StatelessWidget {
  const _Crumbs({super.key, required this.titles, required this.onTap});
  final List<String> titles;

  /// Index of the tapped crumb; -1 = the top.
  final void Function(int i) onTap;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int i, bool last) => Pressable(
      scale: 0.96,
      onTap: last ? null : () => onTap(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: GText.sans(
            size: 13,
            weight: last ? FontWeight.w800 : FontWeight.w600,
            color: last ? GColors.maroon : GColors.muted,
          ),
        ),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        chip('सभी फ़ोल्डर', -1, titles.isEmpty),
        for (var i = 0; i < titles.length; i++) ...[
          Text('›', style: GText.sans(size: 13, color: GColors.muted)),
          chip(titles[i], i, i == titles.length - 1),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.entry,
    required this.here,
    required this.onTap,
    this.count,
  });
  final FolderEntry entry;
  final bool here;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final tone = switch (e.tone) {
      'saffron' => Tone.saffron,
      'gold' => Tone.gold,
      _ => Tone.maroon,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        scale: 0.98,
        onTap: onTap,
        child: RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: here ? const Color(0xFFFFF4EA) : GColors.paper,
              border: Border.all(
                color: here ? GColors.maroon : const Color(0xFFE7D7B8),
                width: here ? 1.6 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                e.religion != null
                    ? ReligionSymbol(e.icon, tone: tone, size: 44)
                    : GroupIcon(e.icon, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GText.sans(
                          size: 15,
                          weight: FontWeight.w700,
                          color: GColors.text,
                        ),
                      ),
                      if (here || count != null)
                        Text(
                          [
                            if (here) 'ग्रंथ यहाँ है',
                            if (count != null) '$count ग्रंथ',
                          ].join(' • '),
                          style: GText.sans(
                            size: 12,
                            weight: here ? FontWeight.w800 : FontWeight.w500,
                            color: here ? GColors.maroon : GColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (here && e.isLeaf)
                  GIcon('check', size: 16, color: GColors.maroon)
                else
                  GIcon('chevron-right', size: 18, color: GColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
