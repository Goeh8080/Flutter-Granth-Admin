import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/glass_scaffold.dart';
import 'panel_admins.dart';
import 'panel_contacts.dart';
import 'panel_dashboard.dart';
import 'panel_folders.dart';
import 'panel_granths.dart';
import 'panel_history.dart';
import 'panel_inbox.dart';
import 'panel_login.dart';
import 'panel_settings.dart';
import 'panel_widgets.dart';

/// The "कंट्रोल" tab: hub for everything on the control server.
class PanelHome extends StatelessWidget {
  const PanelHome({super.key, this.bottomInset = 0});
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, listen: true);
    final panel = app.panel;
    if (!panel.loggedIn) return PanelLoggedOutView(bottomInset: bottomInset);
    final p = Palette.of(context);
    final me = panel.me;
    return PanelPage<int>(
      title: 'ऐप कंट्रोल',
      bottomInset: bottomInset,
      load: (api) async {
        await panel.refreshMe();
        await panel.refreshAlerts();
        return panel.revision;
      },
      builder: (context, _, reload) => [
        PadSliver(
          child: SliverList(
            delegate: SliverChildListDelegate([
              Glass(
                blur: 16,
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [AppColors.saffron, AppColors.maroon]),
                      ),
                      child: const Icon(CupertinoIcons.slider_horizontal_3, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me?.username ?? 'एडमिन',
                            style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            me == null
                                ? 'कंट्रोल सर्वर'
                                : 'लाइव ऐप कॉन्फ़िग: v${me.version}${me.hasDraft ? ' • ड्राफ्ट बाकी' : ''}',
                            style: TextStyle(color: p.subtext, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const DraftBanner(),
              MenuRow(
                CupertinoIcons.chart_bar_alt_fill,
                'आँकड़े / Stats',
                () => pushPanel(context, const PanelDashboardScreen()),
                sub: 'इंस्टॉल, उपयोग-समय, सबसे ज़्यादा देखे गए',
              ),
              MenuRow(
                CupertinoIcons.book_fill,
                'ग्रंथ / Granths',
                () => pushPanel(context, const PanelGranthsScreen()),
                sub: 'फ़ोल्डर तय करें, दिखाएँ/छिपाएँ',
              ),
              MenuRow(
                CupertinoIcons.folder_fill,
                'फ़ोल्डर / Folders',
                () => pushPanel(context, const PanelFoldersScreen()),
                sub: 'धर्म, समूह, उप-समूह',
              ),
              MenuRow(
                CupertinoIcons.phone_fill,
                'विशेष जानकार / Contacts',
                () => pushPanel(context, const PanelContactsScreen()),
                sub: 'संपर्क सूची जो ऐप में दिखती है',
              ),
              if (me?.isOwner ?? false)
                MenuRow(
                  CupertinoIcons.person_2_fill,
                  'एडमिन / Admins',
                  () => pushPanel(context, const PanelAdminsScreen()),
                  sub: 'खाते जोड़ें, भूमिका, पासवर्ड, सत्र',
                ),
              MenuRow(
                CupertinoIcons.tray_arrow_down_fill,
                'नए ग्रंथ / Inbox',
                () => pushPanel(context, const PanelInboxScreen()),
                sub: 'जिन्हें फ़ोल्डर चाहिए',
                badge: panel.alertCount,
              ),
              MenuRow(
                CupertinoIcons.clock_fill,
                'इतिहास / History',
                () => pushPanel(context, const PanelHistoryScreen()),
                sub: 'वर्ज़न, तुलना, रोलबैक',
              ),
              MenuRow(
                CupertinoIcons.gear_solid,
                'सेटिंग्स / Settings',
                () => pushPanel(context, const PanelSettingsScreen()),
                sub: 'फ़्लैग, घोषणा, AI, पासवर्ड, ऑडिट',
              ),
              MenuRow(CupertinoIcons.square_arrow_right, 'कंट्रोल से लॉगआउट / Logout', () async {
                final ok = await confirmLogout(context);
                if (ok) await panel.logout();
              }, destructive: true),
            ]),
          ),
        ),
      ],
    );
  }
}
