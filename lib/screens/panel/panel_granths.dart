import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/panel_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
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
};

enum GranthFilter { all, isNew, other, hidden, noPraman }

/// Pure filter used by the screen (and unit-tested).
List<PanelGranth> filterGranths(
  List<PanelGranth> all, {
  GranthFilter filter = GranthFilter.all,
  String query = '',
  String? leaf,
  Map<String, PendingGranth> pending = const {},
}) {
  final q = query.trim().toLowerCase();
  bool hiddenOf(PanelGranth g) => pending[g.id]?.hidden ?? g.hidden;
  String leafOf(PanelGranth g) => pending[g.id]?.leaf ?? g.leaf;
  return all.where((g) {
    switch (filter) {
      case GranthFilter.all:
        break;
      case GranthFilter.isNew:
        if (!g.isNew) return false;
      case GranthFilter.other:
        if (leafOf(g) != 'other') return false;
      case GranthFilter.hidden:
        if (!hiddenOf(g)) return false;
      case GranthFilter.noPraman:
        if (!g.noPraman) return false;
    }
    if (leaf != null && leafOf(g) != leaf) return false;
    if (q.isNotEmpty && !(g.title.toLowerCase().contains(q) || g.author.toLowerCase().contains(q) || g.id == q)) return false;
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
  GranthFilter filter = GranthFilter.all;
  String sort = 'number';
  String query = '';
  String? leafFilter;
  PanelGranthList? _data;
  bool _saving = false;

  void _edit(Iterable<String> ids, {String? leaf, bool? hidden}) {
    setState(() {
      for (final id in ids) {
        final e = pending.putIfAbsent(id, PendingGranth.new);
        if (leaf != null) e.leaf = leaf;
        if (hidden != null) e.hidden = hidden;
      }
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
        showToast('90% से ज़्यादा ग्रंथ छिपाना मना है / Cannot hide more than 90%', error: true);
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
            final chunk = entry.value.sublist(i, i + 300 > entry.value.length ? entry.value.length : i + 300);
            await panel.api.bulkGranths(chunk, leaf: sample.leaf, hidden: sample.hidden);
          }
        }
        pending.clear();
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
    final k = await pickLeaf(context, d.leaves, title: '${selected.length} ग्रंथ कहाँ ले जाएँ?');
    if (k == null) return;
    _edit(selected.toList(), leaf: k);
    setState(selected.clear);
  }

  void _pickSort() => showActions(
    context,
    title: 'क्रम / Sort',
    actions: [for (final e in kGranthSorts.entries) SheetAction(e.value, e.key == sort ? CupertinoIcons.checkmark : CupertinoIcons.sort_down, () => setState(() => sort = e.key))],
  );

  Future<void> _pickFilterLeaf(PanelGranthList d) async {
    final k = await pickLeaf(context, d.leaves, current: leafFilter, title: 'फ़ोल्डर से छानें');
    if (k != null) setState(() => leafFilter = k);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<PanelGranthList>(
      key: ValueKey('granths$sort'),
      title: 'ग्रंथ / Granths',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.granths(sort: sort),
      trailing: selected.isEmpty
          ? null
          : CupertinoButton(padding: EdgeInsets.zero, onPressed: () => setState(selected.clear), child: const Text('चयन हटाएँ')),
      floatingBuilder: (context, d) => Positioned(
        left: 14,
        right: 14,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
        child: _bottomBar(context, d),
      ),
      builder: (context, d, reload) {
        _data = d;
        final leafLabels = leafLabelMap(d.leaves);
        final list = filterGranths(d.items, filter: filter, query: query, leaf: leafFilter, pending: pending);
        int count(GranthFilter f) => filterGranths(d.items, filter: f, pending: pending).length;
        final hiddenNow = hiddenAfter(d.items, pending);
        return [
          PadSliver(
            child: SliverList(
              delegate: SliverChildListDelegate([
                const DraftBanner(),
                CupertinoSearchTextField(
                  placeholder: 'ग्रंथ या लेखक खोजें',
                  style: TextStyle(color: p.text, fontFamily: kFont),
                  backgroundColor: p.fieldFill,
                  onChanged: (v) => setState(() => query = v),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChipX('सब', selected: filter == GranthFilter.all, count: d.items.length, onTap: () => setState(() => filter = GranthFilter.all)),
                      const SizedBox(width: 8),
                      FilterChipX('नया', selected: filter == GranthFilter.isNew, count: count(GranthFilter.isNew), onTap: () => setState(() => filter = GranthFilter.isNew)),
                      const SizedBox(width: 8),
                      FilterChipX('अन्य', selected: filter == GranthFilter.other, count: count(GranthFilter.other), onTap: () => setState(() => filter = GranthFilter.other)),
                      const SizedBox(width: 8),
                      FilterChipX('छिपा', selected: filter == GranthFilter.hidden, count: count(GranthFilter.hidden), onTap: () => setState(() => filter = GranthFilter.hidden)),
                      const SizedBox(width: 8),
                      FilterChipX('बिना प्रमाण', selected: filter == GranthFilter.noPraman, count: count(GranthFilter.noPraman), onTap: () => setState(() => filter = GranthFilter.noPraman)),
                      const SizedBox(width: 8),
                      FilterChipX('क्रम: ${kGranthSorts[sort] ?? sort} ▾', selected: false, onTap: _pickSort),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: PressableGlass(
                        radius: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        onTap: () => _pickFilterLeaf(d),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.folder, size: 18, color: AppColors.saffron),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                leafFilter == null ? 'सभी फ़ोल्डर' : (leafLabels[leafFilter] ?? leafFilter!),
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
                        child: const Icon(CupertinoIcons.clear_circled_solid, color: AppColors.red),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${list.length} ग्रंथ • छिपे: $hiddenNow / ${d.items.length}${selected.isEmpty ? '  (लंबा दबाकर कई चुनें)' : ''}',
                  style: TextStyle(color: p.subtext, fontSize: 12.5),
                ),
                if (d.items.isNotEmpty && hiddenNow * 2 > d.items.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '⚠ 50% से ज़्यादा ग्रंथ छिपे हैं — प्रकाशित करते समय "फ़ोर्स" चाहिए होगा।',
                      style: const TextStyle(color: AppColors.red, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 10),
              ]),
            ),
          ),
          if (list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(icon: CupertinoIcons.book, title: 'कोई ग्रंथ नहीं मिला', subtitle: 'फ़िल्टर या खोज बदलकर देखें'),
            )
          else
            PadSliver(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              child: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final g = list[i];
                  final e = pending[g.id];
                  return _GranthRow(
                    g: g,
                    leafLabel: e?.leaf != null ? (leafLabels[e!.leaf!] ?? e.leaf!) : g.leafLabel,
                    hidden: e?.hidden ?? g.hidden,
                    changed: e != null,
                    selected: selected.contains(g.id),
                    selecting: selected.isNotEmpty,
                    onToggleSelect: () => setState(() => selected.contains(g.id) ? selected.remove(g.id) : selected.add(g.id)),
                    onMove: () async {
                      final k = await pickLeaf(context, d.leaves, current: e?.leaf ?? g.leaf, title: g.title);
                      if (k != null) _edit([g.id], leaf: k);
                    },
                    onVisible: (v) => _edit([g.id], hidden: !v),
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
        blur: 20,
        strong: true,
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text('${selected.length} चुने', style: TextStyle(color: p.text, fontWeight: FontWeight.w700))),
            CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 8), onPressed: () => _moveSelected(d), child: const Text('फ़ोल्डर')),
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
      blur: 20,
      strong: true,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              n > 0 ? '$n ग्रंथ में बदलाव सहेजे नहीं गए' : 'ड्राफ्ट में बदलाव बाकी हैं',
              style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          if (n > 0)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: _saving ? null : () => setState(pending.clear),
              child: const Text('हटाएँ', style: TextStyle(color: AppColors.red)),
            ),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(18),
            onPressed: _saving ? null : _preview,
            child: _saving ? const CupertinoActivityIndicator(color: Colors.white) : const Text('प्रीव्यू / Preview'),
          ),
        ],
      ),
    );
  }
}

class _GranthRow extends StatelessWidget {
  const _GranthRow({
    required this.g,
    required this.leafLabel,
    required this.hidden,
    required this.changed,
    required this.selected,
    required this.selecting,
    required this.onToggleSelect,
    required this.onMove,
    required this.onVisible,
  });
  final PanelGranth g;
  final String leafLabel;
  final bool hidden, changed, selected, selecting;
  final VoidCallback onToggleSelect, onMove;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableGlass(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        onTap: selecting ? onToggleSelect : onMove,
        onLongPress: onToggleSelect,
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: selected ? AppColors.saffron : p.subtext),
              ),
            Expanded(
              child: Opacity(
                opacity: hidden ? 0.55 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.position == null ? (g.title.isEmpty ? g.id : g.title) : '#${g.position}  ${g.title.isEmpty ? g.id : g.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
                    if (g.author.isNotEmpty) Text(g.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.subtext, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Tag(leafLabel.isEmpty ? g.leaf : leafLabel, icon: CupertinoIcons.folder_fill, color: AppColors.blue),
                        if (g.isNew) const Tag('नया', color: AppColors.green),
                        if (g.noPraman) const Tag('बिना प्रमाण', color: AppColors.gold),
                        if (changed) const Tag('बदला', color: AppColors.saffron),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            CupertinoSwitch(value: !hidden, activeTrackColor: AppColors.green, onChanged: onVisible),
          ],
        ),
      ),
    );
  }
}
