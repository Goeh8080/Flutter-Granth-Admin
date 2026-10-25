import 'package:flutter/cupertino.dart';

import '../../models/panel_models.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// विशेष जानकार: editor of the contact list shown in the reader app (`/admin/api/contacts`, contract 3.6).
/// Edits are local until "सहेजें" (PUT /contacts -> shared draft), then the publish sheet opens.
class PanelContactsScreen extends StatefulWidget {
  const PanelContactsScreen({super.key});
  @override
  State<PanelContactsScreen> createState() => _PanelContactsScreenState();
}

class _PanelContactsScreenState extends State<PanelContactsScreen> {
  PanelContacts? _src;
  late TextEditingController _title;
  List<PanelContact> _items = [];
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: kContactsTitle)
      ..addListener(() {
        if (!_seeding && !_dirty && _src != null && _title.text != _src!.title) setState(() => _dirty = true);
      });
  }

  bool _seeding = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _seed(PanelContacts d) {
    if (identical(_src, d)) return;
    _src = d;
    _seeding = true;
    _title.text = d.title;
    _seeding = false;
    _items = List.of(d.items);
    _dirty = false;
  }

  void _change(VoidCallback f) => setState(() {
    f();
    _dirty = true;
  });

  Future<void> _edit(int? index, PanelContacts d) async {
    if (index == null && _items.length >= d.maxContacts) {
      showToast('अधिकतम ${d.maxContacts} संपर्क');
      return;
    }
    final r = await showGlassSheet<PanelContact>(
      context,
      (_) => ContactForm(initial: index == null ? null : _items[index]),
    );
    if (r == null) return;
    _change(() => index == null ? _items.add(r) : _items[index] = r);
  }

  void _menu(int i, PanelContacts d) {
    final c = _items[i];
    showActions(
      context,
      title: c.name,
      actions: [
        SheetAction('बदलें / Edit', CupertinoIcons.pencil, () => _edit(i, d)),
        SheetAction(
          c.visible ? 'छिपाएँ / Hide' : 'दिखाएँ / Show',
          c.visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          () => _change(() => _items[i] = c.copyWith(visible: !c.visible)),
        ),
        if (i > 0)
          SheetAction(
            'ऊपर / Move up',
            CupertinoIcons.arrow_up,
            () => _change(() {
              final x = _items.removeAt(i);
              _items.insert(i - 1, x);
            }),
          ),
        if (i < _items.length - 1)
          SheetAction(
            'नीचे / Move down',
            CupertinoIcons.arrow_down,
            () => _change(() {
              final x = _items.removeAt(i);
              _items.insert(i + 1, x);
            }),
          ),
        SheetAction('हटाएँ / Delete', CupertinoIcons.delete, () async {
          final ok = await confirmDialog(context, title: '"${c.name}" हटाएँ?');
          if (ok) _change(() => _items.removeAt(i));
        }, destructive: true),
      ],
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || title.length > 80) return showToast('शीर्षक ज़रूरी है (≤80 अक्षर)', error: true);
    final panel = panelOf(context);
    setState(() => _saving = true);
    try {
      await panel.api.putContacts(title: title, items: _items);
      panel.bump();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      showToast('संपर्क ड्राफ्ट में सहेजे / Saved to draft');
      await showPublishSheet(context);
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<PanelContacts>(
      title: 'विशेष जानकार',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.contacts(),
      floatingBuilder: (context, d) => d == null || !_dirty
          ? null
          : Positioned(
              left: 14,
              right: 14,
              bottom: 10 + MediaQuery.paddingOf(context).bottom,
              child: Glass(
                padding: const EdgeInsets.all(8),
                child: PrimaryButton(
                  label: 'सहेजें / Save to draft',
                  icon: CupertinoIcons.check_mark,
                  busy: _saving,
                  onPressed: _save,
                ),
              ),
            ),
      builder: (context, d, reload) {
        _seed(d);
        return [
          PadSliver(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            child: SliverMainAxisGroup(
              slivers: [
                SliverList(
                  delegate: SliverChildListDelegate([
                    const DraftBanner(),
                    GlassField(
                      label: 'पेज का शीर्षक / Page title',
                      controller: _title,
                      placeholder: kContactsTitle,
                      prefix: CupertinoIcons.textformat,
                      onSubmitted: (_) => setState(() => _dirty = true),
                    ),
                    PrimaryButton(
                      label: 'संपर्क जोड़ें / Add contact',
                      icon: CupertinoIcons.person_add_solid,
                      onPressed: () => _edit(null, d),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_items.length}/${d.maxContacts} संपर्क${_dirty ? ' • बिना सहेजे बदलाव' : ''}',
                      style: TextStyle(color: p.subtext, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    if (_items.isEmpty) const EmptyNote('अभी कोई संपर्क नहीं'),
                  ]),
                ),
                SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) => _ContactRow(c: _items[i], onTap: () => _menu(i, d)),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.c, required this.onTap});
  final PanelContact c;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: c.visible ? 1 : 0.55,
        child: PressableGlass(
          radius: 16,
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Row(
            children: [
              const Icon(CupertinoIcons.person_crop_circle_fill, color: AppColors.saffron, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    if (c.role.isNotEmpty) Text(c.role, style: TextStyle(color: p.subtext, fontSize: 13)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (c.phone.isNotEmpty) Tag(c.phone, icon: CupertinoIcons.phone_fill),
                        if (c.whatsapp) const Tag('WhatsApp', color: AppColors.green),
                        if (!c.visible) const Tag('छिपा', color: AppColors.red),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.ellipsis, color: p.subtext),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit one contact. Pops the new [PanelContact] (id kept when editing).
class ContactForm extends StatefulWidget {
  const ContactForm({super.key, this.initial});
  final PanelContact? initial;
  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _role = TextEditingController(text: widget.initial?.role);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late bool _wa = widget.initial?.whatsapp ?? false;
  late bool _visible = widget.initial?.visible ?? true;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    final base = widget.initial ?? const PanelContact(id: '', name: '');
    final c = PanelContact(
      id: base.id,
      name: _name.text.trim(),
      role: _role.text.trim(),
      phone: cleanPhone(_phone.text.trim()),
      whatsapp: _wa,
      visible: _visible,
      order: base.order,
    );
    final err = contactError(c);
    if (err != null) return setState(() => _err = err);
    Navigator.pop(context, c);
  }

  Widget _switch(String label, bool v, ValueChanged<bool> on) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Glass(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: p.text, fontSize: 15)),
            ),
            CupertinoSwitch(value: v, activeTrackColor: AppColors.green, onChanged: on),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: widget.initial == null ? 'नया संपर्क' : 'संपर्क बदलें',
    onSave: _save,
    children: [
      GlassField(label: 'नाम / Name', controller: _name, required: true, prefix: CupertinoIcons.person),
      GlassField(label: 'भूमिका / Role (वैकल्पिक)', controller: _role, prefix: CupertinoIcons.briefcase),
      GlassField(
        label: 'फ़ोन / Phone (वैकल्पिक)',
        controller: _phone,
        keyboardType: TextInputType.phone,
        placeholder: '+919876543210',
        prefix: CupertinoIcons.phone,
      ),
      _switch('WhatsApp पर संपर्क', _wa, (v) => setState(() => _wa = v)),
      _switch('ऐप में दिखाएँ', _visible, (v) => setState(() => _visible = v)),
      if (_err != null) Text(_err!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
    ],
  );
}
