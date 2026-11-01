import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../admin/widgets/toast.dart';
import '../../theme/colors.dart';
import '../../widgets/common.dart';
import '../admin_kit.dart';
import 'analytics_home.dart' show AnLive;
import 'analytics_kit.dart';

const _kinds = <(String, String)>[
  ('granths', 'ग्रंथ खुले'),
  ('folders', 'फ़ोल्डर खुले'),
  ('downloads', 'PDF डाउनलोड'),
  ('pdf_generate', 'PDF बने'),
  ('praman', 'प्रमाण'),
  ('topics', 'विषय'),
  ('ai_fail', 'AI फेल प्रश्न'),
  ('sync_fail', 'Sync फेल'),
];

/// "Document": the full report — every counter, every top list, today + live, in one page (copyable).
class AnalyticsReportScreen extends StatefulWidget {
  const AnalyticsReportScreen({super.key});
  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  int _days = 30;
  AnData? _d;
  Map<String, Map<String, dynamic>> _tops = {};
  List<Map<String, dynamic>> _folders = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final d = await AnData.load(_days);
    final t = await Future.wait([for (final k in _kinds) d.top(k.$1)]);
    final f = await anGet('/stats/folders', query: {'days': '$_days'});
    if (!mounted) return;
    setState(() {
      _d = d;
      _tops = {for (var i = 0; i < _kinds.length; i++) _kinds[i].$1: t[i]};
      _folders = anL(f['items']);
      _busy = false;
    });
  }

  List<(String, String)> _rows(AnData d) {
    final l = AnLive(d.presence, d.live);
    final ai1 = anM(d.d1['ai']),
        pdf1 = anM(d.d1['pdf']),
        sync1 = anM(d.d1['sync']);
    final gt = d.gaT,
        t = d.today,
        at = anM(d.ga['all_time']),
        ret = anM(d.ga['retention']);
    return [
      ('— लाइव —', ''),
      ('लाइव यूज़र', '${l.online}'),
      ('कुल यूज़र', '${l.total}'),
      ('ऑफ़लाइन यूज़र', '${l.offline}'),
      ('आज के यूज़र', '${l.today}'),
      ('कुल समय', anDur(l.totalTime)),
      ('आज का समय', anDur(l.todayTime)),
      ('— आज (GA आज + रियलटाइम) —', ''),
      for (final k in const [
        'active_users',
        'new_users',
        'sessions',
        'app_opens',
        'installs',
        'screen_views',
        'granth_open',
        'folder_open',
        'praman_open',
        'cite_tap',
        'pdf_generate',
        'pdf_download',
        'pdf_fail',
        'ai_ask',
        'ai_answer',
        'ai_fail',
        'sync_ok',
        'sync_fail',
      ])
        (k, '${anI(t[k])}'),
      ('— ${d.days} दिन (GA / D1 → सर्वश्रेष्ठ) —', ''),
      ('सक्रिय यूज़र (GA)', '${anI(gt['active_users'])}'),
      ('नए यूज़र (GA)', '${anI(gt['new_users'])}'),
      ('सेशन', '${d.best('sessions', d.d1T['sessions'])}'),
      ('स्क्रीन व्यू', '${anI(gt['screen_views'])}'),
      ('एंगेजमेंट समय', anDur(gt['engagement_s'])),
      ('ऐप फ़ोरग्राउंड समय (D1)', anDur(d.d1T['app_fg_s'])),
      ('ऐप खुला', '${d.best('app_opens', d.d1Ev['app_open'])}'),
      ('इंस्टॉल', '${d.best('installs', d.d1T['new_installs_in_range'])}'),
      ('ग्रंथ खुले', '${d.best('granth_open', d.d1T['granth_opens'])}'),
      ('फ़ोल्डर खुले', '${d.best('folder_open', d.d1T['folder_opens'])}'),
      ('ग्रंथ पढ़ने का समय (D1)', anDur(d.d1T['granth_watch_s'])),
      ('प्रमाण खुले', '${d.best('praman_open', d.d1T['praman_opens'])}'),
      ('विषय खुले', '${d.best('topic_open', d.d1T['topic_opens'])}'),
      ('AI प्रमाण टैप', '${d.best('cite_tap', ai1['cite_tap'])}'),
      ('PDF बने', '${d.best('pdf_generate', pdf1['ok'])}'),
      ('PDF डाउनलोड', '${d.best('pdf_download', d.d1Ev['pdf_download'])}'),
      ('PDF फेल', '${d.best('pdf_fail', pdf1['fail'])}'),
      ('AI प्रश्न', '${d.best('ai_ask', ai1['asked'])}'),
      (
        'AI जवाब',
        '${d.best('ai_answer', d.d1Ev['ai_answer'] ?? ai1['answered'])}',
      ),
      ('AI फेल', '${d.best('ai_fail', d.d1Ev['ai_fail'])}'),
      ('Sync सफल', '${d.best('sync_ok', sync1['ok'])}'),
      ('Sync फेल', '${d.best('sync_fail', sync1['fail'])}'),
      ('— सब समय —', ''),
      ('इंस्टॉल (GA)', '${anI(at['installs'])}'),
      ('इंस्टॉल (D1)', '${anI(d.d1T['total_installs'])}'),
      ('ऐप खुला (GA)', '${anI(at['app_opens'])}'),
      ('PDF बने (GA)', '${anI(at['pdf_generate'])}'),
      ('PDF डाउनलोड (GA)', '${anI(at['pdf_download'])}'),
      (
        'DAU / WAU / MAU (GA)',
        '${anI(ret['dau'])} / ${anI(ret['wau'])} / ${anI(ret['mau'])}',
      ),
    ];
  }

  String _text(AnData d) {
    final b = StringBuffer(
      'ग्रंथ प्रबंधन — एनालिटिक्स रिपोर्ट (${d.days} दिन) · ${anIst(DateTime.now().toUtc().toIso8601String())}\n\n',
    );
    for (final r in _rows(d)) {
      b.writeln(r.$2.isEmpty ? '\n${r.$1}' : '${r.$1}: ${r.$2}');
    }
    for (final k in _kinds) {
      b.writeln('\nटॉप — ${k.$2}');
      var i = 0;
      for (final e in anTopItems(_tops[k.$1] ?? const {}).take(20)) {
        b.writeln('${++i}. ${e.$1} — ${e.$2}');
      }
      if (i == 0) b.writeln('(डेटा नहीं)');
    }
    return b.toString();
  }

  Widget _list(String title, List<(String, num)> items) => anCard([
    anTitle(title),
    if (items.isEmpty) anNote('डेटा नहीं'),
    for (var i = 0; i < items.length && i < 200; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${i + 1}.',
                style: GText.sans(size: 12.5, color: GColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                items[i].$1,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GText.sans(size: 12.5),
              ),
            ),
            Text(
              '${items[i].$2}',
              style: GText.sans(
                size: 12.5,
                weight: FontWeight.w700,
                color: GColors.maroon,
              ),
            ),
          ],
        ),
      ),
  ]);

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return AdminSubPage(
      title: 'पूरी रिपोर्ट',
      onRefresh: _load,
      trailing: IconButton(
        tooltip: 'कॉपी करें',
        onPressed: d == null
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: _text(d)));
                showToast('रिपोर्ट कॉपी हुई');
              },
        icon: const Icon(Icons.copy_all, color: GColors.maroon),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnRange(
                days: _days,
                onChanged: (v) {
                  _days = v;
                  _load();
                },
              ),
              if (d == null)
                const EmptyState(title: 'लोड हो रहा है…', spinner: true)
              else ...[
                if (_busy)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: GColors.saffron,
                  ),
                if (d.errors.isNotEmpty) anCard([anNote(d.errors.join(' · '))]),
                anCard([
                  for (final r in _rows(d))
                    r.$2.isEmpty
                        ? anTitle(r.$1)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.$1,
                                    style: GText.sans(size: 13),
                                  ),
                                ),
                                Text(
                                  r.$2,
                                  style: GText.sans(
                                    size: 13,
                                    weight: FontWeight.w800,
                                    color: GColors.maroon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                ]),
                anCard([
                  anTitle('हर दिन — ऐप खुला / सक्रिय यूज़र'),
                  anDayBars(d.byDay, const [
                    ('app_opens', 'ऐप खुला', GColors.saffron),
                    ('active_users', 'यूज़र', GColors.maroon),
                  ]),
                ]),
                for (final k in _kinds)
                  _list(
                    'टॉप — ${k.$2} (GA)',
                    anTopItems(_tops[k.$1] ?? const {}, names: anNames(k.$1)),
                  ),
                _list('फ़ोल्डर — खुले, नाम सहित (D1, पूरी सूची)', [
                  for (final x in _folders) (anS(x['label']), anI(x['opens'])),
                ]),
                _list('टॉप ग्रंथ — पढ़ने का समय मिनट (D1)', [
                  for (final x in anL(d.d1['top_granths_watch']))
                    (anS(x['title']), anI(x['watch_s']) ~/ 60),
                ]),
                _list('स्क्रीन — व्यू (GA)', [
                  for (final x in anL(d.ga['screens']))
                    (anS(x['screen']), anI(x['views'])),
                ]),
                _list('ऐप वर्ज़न — यूज़र (GA)', [
                  for (final x in anL(d.ga['versions']))
                    (anS(x['version']), anI(x['active_users'])),
                ]),
                _list('डिवाइस (GA)', [
                  for (final x in anL(d.ga['devices']))
                    (anS(x['model']), anI(x['active_users'])),
                ]),
                _list('इंस्टॉल — वर्ज़न (D1)', [
                  for (final x in anL(d.d1['installs_by_version']))
                    (anS(x['app']), anI(x['n'])),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
