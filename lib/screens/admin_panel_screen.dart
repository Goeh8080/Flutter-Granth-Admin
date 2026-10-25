import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../admin/models/ai_models.dart';
import '../admin/models/panel_models.dart';
import '../admin/screens/panel/panel_admins.dart';
import '../admin/screens/panel/panel_contacts.dart';
import '../admin/screens/panel/panel_dashboard.dart';
import '../admin/screens/panel/panel_folders.dart';
import '../admin/screens/panel/panel_granths.dart';
import '../admin/screens/panel/panel_history.dart';
import '../admin/screens/panel/panel_inbox.dart';
import '../admin/screens/panel/panel_settings.dart';
import '../admin/screens/panel/panel_widgets.dart'
    show confirmLogout, pushPanel;
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../admin_ui/admin_data.dart';
import '../admin_ui/admin_kit.dart';
import '../admin_ui/admin_widgets.dart';
import '../admin_ui/ai_admin_screens.dart';
import '../admin_ui/announcement_editor.dart';
import '../config.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import '../widgets/panel.dart';

/// Tab 7 — the Admin Panel (a sliver, like every other tab of the shell).
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  StatsOverview? _stats;
  AiSummary? _ai;
  String? _statsErr;
  String _version = kAppVersion;

  AdminData get _d => AdminData.I;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted && p.version.isNotEmpty)
        setState(
          () => _version = p.buildNumber.isEmpty
              ? p.version
              : '${p.version} (${p.buildNumber})',
        );
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    if (!_d.controlReady) return;
    try {
      final api = _d.app.panel.api;
      final s = await api.statsOverview(days: 7);
      AiSummary? a;
      try {
        a = await api.aiSummary();
      } catch (_) {}
      if (mounted)
        setState(() {
          _stats = s;
          _ai = a;
          _statsErr = null;
        });
    } catch (e) {
      if (mounted) setState(() => _statsErr = '$e');
    }
  }

  void _open(Widget page) => pushPanel(context, page);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AdminData.I, AdminData.I.app.panel]),
    builder: (context, _) {
      final d = _d;
      final me = d.me;
      final ready = d.controlReady;
      final grid = d.settings?.uiGrid;
      final children = <Widget>[
        Entry(
          index: 0,
          child: PageHeader(
            tone: Tone.maroon,
            icon: 'settings',
            title: 'Admin Panel',
            subtitle: me == null
                ? 'कंट्रोल सर्वर'
                : '${me.username} · ${me.isOwner ? 'owner' : 'admin'} · लाइव v${me.version}${me.hasDraft ? ' · ड्राफ्ट बाकी' : ''}',
          ),
        ),
        const SizedBox(height: 14),
        if (!ready)
          GCard(
            child: Text(
              'कंट्रोल सर्वर में लॉगिन नहीं है। ग्रंथ/फ़ोल्डर/घोषणा/AI बदलने के लिए लॉगआउट करके कंट्रोल पासवर्ड से फिर लॉगिन करें।',
              style: GText.sans(size: 14, height: 1.45),
            ),
          )
        else ...[
          Entry(index: 1, child: _analytics()),
          const AdminLabel('पाठकों के लिए सेटिंग'),
          Entry(index: 2, child: const AiToggleCard()),
          const SizedBox(height: 10),
          Entry(index: 3, child: _gridCard(grid)),
          const SizedBox(height: 10),
          Entry(index: 4, child: _announcementCard()),
          const AdminLabel('AI प्रबंधन'),
          Entry(
            index: 5,
            child: AdminTile(
              icon: 'lightbulb',
              title: 'AI Key Points',
              sub: _ai == null
                  ? '"अगर सवाल X, तो जवाब Y" जोड़ें / बदलें'
                  : '${_ai!.kbVisible} दिखते · कुल ${_ai!.kbTotal}/${_ai!.kbMax} — तुरंत लाइव',
              tone: Tone.saffron,
              onTap: () => _open(const AiKnowledgeScreen()),
            ),
          ),
          Entry(
            index: 6,
            child: AdminTile(
              icon: 'inbox',
              title: 'यूज़र के सवाल',
              sub: 'पाठकों के सवाल देखें, जवाब दें',
              badge: _ai?.unread ?? 0,
              tone: Tone.saffron,
              onTap: () async {
                await pushPanel(context, const AiQuestionsScreen());
                _loadStats();
              },
            ),
          ),
          const AdminLabel('ग्रंथ और फ़ोल्डर'),
          Entry(
            index: 7,
            child: AdminTile(
              icon: 'folder',
              title: 'फ़ोल्डर बनाएँ / प्रबंधित करें',
              sub: 'धर्म, समूह, उप-समूह — नाम, आइकन, क्रम, हटाना',
              onTap: () => _open(const PanelFoldersScreen(startAdd: true)),
            ),
          ),
          Entry(
            index: 8,
            child: AdminTile(
              icon: 'book-open',
              title: 'ग्रंथ प्रबंधक',
              sub: 'हर ग्रंथ का फ़ोल्डर चुनें, दिखाएँ/छिपाएँ',
              onTap: () => _open(const PanelGranthsScreen()),
            ),
          ),
          Entry(
            index: 9,
            child: AdminTile(
              icon: 'inbox',
              title: 'नए ग्रंथ',
              sub: 'जिन्हें फ़ोल्डर चाहिए',
              badge: _d.app.panel.alertCount,
              onTap: () => _open(const PanelInboxScreen()),
            ),
          ),
          Entry(
            index: 10,
            child: AdminTile(
              icon: 'phone',
              title: 'विशेष जानकार',
              sub: 'ऐप में दिखने वाली संपर्क सूची',
              onTap: () => _open(const PanelContactsScreen()),
            ),
          ),
          const AdminLabel('खाते और इतिहास'),
          if (d.isOwner)
            Entry(
              index: 11,
              child: AdminTile(
                icon: 'users',
                title: 'एडमिन जोड़ें / हटाएँ',
                sub: 'सिर्फ़ owner — खाते, भूमिका, पासवर्ड, सत्र',
                onTap: () => _open(const PanelAdminsScreen()),
              ),
            ),
          AdminTile(
            icon: 'history',
            title: 'इतिहास',
            sub: 'वर्ज़न, तुलना, रोलबैक',
            onTap: () => _open(const PanelHistoryScreen()),
          ),
          AdminTile(
            icon: 'settings',
            title: 'और सेटिंग्स',
            sub: 'फ़्लैग, AI endpoint, पासवर्ड, ऑडिट',
            onTap: () => _open(const PanelSettingsScreen()),
          ),
        ],
        const AdminLabel('लॉगिन'),
        if (ready)
          AdminTile(
            icon: 'log-out',
            title: 'कंट्रोल सर्वर से लॉगआउट',
            sub: 'वेबसाइट वाला लॉगिन चालू रहेगा',
            danger: true,
            onTap: () async {
              if (await confirmLogout(context)) await _d.app.panel.logout();
            },
          ),
        AdminTile(
          icon: 'log-out',
          title: 'वेबसाइट (wnm) से लॉगआउट',
          sub: 'ग्रंथ/विषय/प्रमाण का लॉगिन',
          danger: true,
          onTap: () async {
            final yes = await confirmPopTitled(
              context,
              title: 'वेबसाइट से लॉगआउट?',
              message:
                  'ग्रंथ, विषय और प्रमाण बदलने के लिए फिर लॉगिन करना होगा।',
              confirm: 'लॉगआउट',
              destructive: true,
            );
            if (yes) await _d.app.logout();
          },
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'ग्रंथ एडमिन · संस्करण $_version${me == null ? '' : ' · लाइव कॉन्फ़िग v${me.version}'}',
            key: const ValueKey('version-line'),
            textAlign: TextAlign.center,
            style: GText.sans(size: 12.5, color: GColors.muted),
          ),
        ),
      ];
      return SliverList.list(children: children);
    },
  );

  Widget _analytics() {
    final s = _stats;
    return GCard(
      key: const ValueKey('analytics-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GIcon('bar-chart', size: 20, color: GColors.maroon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'आँकड़े · 7 दिन',
                  style: GText.display(size: 20, color: GColors.maroon),
                ),
              ),
              Pill(
                label: 'पूरे आँकड़े',
                onTap: () => _open(const PanelDashboardScreen()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (s == null)
            Text(
              _statsErr == null ? 'लोड हो रहा है…' : 'आँकड़े लोड नहीं हुए',
              style: GText.sans(size: 13.5, color: GColors.muted),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat('इंस्टॉल', s.totals.totalInstalls),
                _stat('ग्रंथ खुले', s.totals.granthOpens),
                _stat('AI सवाल', s.aiAsked, key: 'ai-asked'),
                _stat('AI जवाब', s.aiAnswered, key: 'ai-answered'),
                _stat('स्रोत टैप', s.aiCiteTap, key: 'ai-cite-tap'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, int v, {String? key}) => Container(
    key: key == null ? null : ValueKey(key),
    width: 104,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: GColors.pill,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$v', style: GText.display(size: 22, color: GColors.maroon)),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GText.sans(size: 12, color: GColors.muted),
        ),
      ],
    ),
  );

  Widget _gridCard(int? grid) => GCard(
    key: const ValueKey('grid-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const GIcon('layout-grid', size: 20, color: GColors.maroon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'पाठकों का ग्रिड',
                style: GText.sans(
                  size: 15,
                  weight: FontWeight.w800,
                  color: GColors.maroon,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          grid == null
              ? 'तय नहीं — ऐप 3×3 दिखाता है'
              : 'अभी: $grid×$grid (प्रकाशित करने पर लागू)',
          style: GText.sans(size: 12.5, color: GColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in const [1, 2, 3])
              Pill(
                key: ValueKey('grid-$n'),
                label: '$n×$n',
                tone: grid == n ? PillTone.maroon : PillTone.plain,
                minHeight: 40,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                fontSize: 14,
                onTap: () => runWrite(
                  () => _d.saveSettings(uiGrid: n),
                  success: 'ग्रिड $n×$n (ड्राफ्ट) — प्रकाशित करें',
                ),
              ),
            Pill(
              key: const ValueKey('grid-default'),
              label: 'डिफ़ॉल्ट',
              tone: grid == null ? PillTone.maroon : PillTone.plain,
              minHeight: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              fontSize: 14,
              onTap: () => runWrite(
                () => _d.saveSettings(clearUiGrid: true),
                success: 'ग्रिड डिफ़ॉल्ट (ड्राफ्ट)',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _announcementCard() {
    final a = _d.settings?.announcement;
    final on = a != null && a.enabled && a.text.trim().isNotEmpty;
    return GCard(
      key: const ValueKey('announcement-card'),
      onTap: () => showAnnouncementEditor(context),
      child: Row(
        children: [
          IconBox(
            tone: Tone.gold,
            icon: on && a.pinned ? 'pin' : 'megaphone',
            size: 40,
            radius: 12,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'पिन की हुई घोषणा',
                  style: GText.sans(
                    size: 15,
                    weight: FontWeight.w800,
                    color: GColors.maroon,
                  ),
                ),
                Text(
                  on
                      ? '${a.pinned ? 'पिन · ' : 'पिन नहीं · '}${a.expiresAt == null ? 'हटाने तक' : 'समाप्ति ${announcementExpiryLabel(a.expiresAt!)}'}\n${a.text}'
                      : 'कोई घोषणा नहीं — जोड़ने के लिए दबाएँ',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GText.sans(
                    size: 12.5,
                    color: GColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const GIcon('pen-line', size: 18, color: GColors.muted),
        ],
      ),
    );
  }
}
