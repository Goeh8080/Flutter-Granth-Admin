import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/panel_models.dart';
import '../../models/structure_edit.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/grid_kit.dart';
import '../../widgets/icons/folder_tokens.dart';
import '../../widgets/icons/group_icon.dart';
import '../../widgets/icons/religion_symbol.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// Structure + the granth list (for the "N ग्रंथ • M प्रमाण" counts). [granths] is null when it could not be loaded.
class FoldersData {
  const FoldersData(this.structure, this.granths);
  final PanelStructure structure;
  final List<PanelGranth>? granths;
}

/// "N ग्रंथ • M प्रमाण" (just "N ग्रंथ" when M is 0).
String folderSub(int n, int m, {String sep = ' • '}) => m > 0 ? '$n ग्रंथ$sep$m प्रमाण' : '$n ग्रंथ';

/// Granth and praman totals of the leaf keys [keys] (hidden granths are not counted, like in the reader app).
({int granths, int pramans}) folderTotals(Iterable<String> keys, List<PanelGranth>? granths, Map<String, int> counts) {
  final set = keys.toSet();
  if (granths == null) {
    var n = 0;
    for (final k in set) {
      n += counts[k] ?? 0;
    }
    return (granths: n, pramans: 0);
  }
  var n = 0, m = 0;
  for (final g in granths) {
    if (g.hidden || !set.contains(g.leaf)) continue;
    n++;
    m += g.pramanCount;
  }
  return (granths: n, pramans: m);
}

/// फ़ोल्डर: shelf-style icon-card grid of religions / groups / sub-groups (saved to the shared draft with PUT /structure).
class PanelFoldersScreen extends StatefulWidget {
  const PanelFoldersScreen({super.key});
  @override
  State<PanelFoldersScreen> createState() => _PanelFoldersScreenState();
}

class _PanelFoldersScreenState extends State<PanelFoldersScreen> {
  Map<String, dynamic>? _tree;
  Map<String, dynamic>? _orig;
  Object? _src;
  PanelStructure? _s;
  List<PanelGranth>? _granths;
  bool _saving = false;
  int _cols = 3;

  /// Ids walked into so far: [] = religions, [r] = groups of r, [r, g] = sub-groups of g.
  final List<String> _path = [];

  bool get _dirty => _tree != null && _orig != null && !sameTree(_tree!, _orig!);

  @override
  void initState() {
    super.initState();
    readGridCols(kGridPrefFolders, 3).then((v) {
      if (mounted && v != _cols) setState(() => _cols = v);
    });
  }

  void _setCols(int v) {
    setState(() => _cols = v);
    saveGridCols(kGridPrefFolders, v);
  }

  void _sync(FoldersData d) {
    if (!identical(_src, d)) {
      _src = d;
      _s = d.structure;
      _granths = d.granths;
      _orig = d.structure.structure;
      _tree = deepCopy(d.structure.structure);
    }
  }

  void _change(VoidCallback f) => setState(f);

  Future<void> _save(PanelStructure s) async {
    final panel = panelOf(context);
    setState(() => _saving = true);
    var drop = false;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await panel.api.putStructure(_tree!, dropOverrides: drop);
          break;
        } on PanelApiException catch (e) {
          if (e.code == 'leaf_in_use' && !drop) {
            final leaves = (e.extra['leaves'] is List) ? (e.extra['leaves'] as List).take(6).join(', ') : '';
            if (!mounted) return;
            final ok = await confirmDialog(
              context,
              title: 'फ़ोल्डर में ग्रंथ लगे हैं',
              message:
                  'हटाए जा रहे फ़ोल्डर में ग्रंथ रखे हैं${leaves.isEmpty ? '' : ' ($leaves)'}। आगे बढ़ने पर उन ग्रंथों की जगह अपने-आप (डिफ़ॉल्ट नियम से) तय होगी।',
              confirm: 'आगे बढ़ें / Continue',
              destructive: false,
            );
            if (!ok) {
              if (mounted) setState(() => _saving = false);
              return;
            }
            drop = true;
            continue;
          }
          rethrow;
        }
      }
      panel.bump();
      if (!mounted) return;
      setState(() => _saving = false);
      showToast('फ़ोल्डर ड्राफ्ट में सहेजे / Saved to draft');
      await showPublishSheet(context);
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addReligion(PanelStructure s) async {
    final tree = _tree!;
    final r = await showGlassSheet<Map<String, dynamic>>(
      context,
      (_) => _NodeForm(
        title: 'नया धर्म / New religion',
        icons: s.icons.religion,
        tones: s.icons.tones,
        isReligion: true,
        siblingIds: [for (final x in listOf(tree['religions'])) '${x['id']}'],
      ),
    );
    if (r == null) return;
    _change(() => childList(tree, 'religions').add(r));
  }

  Future<void> _addChild(PanelStructure s, Map<String, dynamic> parent, {required bool sub}) async {
    final key = sub ? 'subgroups' : 'groups';
    final r = await showGlassSheet<Map<String, dynamic>>(
      context,
      (_) => _NodeForm(
        title: sub ? 'नया उप-समूह / New sub-group' : 'नया समूह / New group',
        icons: s.icons.group,
        tones: const [],
        isReligion: false,
        siblingIds: [for (final x in listOf(parent[key])) '${x['id']}'],
      ),
    );
    if (r == null) return;
    _change(() {
      if (sub) {
        addSubgroup(parent, r);
      } else {
        childList(parent, 'groups').add(r);
      }
    });
  }

  Future<void> _edit(PanelStructure s, Map<String, dynamic> node, {required bool religion, bool other = false}) async {
    final r = await showGlassSheet<Map<String, dynamic>>(
      context,
      (_) => _NodeForm(
        title: 'संपादित करें / Edit',
        icons: religion || other ? s.icons.religion : s.icons.group,
        tones: religion || other ? s.icons.tones : const [],
        isReligion: religion || other,
        initial: node,
        lockVisible: other,
        siblingIds: const [],
      ),
    );
    if (r == null) return;
    _change(() {
      for (final e in r.entries) {
        if (e.value == null) {
          node.remove(e.key);
        } else {
          node[e.key] = e.value;
        }
      }
    });
  }

  Future<void> _remove(Map<String, dynamic> parent, String key, int i, String name) async {
    final ok = await confirmDialog(
      context,
      title: '"$name" हटाएँ?',
      message: 'इसके अंदर के समूह भी हट जाएँगे। सहेजने तक ड्राफ्ट में नहीं जाएगा।',
    );
    if (ok) _change(() => removeChild(parent, key, i));
  }

  // ------------------------------------------------------------------ navigation / lookup

  /// The nodes walked into by [_path] (religion, group); stops at the first id that no longer exists.
  List<Map<String, dynamic>> _chain() {
    final out = <Map<String, dynamic>>[];
    final tree = _tree;
    if (tree == null) return out;
    var list = childList(tree, 'religions');
    var key = 'groups';
    for (final id in _path) {
      final n = list.where((e) => '${e['id']}' == id).firstOrNull;
      if (n == null) break;
      out.add(n);
      list = listOf(n[key]).isEmpty ? <Map<String, dynamic>>[] : childList(n, key);
      key = 'subgroups';
    }
    return out;
  }

  void _open(String id) => setState(() => _path.add(id));
  void _up() => setState(() {
    if (_path.isNotEmpty) _path.removeLast();
  });

  void _menu(
    PanelStructure s, {
    required String name,
    required Map<String, dynamic> node,
    required Map<String, dynamic> parent,
    required String key,
    required int index,
    required bool religion,
    bool canAddGroup = false,
    bool canAddSub = false,
  }) {
    final list = childList(parent, key);
    showActions(
      context,
      title: name,
      actions: [
        SheetAction('नाम / आइकन / रंग बदलें / Edit', CupertinoIcons.pencil, () => _edit(s, node, religion: religion)),
        SheetAction(
          node['visible'] == false ? 'दिखाएँ / Show' : 'छिपाएँ / Hide',
          node['visible'] == false ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          () => _change(() => node['visible'] = node['visible'] == false),
        ),
        if (canAddGroup)
          SheetAction('समूह जोड़ें / Add group', CupertinoIcons.plus_circle, () => _addChild(s, node, sub: false)),
        if (canAddSub)
          SheetAction(
            'उप-समूह जोड़ें / Add sub-group',
            CupertinoIcons.plus_circle,
            () => _addChild(s, node, sub: true),
          ),
        if (index > 0)
          SheetAction(
            'पहले ले जाएँ / Move earlier',
            CupertinoIcons.arrow_left,
            () => _change(() => moveChild(list, index, -1)),
          ),
        if (index < list.length - 1)
          SheetAction(
            'बाद में ले जाएँ / Move later',
            CupertinoIcons.arrow_right,
            () => _change(() => moveChild(list, index, 1)),
          ),
        SheetAction(
          'हटाएँ / Remove',
          CupertinoIcons.delete,
          () => _remove(parent, key, index, name),
          destructive: true,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ cards

  Widget _card(
    BuildContext context,
    PanelStructure s, {
    required Map<String, dynamic> node,
    required Map<String, dynamic> parent,
    required String key,
    required int index,
    required int level,
    required List<String> leafKeys,
    required bool hasChildren,
    required int cols,
  }) {
    final religion = level == 0;
    final id = '${node['id']}';
    final visible = node['visible'] != false;
    final soon = '${node['coming_soon'] ?? ''}'.trim();
    final title = '${node['title'] ?? ''}';
    final t = folderTotals(leafKeys, _granths, s.counts);
    final icon = '${node['icon'] ?? 'misc'}';
    final tone = toneOf(node['tone']);
    void menu() => _menu(
      s,
      name: title,
      node: node,
      parent: parent,
      key: key,
      index: index,
      religion: religion,
      canAddGroup: religion,
      canAddSub: level == 1,
    );
    return _FolderTile(
      key: ValueKey('folder-$level-$id'),
      cols: cols,
      title: title,
      icon: religion
          ? ReligionSymbol(icon, tone: tone, size: _symbolSize(cols))
          : GroupIcon(icon, size: _symbolSize(cols)),
      n: t.granths,
      m: t.pramans,
      hidden: !visible,
      soon: soon.isNotEmpty,
      chevron: hasChildren,
      onTap: hasChildren ? () => _open(id) : menu,
      onMenu: menu,
    );
  }

  double _symbolSize(int cols) => switch (cols) {
    1 => 44,
    2 => 72,
    _ => 46,
  };

  Widget _addCard(String label, VoidCallback onTap, int cols) => PaperCard(
    onTap: onTap,
    padding: EdgeInsets.symmetric(horizontal: cols == 3 ? 6 : 10, vertical: cols == 3 ? 10 : 14),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: _symbolSize(cols) * (cols == 1 ? 1 : 0.8),
          height: _symbolSize(cols) * (cols == 1 ? 1 : 0.8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GColors.gold, width: 1.4),
          ),
          child: const Icon(CupertinoIcons.add, color: GColors.saffronDark),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: kFont,
            color: GColors.saffronDark,
            fontWeight: FontWeight.w700,
            fontSize: cols == 3 ? 12 : 13.5,
          ),
        ),
      ],
    ),
  );

  Widget _crumbs(BuildContext context, List<Map<String, dynamic>> chain) {
    final p = Palette.of(context);
    Widget seg(String label, VoidCallback? on, {bool last = false}) => GestureDetector(
      onTap: on,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: last ? FontWeight.w700 : FontWeight.w500,
          color: last ? p.text : AppColors.saffron,
        ),
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        seg('सभी धर्म', chain.isEmpty ? null : () => setState(_path.clear), last: chain.isEmpty),
        for (var i = 0; i < chain.length; i++) ...[
          Icon(CupertinoIcons.chevron_right, size: 11, color: p.subtext),
          seg(
            '${chain[i]['title'] ?? chain[i]['id']}',
            i == chain.length - 1 ? null : () => setState(() => _path.removeRange(i + 1, _path.length)),
            last: i == chain.length - 1,
          ),
        ],
      ],
    );
  }

  List<Widget> _content(BuildContext context, FoldersData d) {
    final s = d.structure;
    final tree = _tree!;
    final chain = _chain();
    if (chain.length < _path.length) {
      // a node on the way vanished (removed): step back out
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _path.removeRange(chain.length, _path.length));
      });
    }
    final p = Palette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = folderColumns(_cols, width);
    final tiles = <Widget>[];
    String? heading;
    Iterable<String> headKeys = const [];

    if (chain.isEmpty) {
      final religions = childList(tree, 'religions');
      for (var i = 0; i < religions.length; i++) {
        final r = religions[i];
        tiles.add(
          _card(
            context,
            s,
            node: r,
            parent: tree,
            key: 'religions',
            index: i,
            level: 0,
            leafKeys: religionLeafKeys(r),
            hasChildren: true,
            cols: _cols,
          ),
        );
      }
      final other = tree['other'];
      if (other is Map<String, dynamic>) {
        final t = folderTotals(const ['other'], _granths, s.counts);
        tiles.add(
          _FolderTile(
            key: const ValueKey('folder-other'),
            cols: _cols,
            title: '${other['title'] ?? 'अन्य'}',
            icon: ReligionSymbol(
              '${other['icon'] ?? 'misc'}',
              tone: toneOf(other['tone'] ?? 'gold'),
              size: _symbolSize(_cols),
            ),
            n: t.granths,
            m: t.pramans,
            hidden: false,
            soon: false,
            chevron: false,
            onTap: () => _edit(s, other, religion: false, other: true),
            onMenu: () => _edit(s, other, religion: false, other: true),
          ),
        );
      }
      tiles.add(_addCard('नया धर्म', () => _addReligion(s), _cols));
      headKeys = [for (final r in religions) ...religionLeafKeys(r), 'other'];
    } else if (chain.length == 1) {
      final r = chain[0];
      final groups = childList(r, 'groups');
      for (var j = 0; j < groups.length; j++) {
        final g = groups[j];
        final subs = listOf(g['subgroups']);
        tiles.add(
          _card(
            context,
            s,
            node: g,
            parent: r,
            key: 'groups',
            index: j,
            level: 1,
            leafKeys: leafKeysUnder(g, '${r['id']}/${g['id']}'),
            hasChildren: subs.isNotEmpty,
            cols: _cols,
          ),
        );
      }
      tiles.add(_addCard('नया समूह', () => _addChild(s, r, sub: false), _cols));
      heading = '${r['title']}';
      headKeys = religionLeafKeys(r);
    } else {
      final r = chain[0], g = chain[1];
      final subs = listOf(g['subgroups']).isEmpty ? <Map<String, dynamic>>[] : childList(g, 'subgroups');
      for (var k = 0; k < subs.length; k++) {
        final sg = subs[k];
        tiles.add(
          _card(
            context,
            s,
            node: sg,
            parent: g,
            key: 'subgroups',
            index: k,
            level: 2,
            leafKeys: ['${r['id']}/${g['id']}/${sg['id']}'],
            hasChildren: false,
            cols: _cols,
          ),
        );
      }
      tiles.add(_addCard('नया उप-समूह', () => _addChild(s, g, sub: true), _cols));
      heading = '${g['title']}';
      headKeys = leafKeysUnder(g, '${r['id']}/${g['id']}');
    }
    final tot = folderTotals(headKeys, _granths, s.counts);

    return [
      PadSliver(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: SliverList(
          delegate: SliverChildListDelegate([
            const DraftBanner(),
            Row(
              children: [
                if (chain.isNotEmpty)
                  CupertinoButton(
                    key: const ValueKey('folder-up'),
                    padding: const EdgeInsets.only(right: 10),
                    minimumSize: Size.zero,
                    onPressed: _up,
                    child: const Icon(CupertinoIcons.arrow_up_left, size: 20),
                  ),
                Expanded(child: _crumbs(context, chain)),
                GridSwitch(cols: _cols, onChanged: _setCols),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${heading ?? 'कुल'}: ${folderSub(tot.granths, tot.pramans)}',
              style: TextStyle(color: p.subtext, fontSize: 12.5),
            ),
            const SizedBox(height: 2),
            Text(
              'कार्ड दबाकर खोलें; ⋯ से नाम/आइकन/रंग बदलें, दिखाएँ/छिपाएँ, क्रम बदलें या हटाएँ। आईडी बाद में नहीं बदलती।',
              style: TextStyle(color: p.subtext, fontSize: 12),
            ),
          ]),
        ),
      ),
      PadSliver(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        child: GridRowsSliver(cols: cols, count: tiles.length, gap: gridGap(_cols), itemBuilder: (_, i) => tiles[i]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _path.isNotEmpty) _up();
      },
      child: PanelPage<FoldersData>(
        title: 'फ़ोल्डर / Folders',
        previousPageTitle: 'कंट्रोल',
        load: (api) async {
          final s = await api.structure();
          List<PanelGranth>? g;
          try {
            g = (await api.granths()).items;
          } on PanelApiException {
            g = null; // counts fall back to the server's per-folder totals
          }
          return FoldersData(s, g);
        },
        floatingBuilder: (context, d) => !_dirty
            ? null
            : Positioned(
                left: 14,
                right: 14,
                bottom: 10 + MediaQuery.paddingOf(context).bottom,
                child: Glass(
                  blur: 0,
                  tint: Palette.of(context).dark ? const Color(0xF2262230) : const Color(0xF5FFFFFF),
                  strong: true,
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'फ़ोल्डर में बदलाव सहेजे नहीं गए',
                          style: TextStyle(color: Palette.of(context).text, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: _saving ? null : () => setState(() => _tree = deepCopy(_orig!)),
                        child: const Text('हटाएँ', style: TextStyle(color: AppColors.red)),
                      ),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(18),
                        onPressed: _saving || _s == null ? null : () => _save(_s!),
                        child: _saving ? const CupertinoActivityIndicator(color: Colors.white) : const Text('सहेजें'),
                      ),
                    ],
                  ),
                ),
              ),
        builder: (context, d, reload) {
          _sync(d);
          return _content(context, d);
        },
      ),
    );
  }
}

/// One shelf tile: symbol, title and "N ग्रंथ • M प्रमाण" (tokens §5; 3×3 wraps the sub-line).
class _FolderTile extends StatelessWidget {
  const _FolderTile({
    super.key,
    required this.cols,
    required this.title,
    required this.icon,
    required this.n,
    required this.m,
    required this.hidden,
    required this.soon,
    required this.chevron,
    required this.onTap,
    required this.onMenu,
  });
  final int cols, n, m;
  final String title;
  final Widget icon;
  final bool hidden, soon, chevron;
  final VoidCallback onTap, onMenu;

  @override
  Widget build(BuildContext context) {
    final small = cols == 3;
    final titleStyle = TextStyle(
      fontFamily: kSerif,
      color: GColors.maroon,
      fontSize: cols == 1 ? 19 : (small ? 14.5 : 18),
      height: 1.25,
    );
    final subStyle = TextStyle(
      fontFamily: kFont,
      color: GColors.muted,
      fontWeight: FontWeight.w600,
      fontSize: cols == 1 ? 13 : (small ? 11 : 12.5),
    );
    final badges = Wrap(
      spacing: 4,
      runSpacing: 2,
      alignment: cols == 1 ? WrapAlignment.start : WrapAlignment.center,
      children: [
        if (hidden) const _Mini('छिपा', Color(0xFF8B6A4A)),
        if (soon) const _Mini('जल्द', GColors.saffronDark),
      ],
    );
    final menu = GestureDetector(
      key: const ValueKey('folder-menu'),
      behavior: HitTestBehavior.opaque,
      onTap: onMenu,
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(CupertinoIcons.ellipsis, size: 18, color: GColors.muted),
      ),
    );
    final Widget body;
    if (cols == 1) {
      body = Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
                const SizedBox(height: 2),
                Text(folderSub(n, m), style: subStyle),
                if (hidden || soon) Padding(padding: const EdgeInsets.only(top: 3), child: badges),
              ],
            ),
          ),
          menu,
          if (chevron) const Icon(CupertinoIcons.chevron_right, size: 20, color: GColors.muted),
        ],
      );
    } else {
      body = Stack(
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                icon,
                SizedBox(height: small ? 6 : 8),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 3),
                if (small) ...[
                  Text('$n ग्रंथ', textAlign: TextAlign.center, style: subStyle),
                  if (m > 0) Text('$m प्रमाण', textAlign: TextAlign.center, style: subStyle),
                ] else
                  Text(folderSub(n, m), textAlign: TextAlign.center, style: subStyle),
                if (hidden || soon) Padding(padding: const EdgeInsets.only(top: 3), child: badges),
              ],
            ),
          ),
          Positioned(top: -6, right: -6, child: menu),
        ],
      );
    }
    return PaperCard(
      onTap: onTap,
      dim: hidden,
      padding: cols == 1
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
          : (small
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 10)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
      child: body,
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

/// Add / edit form for one folder node. Pops with the fields to set (null value = remove the key).
class _NodeForm extends StatefulWidget {
  const _NodeForm({
    required this.title,
    required this.icons,
    required this.tones,
    required this.isReligion,
    required this.siblingIds,
    this.initial,
    this.lockVisible = false,
  });
  final String title;
  final List<String> icons, tones, siblingIds;
  final bool isReligion, lockVisible;
  final Map<String, dynamic>? initial;
  @override
  State<_NodeForm> createState() => _NodeFormState();
}

class _NodeFormState extends State<_NodeForm> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _soon = TextEditingController();
  String? _icon, _tone;
  bool _visible = true;
  String? _err;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    if (n != null) {
      _name.text = '${n['title'] ?? ''}';
      _soon.text = '${n['coming_soon'] ?? ''}';
      _icon = n['icon'] as String?;
      _tone = n['tone'] as String?;
      _visible = n['visible'] != false;
    } else {
      _icon = widget.icons.contains('misc') ? 'misc' : null;
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _soon.dispose();
    super.dispose();
  }

  void _save() {
    final te = titleError(_name.text);
    if (te != null) return setState(() => _err = te);
    if (_soon.text.trim().length > 200) return setState(() => _err = 'संदेश 200 अक्षर तक / max 200 chars');
    if (_isNew) {
      final ie = idError(_id.text.trim(), widget.siblingIds, religion: widget.isReligion);
      if (ie != null) return setState(() => _err = ie);
      final node = newNode(_id.text.trim(), _name.text, icon: _icon, tone: _tone, religion: widget.isReligion);
      if (_soon.text.trim().isNotEmpty) node['coming_soon'] = _soon.text.trim();
      node['visible'] = _visible;
      Navigator.pop(context, node);
    } else {
      Navigator.pop(context, <String, dynamic>{
        'title': _name.text.trim(),
        'icon': _icon,
        if (widget.isReligion) 'tone': _tone,
        if (!widget.lockVisible) 'visible': _visible,
        'coming_soon': _soon.text.trim().isEmpty ? null : _soon.text.trim(),
      });
    }
  }

  Widget _chips(String label, List<String> items, String? value, ValueChanged<String> on) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final i in items) FilterChipX(i, selected: i == value, onTap: () => on(i))],
          ),
        ],
      ),
    );
  }

  /// Icon keys drawn with the same painters as the reader app (tap one to choose).
  Widget _iconPicker() {
    final p = Palette.of(context);
    final tone = toneOf(_tone ?? (widget.isReligion ? 'saffron' : null));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'आइकन / Icon',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in widget.icons)
                GestureDetector(
                  key: ValueKey('icon-$k'),
                  onTap: () => setState(() => _icon = k),
                  child: Container(
                    width: 64,
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                    decoration: BoxDecoration(
                      color: k == _icon ? AppColors.saffron.withValues(alpha: 0.16) : p.fieldFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: k == _icon ? AppColors.saffron : p.glassBorder,
                        width: k == _icon ? 1.5 : 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        widget.isReligion ? ReligionSymbol(k, tone: tone, size: 40) : GroupIcon(k, size: 40),
                        const SizedBox(height: 3),
                        Text(
                          k,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5, color: p.subtext),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: widget.title,
      onSave: _save,
      children: [
        if (_isNew)
          GlassField(
            label: 'आईडी / ID (a-z, 0-9, _ -)',
            controller: _id,
            placeholder: 'जैसे: upanishad',
            prefix: CupertinoIcons.number,
          ),
        GlassField(label: 'नाम / Title', controller: _name, required: true, placeholder: 'जैसे: उपनिषद'),
        if (widget.icons.isNotEmpty) _iconPicker(),
        if (widget.isReligion && widget.tones.isNotEmpty)
          _chips('रंग / Tone', widget.tones, _tone, (v) => setState(() => _tone = v)),
        if (!widget.lockVisible) ActiveSwitch(value: _visible, onChanged: (v) => setState(() => _visible = v)),
        GlassField(
          label: '"जल्द आ रहा है" संदेश (वैकल्पिक)',
          controller: _soon,
          maxLines: 2,
          placeholder: 'जैसे: जल्द आ रहा है',
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_err!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ),
      ],
    );
  }
}
