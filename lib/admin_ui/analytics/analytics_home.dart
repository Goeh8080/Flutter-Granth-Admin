import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../admin/screens/panel/panel_widgets.dart' show pushPanel;
import '../../theme/colors.dart';
import '../../widgets/common.dart' show Tone;
import '../admin_kit.dart';
import '../round3_screens.dart' show EventsScreen;
import 'analytics_ai.dart';
import 'analytics_granth.dart';
import 'analytics_folders.dart';
import 'analytics_kit.dart';
import 'analytics_pdf.dart';
import 'analytics_praman.dart';
import 'analytics_report.dart';
import 'analytics_topics.dart';
import 'google_users.dart';

/// Merged live header numbers: presence (exact, 45 s window) first, GA4 as fallback/floor.
class AnLive {
  AnLive(this.p, this.ga);
  final Map<String, dynamic> p, ga;
  bool get presence => p['ready'] == true;
  int get online => presence ? anI(p['online']) : anI(ga['live_users']);
  int get total => math.max(anI(p['total_users']), anI(ga['total_users']));
  int get offline => math.max(0, total - online);
  int get today =>
      math.max(anI(p['today_users']), anI(anM(ga['today'])['active_users']));
  int get totalTime =>
      math.max(anI(p['total_time_s']), anI(ga['total_engagement_s']));
  int get todayTime =>
      math.max(anI(p['today_time_s']), anI(anM(ga['today'])['engagement_s']));
}

class AnalyticsHomeScreen extends StatefulWidget {
  const AnalyticsHomeScreen({super.key});
  @override
  State<AnalyticsHomeScreen> createState() => _AnalyticsHomeScreenState();
}

class _AnalyticsHomeScreenState extends State<AnalyticsHomeScreen> {
  Map<String, dynamic> _p = const {}, _ga = const {};
  Timer? _t;
  DateTime? _at;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ga =
        _tick++ % 6 ==
        0; // GA live every 30 s (server caches 60 s), presence every 5 s
    final r = await Future.wait([anGet('/live'), if (ga) anGet('/ga/live')]);
    if (!mounted) return;
    setState(() {
      _p = r[0];
      if (ga) _ga = r[1];
      _at = DateTime.now();
    });
  }

  Widget _header() {
    final l = AnLive(_p, _ga);
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    return anCard(key: const ValueKey('an-header'), [
      Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: GColors.online,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'लाइव डैशबोर्ड',
              style: GText.sans(
                size: 15,
                weight: FontWeight.w800,
                color: GColors.maroon,
              ),
            ),
          ),
          Text(
            _at == null ? '…' : '${hm(_at!)} IST · हर 5 से.',
            style: GText.sans(size: 11, color: GColors.muted),
          ),
        ],
      ),
      const SizedBox(height: 10),
      anStats([
        AnStat(
          'लाइव यूज़र',
          '${l.online}',
          GColors.online,
          l.presence ? 'पिछले 45 से.' : 'GA (30 मि.)',
        ),
        AnStat('कुल यूज़र', '${l.total}', GColors.maroon),
        AnStat('ऑफ़लाइन यूज़र', '${l.offline}', GColors.muted),
        AnStat('आज के यूज़र', '${l.today}', GColors.saffronDark),
        AnStat(
          'कुल समय',
          anDur(l.totalTime),
          GColors.brown,
          'आज ${anDur(l.todayTime)}',
        ),
        if (l.presence)
          AnStat(
            'ऑनलाइन (Google लॉगिन)',
            '${anI(_p['online_signed_in'])}',
            GColors.gold,
          ),
      ]),
      if (!l.presence)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: anNote(
            _p['error'] == 'migration_pending'
                ? 'प्रेज़ेंस टेबल अभी नहीं बनी — GA के आँकड़े दिखाए गए हैं'
                : 'प्रेज़ेंस डेटा अभी नहीं (यूज़र ऐप के heartbeat अपडेट के बाद लाइव होगा) — GA के आँकड़े दिखाए गए हैं',
          ),
        ),
      if (anL(_p['screens']).isNotEmpty) ...[
        anTitle('अभी कौन-सी स्क्रीन पर'),
        anTop5([
          for (final s in anL(_p['screens'])) (anS(s['screen']), anI(s['n'])),
        ], color: GColors.online),
      ],
    ]);
  }

  Widget _section(
    String key,
    String icon,
    String title,
    String sub,
    Widget page,
  ) => AdminTile(
    key: ValueKey('an-$key'),
    icon: icon,
    title: title,
    sub: sub,
    tone: Tone.saffron,
    onTap: () => pushPanel(context, page),
  );

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'एनालिटिक्स',
    onRefresh: _refresh,
    trailing: FilledButton.icon(
      key: const ValueKey('an-document'),
      style: FilledButton.styleFrom(backgroundColor: GColors.maroon),
      onPressed: () => pushPanel(context, const AnalyticsReportScreen()),
      icon: const Icon(Icons.description_outlined, size: 18),
      label: const Text('Document'),
    ),
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _section(
              'pdf',
              'file-text',
              'PDF',
              'बने, डाउनलोड, फेल · टॉप 5',
              const AnalyticsPdfScreen(),
            ),
            _section(
              'granth',
              'book-open',
              'ग्रंथ',
              'ग्रंथ/फ़ोल्डर खुले, पढ़ने का समय · टॉप 5',
              const AnalyticsGranthScreen(),
            ),
            _section(
              'folders',
              'folder',
              'फ़ोल्डर',
              'कौन-से फ़ोल्डर खुले — नाम व गिनती · पूरी सूची',
              const AnalyticsFoldersScreen(),
            ),
            _section(
              'praman',
              'check',
              'प्रमाण',
              'प्रमाण खुले, AI से प्रमाण टैप · टॉप 5',
              const AnalyticsPramaanScreen(),
            ),
            _section(
              'topics',
              'lightbulb',
              'विषय / Topics',
              'विषय खुले · टॉप 5',
              const AnalyticsTopicsScreen(),
            ),
            _section(
              'ai',
              'sparkles',
              'AI',
              'प्रश्न, जवाब, फेल दर · टॉप 5 फेल प्रश्न',
              const AnalyticsAiScreen(),
            ),
            _section(
              'gusers',
              'users',
              'Google यूज़र',
              'लॉगिन किए सभी यूज़र — नाम, Gmail, फ़ोटो, समय',
              const GoogleUsersScreen(),
            ),
            _section(
              'ga4',
              'bar-chart',
              'GA4 विस्तृत',
              'पुराना पूरा GA4 पेज (डिवाइस, वर्ज़न, Sync…)',
              const EventsScreen(),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Settings / hub card that opens the analytics home.
class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({super.key});
  @override
  Widget build(BuildContext context) => AdminTile(
    key: const ValueKey('r3-analytics'),
    icon: 'bar-chart',
    title: 'एनालिटिक्स / Analytics',
    sub: 'लाइव यूज़र, PDF, ग्रंथ, प्रमाण, विषय, AI, Google यूज़र, रिपोर्ट',
    tone: Tone.saffron,
    onTap: () => pushPanel(context, const AnalyticsHomeScreen()),
  );
}
