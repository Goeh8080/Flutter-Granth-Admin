import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/perf.dart';
import '../../models/panel_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/grid_kit.dart';
import '../../widgets/icons/folder_tokens.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import '../../services/panel_api.dart';
import 'panel_widgets.dart';

/// A not-yet-saved change to one granth (held on the phone until "Preview").
class PendingGranth {
  PendingGranth({this.leaf, this.hidden});
  String? leaf;
  bool? hidden;
  bool get isEmpty => leaf == null && hidden == null;
}

/// Server-side sort keys (`GET /granths?sort=`) with their labels; `number` = catalogue number, #1 first.
const kGranthSorts = <String, String>{
  'number': 'नंबर (कैटलॉग)',
  'title': 'नाम (अ–ज्ञ)',
  'opens': 'ज़्यादा खुले (7 दिन)',
  'watch': 'ज़्यादा समय (7 दिन)',
  'praman': 'प्रमाण संख्या',
  'newest': 'सबसे नए',
  'id': 'ID (संख्या)',
};

/// Default direction per sort key (CONTRACT 3.5): asc for number/id/title, desc for the rest.
String defaultOrder(String sort) =>
    const {'number', 'position', 'id', 'title'}.contains(sort) ? 'asc' : 'desc';

enum GranthFilter { all, isNew, other, hidden, noPraman }

/// Pure filter used by the screen (and unit-tested).
List<PanelGranth> filterGranths(
  List<PanelGranth> all, {
  GranthFilter filter = GranthFilter.all,
  String query = '',
  String? leaf,
  Map<String, PendingGranth> pending = const {},

  /// Several filters at once (all must match); combined with [filter].
  Set<GranthFilter> filters = const {},
}) {
  final q = query.trim().toLowerCase();
  bool hiddenOf(PanelGranth g) => pending[g.id]?.hidden ?? g.hidden;
  String leafOf(PanelGranth g) => pending[g.id]?.leaf ?? g.leaf;
  bool passes(GranthFilter f, PanelGranth g) {
    switch (f) {
      case GranthFilter.all:
        return true;
      case GranthFilter.isNew:
        return g.isNew;
      case GranthFilter.other:
        return leafOf(g) == 'other';
      case GranthFilter.hidden:
        return hiddenOf(g);
      case GranthFilter.noPraman:
        return g.noPraman;
    }
  }

  return all.where((g) {
    if (!passes(filter, g)) return false;
    for (final f in filters) {
      if (!passes(f, g)) return false;
    }
    if (leaf != null && leafOf(g) != leaf) return false;
    if (q.isNotEmpty &&
        !(g.title.toLowerCase().contains(q) ||
            g.author.toLowerCase().contains(q) ||
            g.id == q)) {
      return false;
    }
    return true;
  }).toList();
}

/// How many granths would be hidden after the pending edits.
int hiddenAfter(List<PanelGranth> all, Map<String, PendingGranth> pending) =>
    all.where((g) => pending[g.id]?.hidden ?? g.hidden).length;

class PanelGranthsScreen extends StatefulWidget {
  const PanelGranthsScreen({super.key});
  @override
  State<PanelGranthsScreen> createState() => _PanelGranthsScreenState();
}

class _PanelGranthsScreenState extends State<PanelGranthsScreen> {
  final pending = <String, PendingGranth>{};
  final selected = <String>{};
  final Set<GranthFilter> filters = {};
  String sort = 'number';
  String order = 'asc';
  int _cols = 2;
  String query = '';
  String? leafFilter;
  PanelGranthList? _data;
  bool _saving = false;
  // Search is applied 250 ms after typing stops; the filtered list and chip counts are
  // computed once per data/filter change instead of on every rebuild.
  final _debounce = Debouncer();
  final _listMemo = Memo<Object, List<PanelGranth>>();
  final _countMemo = Memo<Object, Map<GranthFilter, int>>();
  final _hiddenMemo = Memo<Object, int>();
  int _pendingRev = 0;

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  void _clearPending() => setState(() {
    pending.clear();
    _pendingRev++;
  });

  @override
  void initState() {
    super.initState();
    readGridCols(kGridPrefPanelGranths, 2).then((v) {
      if (mounted && v != _cols) setState(() => _cols = v);
    });
  }

  void _setCols(int v) {
    setState(() => _cols = v);
    saveGridCols(kGridPrefPanelGranths, v);
  }

  void _toggleFilter(GranthFilter f) =>
      setState(() => filters.contains(f) ? filters.remove(f) : filters.add(f));

  void _edit(Iterable<String> ids, {String? leaf, bool? hidden}) {
    setState(() {
      for (final id in ids) {
        final e = pending.putIfAbsent(id, PendingGranth.new);
        if (leaf != null) e.leaf = leaf;
        if (hidden != null) e.hidden = hidden;
      }
      _pendingRev++;
      _prune();
    });
  }

  /// Drops pending values that equal what the server already has.
  void _prune() {
    final d = _data;
    if (d == null) return;
    final byId = {for (final g in d.items) g.id: g};
    pending.removeWhere((id, e) {
      final g = byId[id];
      if (g == null) return true;
      if (e.leaf == g.leaf) e.leaf = null;
      if (e.hidden == g.hidden) e.hidden = null;
      return e.isEmpty;
    });
  }

  Future<void> _preview() async {
    final d = _data;
    final panel = panelOf(context);
    if (pending.isNotEmpty && d != null) {
      final total = d.items.length;
      final hidden = hiddenAfter(d.items, pending);
      if (total > 0 && hidden * 10 > total * 9) {
        showToast(
          '90% से ज़्यादा ग्रंथ छिपाना मना है / Cannot hide more than 90%',
          error: true,
        );
        return;
      }
      setState(() => _saving = true);
      try {
        // Group identical edits so one call covers up to 300 granths.
        final groups = <String, List<String>>{};
        for (final e in pending.entries) {
          final key = '${e.value.leaf ?? ''}|${e.value.hidden ?? ''}';
          (groups[key] ??= []).add(e.key);
        }
        for (final entry in groups.entries) {
          final sample = pending[entry.value.first]!;
          for (var i = 0; i < entry.value.length; i += 300) {
            final chunk = entry.value.sublist(
              i,
              i + 300 > entry.value.length ? entry.value.length : i + 300,
            );
            await panel.api.bulkGranths(
              chunk,
              leaf: sample.leaf,
              hidden: sample.hidden,
            );
          }
        }
        pending.clear();
        _pendingRev++;
        selected.clear();
        panel.bump();
      } on PanelApiException catch (e) {
        showError(e);
        if (mounted) setState(() => _saving = false);
        return;
      }
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    await showPublishSheet(context);
  }

  Future<void> _moveSelected(PanelGranthList d) async {
    final k = await pickLeaf(
      context,
      d.leaves,
      title: '${selected.length} ग्रंथ कहाँ ले जाएँ?',
    );
    if (k == null) return;
    _edit(selected.toList(), leaf: k);
    setState(selected.clear);
  }

  void _pickSort() => showActions(
    context,
    title: 'क्रम / Sort',
    actions: [
      for (final e in kGranthSorts.entries)
        SheetAction(
          e.value,
          e.key == sort ? CupertinoIcons.checkmark : CupertinoIcons.sort_down,
          () => setState(() {
            sort = e.key;
            order = defaultOrder(e.key);
          }),
        ),
    ],
  );

  Future<void> _pickFilterLeaf(PanelGranthList d) async {
    final k = await pickLeaf(
      context,
      d.leaves,
      current: leafFilter,
      title: 'फ़ोल्डर से छानें',
    );
    if (k != null) setState(() => leafFilter = k);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<PanelGranthList>(
      key: ValueKey('granths$sort$order'),
      title: 'ग्रंथ / Granths',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.granths(sort: sort, order: order),
      trailing: selected.isEmpty
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(selected.clear),
              child: const Text('चयन हटाएँ'),
            ),
      floatingBuilder: (context, d) => Positioned(
        left: 14,
        right: 14,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
        child: _bottomBar(context, d),
      ),
      builder: (context, d, reload) {
        _data = d;
        final leafLabels = leafLabelMap(d.leaves);
        final fkey = (filters.map((f) => f.index).toList()..sort()).join(',');
        final list = _listMemo.get(
          (d.items, _pendingRev, fkey, query, leafFilter),
          () => filterGranths(
            d.items,
            filters: filters,
            query: query,
            leaf: leafFilter,
            pending: pending,
          ),
        );
        final counts = _countMemo.get((d.items, _pendingRev), () {
          int one(GranthFilter f) =>
              filterGranths(d.items, filter: f, pending: pending).length;
          return {
            GranthFilter.isNew: one(GranthFilter.isNew),
            GranthFilter.other: one(GranthFilter.other),
            GranthFilter.hidden: one(GranthFilter.hidden),
            GranthFilter.noPraman: one(GranthFilter.noPraman),
          };
        });
        int count(GranthFilter f) => counts[f] ?? 0;
        final hiddenNow = _hiddenMemo.get((
          d.items,
          _pendingRev,
        ), () => hiddenAfter(d.items, pending));
        Widget chip(String label, GranthFilter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChipX(
            label,
            selected: filters.contains(f),
            count: count(f),
            onTap: () => _toggleFilter(f),
          ),
        );
        return [
          // The toolbar scrolls away with the list (not sticky).
          PadSliver(
            child: SliverList(
              delegate: SliverChildListDelegate([
                const DraftBanner(),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoSearchTextField(
                        placeholder: 'ग्रंथ या लेखक खोजें',
                        style: TextStyle(color: p.text, fontFamily: kFont),
                        backgroundColor: p.fieldFill,
                        onChanged: (v) => _debounce(() {
                          if (mounted) setState(() => query = v);
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GridSwitch(cols: _cols, onChanged: _setCols),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChipX(
                          'सब',
                          selected: filters.isEmpty,
                          count: d.items.length,
                          onTap: () => setState(filters.clear),
                        ),
                      ),
                      chip('नया', GranthFilter.isNew),
                      chip('अन्य', GranthFilter.other),
                      chip('छिपा', GranthFilter.hidden),
                      chip('बिना प्रमाण', GranthFilter.noPraman),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: PressableGlass(
                        radius: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onTap: () => _pickFilterLeaf(d),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.folder,
                              size: 18,
                              color: AppColors.saffron,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                leafFilter == null
                                    ? 'सभी फ़ोल्डर'
                                    : (leafLabels[leafFilter] ?? leafFilter!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.text, fontSize: 14),
                              ),
                            ),
                            const Icon(CupertinoIcons.chevron_down, size: 14),
                          ],
                        ),
                      ),
                    ),
                    if (leafFilter != null)
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 10),
                        minimumSize: Size.zero,
                        onPressed: () => setState(() => leafFilter = null),
                        child: const Icon(
                          CupertinoIcons.clear_circled_solid,
                          color: AppColors.red,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChipX(
                      'क्रम: ${kGranthSorts[sort] ?? sort} ▾',
                      selected: false,
                      onTap: _pickSort,
                    ),
                    const SizedBox(width: 8),
                    FilterChipX(
                      order == 'asc' ? '↑ बढ़ते' : '↓ घटते',
                      selected: false,
                      onTap: () => setState(
                        () => order = order == 'asc' ? 'desc' : 'asc',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${list.length} ग्रंथ • छिपे: $hiddenNow / ${d.items.length}${selected.isEmpty ? '  (लंबा दबाकर कई चुनें)' : ''}',
                  style: TextStyle(color: p.subtext, fontSize: 12.5),
                ),
                if (d.items.isNotEmpty && hiddenNow * 2 > d.items.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '⚠ 50% से ज़्यादा ग्रंथ छिपे हैं — प्रकाशित करते समय "फ़ोर्स" चाहिए होगा।',
                      style: TextStyle(color: AppColors.red, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 10),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                icon: CupertinoIcons.book,
                title: 'कोई ग्रंथ नहीं मिला',
                subtitle: 'फ़िल्टर या खोज बदलकर देखें',
              ),
            )
          else
            PadSliver(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              child: GridRowsSliver(
                cols: _cols,
                count: list.length,
                itemBuilder: (context, i) {
                  final g = list[i];
                  final e = pending[g.id];
                  return _GranthCard(
                    g: g,
                    cols: _cols,
                    total: d.total,
                    leafLabel: e?.leaf != null
                        ? (leafLabels[e!.leaf!] ?? e.leaf!)
                        : g.leafLabel,
                    hidden: e?.hidden ?? g.hidden,
                    changed: e != null,
                    selected: selected.contains(g.id),
                    selecting: selected.isNotEmpty,
                    onToggleSelect: () => setState(
                      () => selected.contains(g.id)
                          ? selected.remove(g.id)
                          : selected.add(g.id),
                    ),
                    onMove: () async {
                      final k = await pickLeaf(
                        context,
                        d.leaves,
                        current: e?.leaf ?? g.leaf,
                        title: g.title,
                      );
                      if (k != null) _edit([g.id], leaf: k);
                    },
                    onVisible: (v) => _edit([g.id], hidden: !v),
                    onRemove: () async {
                      final ok = await confirmDialog(
                        context,
                        title: '"${g.title.isEmpty ? g.id : g.title}" हटाएँ?',
                        message: 'ग्रंथ ऐप में छिप जाएगा (हटाना = छिपाना)। प्रीव्यू/प्रकाशित करने तक बदलाव लागू नहीं होगा।',
                        confirm: 'छिपाएँ / Hide',
                      );
                      if (ok) _edit([g.id], hidden: true);
                    },
                  );
                },
              ),
            ),
        ];
      },
    );
  }

  Widget _bottomBar(BuildContext context, PanelGranthList? d) {
    final p = Palette.of(context);
    final me = panelOf(context).me;
    if (d != null && selected.isNotEmpty) {
      return Glass(
        blur: 0,
        tint: p.dark ? const Color(0xF2262230) : const Color(0xF5FFFFFF),
        strong: true,
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${selected.length} चुने',
                style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => _moveSelected(d),
              child: const Text('फ़ोल्डर'),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                _edit(selected.toList(), hidden: true);
                setState(selected.clear);
              },
              child: const Text('छिपाएँ'),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                _edit(selected.toList(), hidden: false);
                setState(selected.clear);
              },
              child: const Text('दिखाएँ'),
            ),
          ],
        ),
      );
    }
    final n = pending.length;
    final draft = me?.hasDraft ?? false;
    if (n == 0 && !draft) return const SizedBox.shrink();
    return Glass(
      blur: 0,
      tint: p.dark ? const Color(0xF2262230) : const Color(0xF5FFFFFF),
      strong: true,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              n > 0
                  ? '$n ग्रंथ में बदलाव सहेजे नहीं गए'
                  : 'ड्राफ्ट में बदलाव बाकी हैं',
              style: TextStyle(
                color: p.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          if (n > 0)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _saving ? null : _clearPending,
              child: const Text(
                'हटाएँ',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(18),
            onPressed: _saving ? null : _preview,
            child: _saving
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Text('प्रीव्यू / Preview'),
          ),
        ],
      ),
    );
  }
}

/// Cover card of the reader app (tokens §4) with only admin buttons in the footer.
class _GranthCard extends StatelessWidget {
  const _GranthCard({
    required this.g,
    required this.cols,
    required this.total,
    required this.leafLabel,
    required this.hidden,
    required this.changed,
    required this.selected,
    required this.selecting,
    required this.onToggleSelect,
    required this.onMove,
    required this.onVisible,
    required this.onRemove,
  });
  final PanelGranth g;
  final int cols, total;
  final String leafLabel;
  final bool hidden, changed, selected, selecting;
  final VoidCallback onToggleSelect, onMove, onRemove;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // inner width of one card (page padding 16, gaps per tokens, card padding 10/16)
    final inner =
        (width - 32 - gridGap(cols) * (cols - 1)) / cols -
        (cols == 1 ? 32 : 20);
    final tiny = inner <= 155;
    final titleSize = tiny
        ? 12.0
        : (cols == 1 ? 18.0 : (cols == 2 ? 15.0 : 13.0));
    final title = g.title.isEmpty ? g.id : g.title;
    final label = leafLabel.isEmpty ? g.leaf : leafLabel;
    final compact = cols == 3 || tiny; // icon-only admin buttons
    return PaperCard(
      key: ValueKey('granth-card-${g.id}'),
      dim: hidden,
      selected: selected,
      padding: EdgeInsets.all(cols == 1 ? 16 : 10),
      onTap: selecting ? onToggleSelect : onMove,
      onLongPress: onToggleSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 20,
                color: selected ? GColors.saffron : GColors.muted,
              ),
            ),
          Text(
            g.position == null ? title : '${g.position}. $title',
            maxLines: tiny ? 4 : 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kSerif,
              color: GColors.maroon,
              fontSize: titleSize,
              height: 1.3,
            ),
          ),
          if (g.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      CupertinoIcons.pencil,
                      size: 14,
                      color: GColors.saffronDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      g.author,
                      maxLines: tiny ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kFont,
                        fontWeight: FontWeight.w700,
                        color: GColors.saffronDark,
                        fontSize: cols == 1 ? 13 : 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          CoverImage(g.cover),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _Flag(label, GColors.muted, icon: CupertinoIcons.folder_fill),
              if (g.isNew) const _Flag('नया', Color(0xFF2E9B4F)),
              if (g.noPraman) const _Flag('बिना प्रमाण', GColors.saffronDark),
              if (hidden) const _Flag('छिपा', Color(0xFFB3261E)),
              if (changed) const _Flag('बदला', GColors.saffron),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: GColors.creamDark)),
            ),
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (g.pramanCount > 0)
                  CardPill(
                    '${g.pramanCount} प्रमाण',
                    icon: CupertinoIcons.photo,
                    tone: PillTone.maroon,
                    cols: cols,
                    tiny: tiny,
                  ),
                if (g.position != null)
                  CardPill(
                    '${g.position}/$total',
                    icon: CupertinoIcons.collections,
                    cols: cols,
                    tiny: tiny,
                  ),
                CardPill(
                  compact ? '' : 'फ़ोल्डर',
                  icon: CupertinoIcons.pencil,
                  tone: PillTone.topic,
                  onTap: onMove,
                  cols: cols,
                  tiny: tiny,
                ),
                CardPill(
                  compact ? '' : (hidden ? 'दिखाएँ' : 'छिपाएँ'),
                  icon: hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  onTap: () => onVisible(hidden),
                  cols: cols,
                  tiny: tiny,
                ),
                if (!hidden)
                  CardPill(
                    compact ? '' : 'हटाएँ',
                    icon: CupertinoIcons.delete,
                    tone: PillTone.danger,
                    onTap: onRemove,
                    cols: cols,
                    tiny: tiny,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag(this.text, this.color, {this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
