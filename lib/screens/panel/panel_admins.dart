import 'package:flutter/cupertino.dart';

import '../../models/panel_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// एडमिन: owner-only management of the admin accounts (`/admin/api/admins`, contract 3.5).
/// Changes here take effect immediately (they are not part of the draft/publish flow).
class PanelAdminsScreen extends StatelessWidget {
  const PanelAdminsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final panel = panelOf(context);
    final owner = panel.me?.isOwner ?? false;
    if (!owner) {
      return GlassPage(
        title: 'एडमिन / Admins',
        previousPageTitle: 'कंट्रोल',
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageView(
              icon: CupertinoIcons.lock_fill,
              title: 'सिर्फ़ मालिक',
              subtitle: 'एडमिन खाते केवल owner प्रबंधित कर सकता है',
            ),
          ),
        ],
      );
    }
    return PanelPage<PanelAdminList>(
      title: 'एडमिन / Admins',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.admins(),
      builder: (context, d, reload) {
        final p = Palette.of(context);
        return [
          PadSliver(
            child: SliverList(
              delegate: SliverChildListDelegate([
                PrimaryButton(
                  label: 'नया एडमिन जोड़ें / Add admin',
                  icon: CupertinoIcons.person_add_solid,
                  onPressed: () async {
                    final ok = await showGlassSheet<bool>(
                      context,
                      (_) => AdminCreateForm(minPassword: d.minPasswordLength, roles: d.roles),
                    );
                    if (ok == true) await reload();
                  },
                ),
                const SizedBox(height: 12),
                Text('${d.items.length} एडमिन', style: TextStyle(color: p.subtext, fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final a in d.items) _AdminRow(a: a, d: d, reload: reload),
              ]),
            ),
          ),
        ];
      },
    );
  }
}

String _since(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.a, required this.d, required this.reload});
  final PanelAdmin a;
  final PanelAdminList d;
  final Future<void> Function() reload;

  Future<void> _run(Future<void> Function() f, String done) async {
    final ok = await runWrite(f, success: done);
    if (ok) await reload();
  }

  void _menu(BuildContext context) {
    final api = panelOf(context).api;
    showActions(
      context,
      title: a.username,
      actions: [
        SheetAction(
          a.isOwner ? 'एडमिन बनाएँ / Make admin' : 'मालिक बनाएँ / Make owner',
          CupertinoIcons.person_2,
          () => _run(() => api.updateAdmin(a.username, role: a.isOwner ? 'admin' : 'owner'), 'भूमिका बदली'),
        ),
        SheetAction(
          a.disabled ? 'चालू करें / Enable' : 'बंद करें / Disable',
          a.disabled ? CupertinoIcons.play_circle : CupertinoIcons.pause_circle,
          () => _run(() => api.updateAdmin(a.username, disabled: !a.disabled), a.disabled ? 'चालू किया' : 'बंद किया'),
        ),
        SheetAction('पासवर्ड रीसेट / Reset password', CupertinoIcons.lock_rotation, () async {
          final ok = await showGlassSheet<bool>(
            context,
            (_) => AdminPasswordForm(username: a.username, minPassword: d.minPasswordLength),
          );
          if (ok == true) await reload();
        }),
        SheetAction('सभी सत्र बंद / Revoke sessions', CupertinoIcons.square_arrow_right, () async {
          try {
            final n = await api.revokeAdminSessions(a.username);
            showToast('$n सत्र बंद किए');
            await reload();
          } catch (e) {
            showError(e);
          }
        }),
        SheetAction('हटाएँ / Delete', CupertinoIcons.delete, () async {
          final ok = await confirmDialog(
            context,
            title: '"${a.username}" हटाएँ?',
            message: 'यह खाता और उसके सत्र हट जाएँगे।',
          );
          if (ok) await _run(() => api.deleteAdmin(a.username), 'हटाया');
        }, destructive: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableGlass(
        radius: 16,
        padding: const EdgeInsets.all(14),
        onTap: a.you ? () => showToast('अपना खाता यहाँ नहीं बदला जा सकता (सेटिंग्स → पासवर्ड)') : () => _menu(context),
        child: Row(
          children: [
            Icon(
              a.isOwner ? CupertinoIcons.shield_lefthalf_fill : CupertinoIcons.person_fill,
              color: a.disabled ? p.subtext : AppColors.saffron,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.username,
                    style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Tag(a.isOwner ? 'owner' : 'admin', color: a.isOwner ? AppColors.maroon : AppColors.saffron),
                      if (a.you) const Tag('आप', color: AppColors.blue),
                      if (a.disabled) const Tag('बंद', color: AppColors.red),
                      Tag('${a.activeSessions} सत्र', color: AppColors.green),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('अंतिम बार: ${_since(a.lastSeen)}', style: TextStyle(color: p.subtext, fontSize: 12)),
                ],
              ),
            ),
            if (!a.you) Icon(CupertinoIcons.ellipsis, color: p.subtext),
          ],
        ),
      ),
    );
  }
}

class AdminCreateForm extends StatefulWidget {
  const AdminCreateForm({super.key, required this.minPassword, required this.roles});
  final int minPassword;
  final List<String> roles;
  @override
  State<AdminCreateForm> createState() => _AdminCreateFormState();
}

class _AdminCreateFormState extends State<AdminCreateForm> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  String _role = 'admin';
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final u = _user.text.trim().toLowerCase();
    final err = adminUsernameError(u) ?? adminPasswordError(_pw.text, u, min: widget.minPassword);
    if (err != null) return setState(() => _err = err);
    final api = panelOf(context).api;
    setState(() {
      _err = null;
      _busy = true;
    });
    final ok = await runWrite(() => api.createAdmin(u, _pw.text, role: _role), success: 'एडमिन जोड़ा');
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'नया एडमिन',
      busy: _busy,
      onSave: _save,
      children: [
        GlassField(
          label: 'यूज़रनेम / Username',
          controller: _user,
          required: true,
          placeholder: 'a-z 0-9 _ . -',
          prefix: CupertinoIcons.person,
        ),
        GlassField(
          label: 'पासवर्ड / Password (≥${widget.minPassword})',
          controller: _pw,
          required: true,
          obscure: true,
          prefix: CupertinoIcons.lock,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 8,
            children: [
              for (final r in widget.roles)
                FilterChipX(r, selected: _role == r, onTap: () => setState(() => _role = r)),
            ],
          ),
        ),
        if (_err != null) Text(_err!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
      ],
    );
  }
}

class AdminPasswordForm extends StatefulWidget {
  const AdminPasswordForm({super.key, required this.username, required this.minPassword});
  final String username;
  final int minPassword;
  @override
  State<AdminPasswordForm> createState() => _AdminPasswordFormState();
}

class _AdminPasswordFormState extends State<AdminPasswordForm> {
  final _pw = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = adminPasswordError(_pw.text, widget.username, min: widget.minPassword);
    if (err != null) return setState(() => _err = err);
    final api = panelOf(context).api;
    setState(() {
      _err = null;
      _busy = true;
    });
    final ok = await runWrite(() => api.resetAdminPassword(widget.username, _pw.text), success: 'पासवर्ड बदला');
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormSheet(
    title: 'पासवर्ड रीसेट: ${widget.username}',
    busy: _busy,
    onSave: _save,
    children: [
      GlassField(
        label: 'नया पासवर्ड / New password (≥${widget.minPassword})',
        controller: _pw,
        required: true,
        obscure: true,
        prefix: CupertinoIcons.lock,
      ),
      if (_err != null) Text(_err!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
    ],
  );
}
