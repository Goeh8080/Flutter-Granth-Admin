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
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// फ़ोल्डर: religions / groups / sub-groups tree editor (saved to the shared draft with PUT /structure).
class PanelFoldersScreen extends StatefulWidget {
  const PanelFoldersScreen({super.key});
  @override
  State<PanelFoldersScreen> createState() => _PanelFoldersScreenState();
}

class _PanelFoldersScreenState extends State<PanelFoldersScreen> {
  Map<String, dynamic>? _tree;
  Map<String, dynamic>? _orig;
  Object? _src;
  bool _saving = false;

  bool get _dirty => _tree != null && _orig != null && !sameTree(_tree!, _orig!);

  void _sync(PanelStructure s) {
    if (!identical(_src, s)) {
      _src = s;
      _orig = s.structure;
      _tree = deepCopy(s.structure);
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
              message: 'हटाए जा रहे फ़ोल्डर में ग्रंथ रखे हैं${leaves.isEmpty ? '' : ' ($leaves)'}। आगे बढ़ने पर उन ग्रंथों की जगह अपने-आप (डिफ़ॉल्ट नियम से) तय होगी।',
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
    final ok = await confirmDialog(context, title: '"$name" हटाएँ?', message: 'इसके अंदर के समूह भी हट जाएँगे। सहेजने तक ड्राफ्ट में नहीं जाएगा।');
    if (ok) _change(() => removeChild(parent, key, i));
  }

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
        SheetAction('संपादित करें / Edit', CupertinoIcons.pencil, () => _edit(s, node, religion: religion)),
        if (canAddGroup) SheetAction('समूह जोड़ें / Add group', CupertinoIcons.plus_circle, () => _addChild(s, node, sub: false)),
        if (canAddSub) SheetAction('उप-समूह जोड़ें / Add sub-group', CupertinoIcons.plus_circle, () => _addChild(s, node, sub: true)),
        if (index > 0) SheetAction('ऊपर / Move up', CupertinoIcons.arrow_up, () => _change(() => moveChild(list, index, -1))),
        if (index < list.length - 1) SheetAction('नीचे / Move down', CupertinoIcons.arrow_down, () => _change(() => moveChild(list, index, 1))),
        SheetAction('हटाएँ / Remove', CupertinoIcons.delete, () => _remove(parent, key, index, name), destructive: true),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    PanelStructure s, {
    required Map<String, dynamic> node,
    required Map<String, dynamic> parent,
    required String key,
    required int index,
    required int level,
    required String path,
    required bool hasChildren,
  }) {
    final p = Palette.of(context);
    final religion = level == 0;
    final visible = node['visible'] != false;
    final soon = '${node['coming_soon'] ?? ''}'.trim();
    final n = s.counts[path];
    final title = '${node['title'] ?? ''}';
    return Padding(
      padding: EdgeInsets.only(left: level * 14.0, bottom: 6),
      child: PressableGlass(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        onTap: () => _menu(
          s,
          name: title,
          node: node,
          parent: parent,
          key: key,
          index: index,
          religion: religion,
          canAddGroup: religion,
          canAddSub: level == 1,
        ),
        child: Row(
          children: [
            Icon(
              religion ? CupertinoIcons.folder_fill : (level == 1 ? CupertinoIcons.folder : CupertinoIcons.doc_text),
              size: 20,
              color: visible ? AppColors.saffron : p.subtext,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Opacity(
                opacity: visible ? 1 : 0.55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: p.text, fontSize: religion ? 16 : 15, fontWeight: religion ? FontWeight.w700 : FontWeight.w500)),
                    Text(
                      [
                        node['id'],
                        if (node['icon'] != null) 'आइकन: ${node['icon']}',
                        if (!visible) 'छिपा',
                        if (soon.isNotEmpty) 'जल्द: $soon',
                        if (n != null) '$n ग्रंथ',
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.subtext, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
            Icon(CupertinoIcons.ellipsis, size: 18, color: p.subtext),
          ],
        ),
      ),
    );
  }

  List<Widget> _tree2(BuildContext context, PanelStructure s) {
    final tree = _tree!;
    final out = <Widget>[];
    final religions = childList(tree, 'religions');
    for (var i = 0; i < religions.length; i++) {
      final r = religions[i];
      out.add(_row(context, s, node: r, parent: tree, key: 'religions', index: i, level: 0, path: '${r['id']}', hasChildren: true));
      final groups = childList(r, 'groups');
      for (var j = 0; j < groups.length; j++) {
        final g = groups[j];
        final subs = listOf(g['subgroups']);
        out.add(_row(context, s, node: g, parent: r, key: 'groups', index: j, level: 1, path: '${r['id']}/${g['id']}', hasChildren: subs.isNotEmpty));
        final subList = subs.isEmpty ? <Map<String, dynamic>>[] : childList(g, 'subgroups');
        for (var k = 0; k < subList.length; k++) {
          final sg = subList[k];
          out.add(_row(context, s, node: sg, parent: g, key: 'subgroups', index: k, level: 2, path: '${r['id']}/${g['id']}/${sg['id']}', hasChildren: false));
        }
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => _addChild(s, r, sub: false),
              child: const Text('+ समूह जोड़ें', style: TextStyle(fontSize: 13.5)),
            ),
          ),
        ),
      );
    }
    final other = tree['other'];
    if (other is Map<String, dynamic>) {
      out.add(const SizedBox(height: 4));
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PressableGlass(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            onTap: () => _edit(s, other, religion: false, other: true),
            child: Row(
              children: [
                const Icon(CupertinoIcons.tray_full_fill, size: 20, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${other['title'] ?? 'अन्य'}  (हमेशा रहता है)', style: TextStyle(color: Palette.of(context).text, fontSize: 15)),
                ),
                const Icon(CupertinoIcons.pencil, size: 18),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return PanelPage<PanelStructure>(
      title: 'फ़ोल्डर / Folders',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.structure(),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _tree == null ? null : () => _addReligion(_src as PanelStructure),
        child: const Icon(CupertinoIcons.add),
      ),
      floatingBuilder: (context, d) => !_dirty
          ? null
          : Positioned(
              left: 14,
              right: 14,
              bottom: 10 + MediaQuery.of(context).padding.bottom,
              child: Glass(
                blur: 20,
                strong: true,
                radius: 22,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('फ़ोल्डर में बदलाव सहेजे नहीं गए', style: TextStyle(color: Palette.of(context).text, fontWeight: FontWeight.w600, fontSize: 14))),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: _saving ? null : () => setState(() => _tree = deepCopy(_orig!)),
                      child: const Text('हटाएँ', style: TextStyle(color: AppColors.red)),
                    ),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      borderRadius: BorderRadius.circular(18),
                      onPressed: _saving || d == null ? null : () => _save(d),
                      child: _saving ? const CupertinoActivityIndicator(color: Colors.white) : const Text('सहेजें'),
                    ),
                  ],
                ),
              ),
            ),
      builder: (context, s, reload) {
        _sync(s);
        return [
          PadSliver(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            child: SliverList(
              delegate: SliverChildListDelegate([
                const DraftBanner(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'किसी भी पंक्ति को दबाकर नाम/आइकन बदलें, क्रम बदलें या हटाएँ। आईडी बाद में नहीं बदलती।',
                    style: TextStyle(color: Palette.of(context).subtext, fontSize: 12.5),
                  ),
                ),
                ..._tree2(context, s),
                const SizedBox(height: 6),
                PrimaryButton(label: 'नया धर्म जोड़ें', icon: CupertinoIcons.add, onPressed: () => _addReligion(s)),
              ]),
            ),
          ),
        ];
      },
    );
  }
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
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.subtext)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final i in items) FilterChipX(i, selected: i == value, onTap: () => on(i))]),
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
          GlassField(label: 'आईडी / ID (a-z, 0-9, _ -)', controller: _id, placeholder: 'जैसे: upanishad', prefix: CupertinoIcons.number),
        GlassField(label: 'नाम / Title', controller: _name, required: true, placeholder: 'जैसे: उपनिषद'),
        if (widget.icons.isNotEmpty) _chips('आइकन / Icon', widget.icons, _icon, (v) => setState(() => _icon = v)),
        if (widget.isReligion && widget.tones.isNotEmpty) _chips('रंग / Tone', widget.tones, _tone, (v) => setState(() => _tone = v)),
        if (!widget.lockVisible) ActiveSwitch(value: _visible, onChanged: (v) => setState(() => _visible = v)),
        GlassField(label: '"जल्द आ रहा है" संदेश (वैकल्पिक)', controller: _soon, maxLines: 2, placeholder: 'जैसे: जल्द आ रहा है'),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_err!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ),
      ],
    );
  }
}
