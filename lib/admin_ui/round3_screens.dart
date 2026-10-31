import 'package:flutter/material.dart';

import '../admin/screens/panel/panel_widgets.dart' show pushPanel, shortTs;
import '../admin/services/panel_api.dart';
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../admin/widgets/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_actions.dart' show SortChips;
import 'admin_data.dart';
import 'admin_kit.dart';

PanelApi get _api => AdminData.I.app.panel.api;

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
Map<String, dynamic> _m(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) =>
    v is List ? v.map(_m).toList() : <Map<String, dynamic>>[];

/// Parses "a, b c" into trending topic ids: `[A-Za-z0-9_-]{1,40}`, deduped, ≤ [max].
/// Returns null (with [onError]) when an id is invalid or there are too many.
List<String>? parseTopicIds(String raw, {int max = 12}) {
  final out = <String>[];
  for (final t in raw.split(RegExp(r'[\s,]+'))) {
    if (t.isEmpty) continue;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(t)) return null;
    if (!out.contains(t)) out.add(t);
  }
  return out.length > max ? null : out;
}

/// Tiles for the hub and Settings: सपोर्ट, AI फ़्लैग, ट्रेंडिंग/प्रमाण, एनालिटिक्स.
class Round3Entries extends StatefulWidget {
  const Round3Entries({super.key});
  @override
  State<Round3Entries> createState() => _Round3EntriesState();
}

class _Round3EntriesState extends State<Round3Entries> {
  int _sup = 0, _flags = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await _api.raw('GET', '/support/unread');
      final f = await _api.raw('GET', '/ai/flags/summary');
      if (mounted) {
        setState(() {
          _sup = _i(a['unread']);
          _flags = _i(f['new']);
        });
      }
    } catch (_) {}
  }

  Future<void> _go(Widget w) async {
    await pushPanel(context, w);
    _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminTile(
        key: const ValueKey('r3-support'),
        icon: 'message-circle',
        title: 'सपोर्ट टिकट',
        sub: 'रोज़ के टोकन (#1, #2…) — जवाब यूज़र के ऐप में जाता है',
        badge: _sup,
        tone: Tone.saffron,
        onTap: () => _go(const SupportScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-flags'),
        icon: 'alert-triangle',
        title: 'AI फ़्लैग (👎)',
        sub: 'जिन AI जवाबों को पाठकों ने ग़लत बताया',
        badge: _flags,
        tone: Tone.saffron,
        onTap: () => _go(const AiFlagsScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-highlights'),
        icon: 'sparkles',
        title: 'ट्रेंडिंग / आज का प्रमाण',
        sub: 'config में जाता है — ड्राफ्ट, फिर प्रकाशित करें',
        tone: Tone.saffron,
        onTap: () => _go(const HighlightsScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-events'),
        icon: 'bar-chart',
        title: 'एनालिटिक्स (GA4)',
        sub: 'इंस्टॉल, ऐप खुला, ग्रंथ/फ़ोल्डर, PDF, AI फेल, रियलटाइम',
        tone: Tone.saffron,
        onTap: () => _go(const EventsScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-features'),
        icon: 'settings',
        title: 'फ़ीचर स्विच',
        sub: 'सपोर्ट, ट्रेंडिंग, आज का प्रमाण, सूचनाएँ, AI — चालू/बंद',
        tone: Tone.saffron,
        onTap: () => _go(const FeatureFlagsScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-notify'),
        icon: 'bell',
        title: 'सूचना भेजें',
        sub: 'टॉपिक पर पुश सूचना (FCM) + इतिहास',
        tone: Tone.saffron,
        onTap: () => _go(const NotifyScreen()),
      ),
    ],
  );
}

class _Load extends StatefulWidget {
  const _Load({required this.load, required this.builder, super.key});
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(
    BuildContext,
    Map<String, dynamic>,
    Future<void> Function(),
  )
  builder;
  @override
  State<_Load> createState() => _LoadState();
}

class _LoadState extends State<_Load> {
  Map<String, dynamic>? _v;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    try {
      final v = await widget.load();
      if (mounted)
        setState(() {
          _v = v;
          _err = null;
        });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_v != null) return widget.builder(context, _v!, _go);
    if (_err == null) {
      return const EmptyState(title: 'लोड हो रहा है…', spinner: true);
    }
    return EmptyState(
      title: 'लोड नहीं हो सका',
      body: '$_err',
      actionLabel: 'फिर कोशिश करें',
      onAction: _go,
    );
  }
}

Text _title(String t) => Text(
  t,
  style: GText.sans(
    size: 15,
    weight: FontWeight.w800,
    color: GColors.maroon,
    height: 1.35,
  ),
);
Text _sub(String t) =>
    Text(t, style: GText.sans(size: 12, color: GColors.muted));
Text _body(String t) => Text(t, style: GText.sans(size: 14, height: 1.45));

Widget _card(Key key, List<Widget> children) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: GCard(
    key: key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('रद्द करें'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('हाँ'),
          ),
        ],
      ),
    ) ??
    false;

// ---------------------------------------------------------------------------- support

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  String _st = 'open';

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'सपोर्ट टिकट',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          key: ValueKey(_st),
          load: () => _api.raw(
            'GET',
            '/support/tickets',
            query: {'status': _st, 'limit': '100'},
          ),
          builder: (context, d, refresh) {
            final c = _m(d['counts']);
            final items = _l(d['items']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sub(
                  'आज ${_s(d['today'])} · आज के टिकट ${_i(c['today'])} · टोकन रोज़ रात 12 बजे (IST) 1 से शुरू',
                ),
                const SizedBox(height: 8),
                SortChips<String>(
                  options: [
                    ('open', 'खुले ${_i(c['open'])}'),
                    ('unread', 'नए ${_i(c['unread'])}'),
                    ('closed', 'बंद ${_i(c['closed'])}'),
                    ('all', 'सब'),
                  ],
                  value: _st,
                  onChanged: (v) => setState(() => _st = v),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const EmptyState(
                    title: 'कोई टिकट नहीं',
                    body: 'पाठकों के सपोर्ट टिकट यहाँ दिखेंगे।',
                  ),
                for (final t in items)
                  _card(ValueKey('t-${t['id']}'), [
                    _title(
                      '#${_s(t['token'])} · ${_s(t['date'])}${t['unread'] == true ? ' · नया' : ''}${t['status'] == 'closed' ? ' · बंद' : ''}',
                    ),
                    if (_s(t['subject']).isNotEmpty) _body(_s(t['subject'])),
                    const SizedBox(height: 4),
                    Text(
                      _s(t['message']),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GText.sans(size: 14, height: 1.45),
                    ),
                    const SizedBox(height: 4),
                    _sub(
                      [
                        _s(t['name']),
                        _s(t['contact']),
                        shortTs(_s(t['created_at'])),
                        if (_i(t['messages_count']) > 0)
                          '${_i(t['messages_count'])} संदेश',
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(
                          label: 'खोलें / जवाब',
                          tone: PillTone.maroon,
                          onTap: () async {
                            await pushPanel(
                              context,
                              SupportTicketScreen(id: _i(t['id'])),
                            );
                            refresh();
                          },
                        ),
                        Pill(
                          label: t['status'] == 'closed'
                              ? 'फिर खोलें'
                              : 'बंद करें',
                          onTap: () async {
                            final op = t['status'] == 'closed'
                                ? 'reopen'
                                : 'close';
                            if (await runWrite(
                              () => _api.raw(
                                'POST',
                                '/support/tickets/${t['id']}/$op',
                              ),
                              success: op == 'close' ? 'बंद किया' : 'फिर खोला',
                            )) {
                              refresh();
                            }
                          },
                        ),
                      ],
                    ),
                  ]),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({super.key, required this.id});
  final int id;
  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _reply = TextEditingController();
  bool _close = false;
  int _rev = 0;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'टिकट',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          key: ValueKey(_rev),
          load: () => _api.raw('GET', '/support/tickets/${widget.id}'),
          builder: (context, t, refresh) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _card(const ValueKey('head'), [
                _title('टोकन #${_s(t['token'])} · ${_s(t['date'])}'),
                _sub(
                  [
                    _s(t['name']),
                    _s(t['contact']),
                    if (_s(t['app_version']).isNotEmpty)
                      'ऐप ${t['app_version']}',
                    'यूज़र ${_s(t['install'])}',
                  ].where((x) => x.isNotEmpty).join(' · '),
                ),
                const SizedBox(height: 6),
                if (_s(t['subject']).isNotEmpty) _title(_s(t['subject'])),
                _body(_s(t['message'])),
              ]),
              for (final m in _l(t['messages']))
                _card(ValueKey('m-${m['id']}'), [
                  _sub(
                    '${m['from'] == 'admin' ? 'एडमिन ${_s(m['by'])}' : 'यूज़र'} · ${shortTs(_s(m['at']))}',
                  ),
                  _body(_s(m['text'])),
                ]),
              if (t['status'] == 'open') ...[
                AdminField(
                  controller: _reply,
                  label: 'जवाब (≤2000 अक्षर)',
                  maxLines: 5,
                ),
                CheckboxListTile(
                  value: _close,
                  onChanged: (v) => setState(() => _close = v ?? false),
                  title: const Text('जवाब के साथ टिकट बंद करें'),
                  contentPadding: EdgeInsets.zero,
                ),
                SheetButton(
                  label: 'जवाब भेजें',
                  primary: true,
                  icon: 'send',
                  onTap: () async {
                    final text = _reply.text.trim();
                    if (text.isEmpty || text.runes.length > 2000) {
                      showToast('जवाब 1–2000 अक्षर का हो');
                      return;
                    }
                    if (await runWrite(
                      () => _api.raw(
                        'POST',
                        '/support/tickets/${widget.id}/reply',
                        body: {'text': text, 'close': _close},
                      ),
                      success: 'जवाब भेजा — यूज़र के ऐप में दिखेगा',
                    )) {
                      _reply.clear();
                      setState(() => _rev++);
                    }
                  },
                ),
              ] else
                _sub('टिकट बंद है'),
              const SizedBox(height: 12),
              SheetButton(
                label: 'टिकट हटाएँ',
                icon: 'trash-2',
                onTap: () async {
                  if (!await _confirm(context, 'टिकट हटाएँ?')) return;
                  if (await runWrite(
                    () => _api.raw('DELETE', '/support/tickets/${widget.id}'),
                    success: 'हटाया',
                  )) {
                    if (context.mounted) Navigator.of(context).maybePop();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------- AI flags

class AiFlagsScreen extends StatefulWidget {
  const AiFlagsScreen({super.key});
  @override
  State<AiFlagsScreen> createState() => _AiFlagsScreenState();
}

class _AiFlagsScreenState extends State<AiFlagsScreen> {
  String _st = 'new';

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'AI फ़्लैग (👎)',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          key: ValueKey(_st),
          load: () => _api.raw(
            'GET',
            '/ai/flags',
            query: {'status': _st, 'limit': '100'},
          ),
          builder: (context, d, refresh) {
            final c = _m(d['counts']);
            final items = _l(d['items']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sub(
                  'पिछले 7 दिन: ${_i(c['last_7d'])} · सही जवाब "AI Key Notes" में जोड़ें',
                ),
                const SizedBox(height: 8),
                SortChips<String>(
                  options: [
                    ('new', 'नए ${_i(c['new'])}'),
                    ('reviewed', 'देखे ${_i(c['reviewed'])}'),
                    ('all', 'सब'),
                  ],
                  value: _st,
                  onChanged: (v) => setState(() => _st = v),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty) const EmptyState(title: 'कोई फ़्लैग नहीं'),
                for (final f in items)
                  _card(ValueKey('f-${f['id']}'), [
                    _title(_s(f['question'])),
                    const SizedBox(height: 4),
                    _body(_s(f['answer'])),
                    if (_s(f['reason']).isNotEmpty)
                      _sub('कारण: ${f['reason']}'),
                    _sub(
                      [
                        shortTs(_s(f['created_at'])),
                        _s(f['lang']),
                        if (_s(f['app_version']).isNotEmpty)
                          'ऐप ${f['app_version']}',
                        if (f['status'] == 'reviewed')
                          'देखा · ${_s(f['reviewed_by'])}',
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        Pill(
                          label: f['status'] == 'new'
                              ? 'देख लिया'
                              : 'फिर नया करें',
                          tone: PillTone.maroon,
                          onTap: () async {
                            if (await runWrite(
                              () => _api.raw(
                                'POST',
                                '/ai/flags/${f['id']}/review',
                                body: {'reviewed': f['status'] == 'new'},
                              ),
                              success: 'सेव',
                            )) {
                              refresh();
                            }
                          },
                        ),
                        Pill(
                          label: 'हटाएँ',
                          onTap: () async {
                            if (!await _confirm(context, 'फ़्लैग हटाएँ?'))
                              return;
                            if (await runWrite(
                              () => _api.raw('DELETE', '/ai/flags/${f['id']}'),
                              success: 'हटाया',
                            )) {
                              refresh();
                            }
                          },
                        ),
                      ],
                    ),
                  ]),
              ],
            );
          },
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------- trending + praman

class HighlightsScreen extends StatelessWidget {
  const HighlightsScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'ट्रेंडिंग / आज का प्रमाण',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          load: () => _api.raw('GET', '/settings'),
          builder: (context, s, refresh) => _HighlightsForm(s: s),
        ),
      ),
    ],
  );
}

class _HighlightsForm extends StatefulWidget {
  const _HighlightsForm({required this.s});
  final Map<String, dynamic> s;
  @override
  State<_HighlightsForm> createState() => _HighlightsFormState();
}

class _HighlightsFormState extends State<_HighlightsForm> {
  late final TextEditingController _ids, _pid, _pdate, _ptitle, _ptext;

  @override
  void initState() {
    super.initState();
    final t = _m(widget.s['trending']), p = _m(widget.s['daily_praman']);
    _ids = TextEditingController(
      text: (t['topic_ids'] is List ? t['topic_ids'] as List : const []).join(
        ', ',
      ),
    );
    _pid = TextEditingController(text: _s(p['id']));
    _pdate = TextEditingController(text: _s(p['date']));
    _ptitle = TextEditingController(text: _s(p['title']));
    _ptext = TextEditingController(text: _s(p['text']));
  }

  @override
  void dispose() {
    for (final c in [_ids, _pid, _pdate, _ptitle, _ptext]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final max = _i(_m(widget.s['highlight_limits'])['topics']);
    final ids = parseTopicIds(_ids.text, max: max > 0 ? max : 12);
    if (ids == null) {
      showToast('टॉपिक id: A-Z a-z 0-9 _ - (≤40), ज़्यादा से ज़्यादा 12');
      return;
    }
    final date = _pdate.text.trim();
    if (date.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      showToast('तारीख YYYY-MM-DD हो, या खाली');
      return;
    }
    final pid = _pid.text.trim();
    final body = {
      'trending': ids.isEmpty
          ? null
          : {
              'topic_ids': ids,
              // keep any per-topic titles/notes whose topic is still listed
              'items': _l(_m(widget.s['trending'])['items'])
                  .where((it) => ids.contains(_s(it['topic_id'])))
                  .toList(),
            },
      'daily_praman': pid.isEmpty
          ? null
          : {
              'id': pid,
              'date': date,
              if (_ptitle.text.trim().isNotEmpty) 'title': _ptitle.text.trim(),
              if (_ptext.text.trim().isNotEmpty) 'text': _ptext.text.trim(),
            },
    };
    await runWrite(
      () => _api.raw('PUT', '/settings', body: body),
      success: 'ड्राफ्ट में सेव — "प्रकाशित करें" से ऐप में जाएगा',
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sub(
        'खाली छोड़ें तो ऐप में वह पंक्ति नहीं दिखेगी। बदलाव ड्राफ्ट में जाता है।',
      ),
      const SizedBox(height: 10),
      AdminField(
        controller: _ids,
        label: 'ट्रेंडिंग टॉपिक id (कॉमा से, क्रम से, ≤12)',
        hint: '12, 45, vrat',
      ),
      _sub(
        'प्रकाशित: ${_m(widget.s['published_trending'])['topic_ids'] ?? '—'}',
      ),
      const AdminLabel('आज का प्रमाण'),
      AdminField(controller: _pid, label: 'प्रमाण id'),
      AdminField(controller: _pdate, label: 'तारीख YYYY-MM-DD (खाली = हर दिन)'),
      AdminField(controller: _ptitle, label: 'शीर्षक (वैकल्पिक, ≤100)'),
      AdminField(
        controller: _ptext,
        label: 'पाठ (वैकल्पिक, ≤600)',
        maxLines: 3,
      ),
      _sub('प्रकाशित: ${_m(widget.s['published_daily_praman'])['id'] ?? '—'}'),
      const SizedBox(height: 12),
      SheetButton(
        label: 'ड्राफ्ट में सेव करें',
        primary: true,
        icon: 'check',
        onTap: _save,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------- analytics

/// GA4 kinds served by `GET /admin/api/ga/top?kind=`.
const kGaKinds = <(String, String)>[
  ('granths', 'ग्रंथ खुले'),
  ('folders', 'फ़ोल्डर खुले'),
  ('downloads', 'PDF डाउनलोड'),
  ('pdf_generate', 'PDF बने'),
  ('praman', 'प्रमाण'),
  ('topics', 'विषय'),
  ('ai_fail', 'AI फेल प्रश्न'),
  ('sync_fail', 'Sync फेल'),
];

const kGaDimsUrl =
    'https://analytics.google.com/analytics/web/#/p561197991/admin/customdefinitions/hub';

/// Analytics = Google Analytics 4 only (server proxies the GA Data API).
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  int _days = 30;
  String _kind = 'granths';

  Widget _row(String a, Object? n) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: _body(a)),
        Text(
          '${n is String ? n : _i(n)}',
          style: GText.sans(size: 14, weight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _days7(String title, List<Map<String, dynamic>> byDay, String key) =>
      _card(ValueKey('day-$key'), [
        _title(title),
        const SizedBox(height: 6),
        if (byDay.isEmpty) _sub('अभी कोई डेटा नहीं'),
        for (final r in byDay.reversed.take(14)) _row(_s(r['day']), r[key]),
      ]);

  Widget _list(
    String title,
    List<Map<String, dynamic>> rows,
    String l,
    String n,
  ) => _card(ValueKey('list-$title'), [
    _title(title),
    const SizedBox(height: 6),
    if (rows.isEmpty) _sub('अभी कोई डेटा नहीं'),
    for (final r in rows.take(10)) _row(_s(r[l]), r[n]),
  ]);

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'एनालिटिक्स (GA4)',
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SortChips<int>(
              options: const [(7, '7 दिन'), (30, '30 दिन'), (90, '90 दिन')],
              value: _days,
              onChanged: (v) => setState(() => _days = v),
            ),
            const SizedBox(height: 10),
            _Load(
              key: ValueKey('ov$_days'),
              load: () async {
                final r = await Future.wait([
                  _api.raw('GET', '/ga/overview', query: {'days': '$_days'}),
                  _api.raw('GET', '/support/unread'),
                ]);
                return {...r[0], 'support': r[1]};
              },
              builder: (context, d, refresh) {
                final t = _m(d['totals']), at = _m(d['all_time']);
                final rt = _m(d['retention']), sup = _m(d['support']);
                final byDay = _l(d['by_day']);
                final rate =
                    (t['ai_fail_rate'] is num ? t['ai_fail_rate'] as num : 0) *
                    100;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(const ValueKey('ga-totals'), [
                      _title('कुल'),
                      _row('अभी सक्रिय (रियलटाइम)', d['realtime_active_users']),
                      _row('इंस्टॉल अब तक (first_open)', at['installs']),
                      _row('इंस्टॉल इस अवधि में', t['installs']),
                      _row('सक्रिय यूज़र', t['active_users']),
                      _row('नए यूज़र', t['new_users']),
                      _row(
                        'DAU / WAU / MAU',
                        '${_i(rt['dau'])} / ${_i(rt['wau'])} / ${_i(rt['mau'])}',
                      ),
                      _row('ऐप खुला (सेशन)', t['app_opens']),
                      _row('ऐप खुला अब तक', at['app_opens']),
                      _row('स्क्रीन व्यू', t['screen_views']),
                      _row(
                        'फ़ोल्डर / ग्रंथ खुले',
                        '${_i(t['folder_open'])} / ${_i(t['granth_open'])}',
                      ),
                      _row(
                        'PDF डाउनलोड (अब तक ${_i(at['pdf_download'])})',
                        t['pdf_download'],
                      ),
                      _row(
                        'PDF बने (अब तक ${_i(at['pdf_generate'])})',
                        t['pdf_generate'],
                      ),
                      _row(
                        'AI जवाब / फेल',
                        '${_i(t['ai_answer'])} / ${_i(t['ai_fail'])} (${rate.toStringAsFixed(1)}%)',
                      ),
                      _row('Sync फेल', t['sync_fail']),
                      _row(
                        'सपोर्ट खुले / नए',
                        '${_i(sup['open'])} / ${_i(sup['unread'])}',
                      ),
                    ]),
                    _days7('रोज़ के इंस्टॉल', byDay, 'installs'),
                    _days7('रोज़ ऐप खुला', byDay, 'app_opens'),
                    _days7('रोज़ के सक्रिय यूज़र', byDay, 'active_users'),
                    _days7('रोज़ के PDF डाउनलोड', byDay, 'pdf_download'),
                    _list(
                      'ऐप वर्ज़न',
                      _l(d['versions']),
                      'version',
                      'active_users',
                    ),
                    _list('Android वर्ज़न', _l(d['os']), 'os', 'active_users'),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SortChips<String>(
              options: kGaKinds,
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: 10),
            _Load(
              key: ValueKey('top$_kind$_days'),
              load: () => _api.raw(
                'GET',
                '/ga/top',
                query: {'kind': _kind, 'days': '$_days'},
              ),
              builder: (context, d, refresh) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card(const ValueKey('ga-top'), [
                    _title('कुल: ${_i(d['total'])}'),
                    if (d['dims_missing'] == true)
                      _sub(
                        'GA4 में कस्टम डाइमेंशन "${_s(d['param'])}" बनाना बाकी — तब तक सिर्फ़ कुल गिनती। $kGaDimsUrl',
                      ),
                    for (final r in _l(d['items']).take(25))
                      _row(
                        _s(r['label']).isEmpty ? _s(r['id']) : _s(r['label']),
                        r['n'],
                      ),
                  ]),
                  _days7('रोज़ाना', _l(d['by_day']), 'n'),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------- feature switches

/// Labels for the `flags.*` switches the server knows. Unknown server flags still show with their key.
const kFeatureFlagLabels = <String, String>{
  'ai_enabled': 'AI सहायक',
  'analytics_enabled': 'एनालिटिक्स',
  'support_enabled': 'सपोर्ट टिकट',
  'trending_enabled': 'ट्रेंडिंग',
  'daily_enabled': 'आज का प्रमाण',
  'notifications_enabled': 'पुश सूचनाएँ',
  'ai_flags_enabled': 'AI जवाब पर 👎 फ़्लैग',
};

/// All switchable flag keys: the two base flags plus the server's `feature_flags` list.
List<String> featureFlagKeys(Map<String, dynamic> settings) {
  final out = <String>['ai_enabled', 'analytics_enabled'];
  final f = settings['feature_flags'];
  if (f is List) {
    for (final k in f) {
      if (k is String && !out.contains(k)) out.add(k);
    }
  }
  return out;
}

class FeatureFlagsScreen extends StatelessWidget {
  const FeatureFlagsScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'फ़ीचर स्विच',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          load: () => _api.raw('GET', '/settings'),
          builder: (context, s, refresh) => _FlagsForm(s: s, refresh: refresh),
        ),
      ),
    ],
  );
}

class _FlagsForm extends StatefulWidget {
  const _FlagsForm({required this.s, required this.refresh});
  final Map<String, dynamic> s;
  final Future<void> Function() refresh;
  @override
  State<_FlagsForm> createState() => _FlagsFormState();
}

class _FlagsFormState extends State<_FlagsForm> {
  late final Map<String, bool?> _v;

  @override
  void initState() {
    super.initState();
    final f = _m(widget.s['flags']);
    _v = {
      for (final k in featureFlagKeys(widget.s))
        k: f[k] is bool ? f[k] as bool : null,
    };
  }

  Future<void> _save() async {
    // null = not set (removed from config; the user app uses its default)
    await runWrite(
      () => _api.raw('PUT', '/settings', body: {'flags': _v}),
      success: 'ड्राफ्ट में सेव — "प्रकाशित करें" से ऐप में जाएगा',
    );
    await widget.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pub = _m(widget.s['published_flags']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sub('बदलाव ड्राफ्ट में जाता है। "तय नहीं" = ऐप का डिफ़ॉल्ट।'),
        const SizedBox(height: 10),
        for (final k in _v.keys)
          _card(ValueKey('flag-$k'), [
            _title(kFeatureFlagLabels[k] ?? k),
            _sub(
              '$k · प्रकाशित: ${pub[k] is bool ? (pub[k] == true ? 'चालू' : 'बंद') : 'तय नहीं'}',
            ),
            const SizedBox(height: 6),
            SortChips<int>(
              options: [
                (1, 'चालू'),
                (0, 'बंद'),
                if (k != 'ai_enabled' && k != 'analytics_enabled')
                  (-1, 'तय नहीं'),
              ],
              value: _v[k] == null ? -1 : (_v[k]! ? 1 : 0),
              onChanged: (x) => setState(() => _v[k] = x == -1 ? null : x == 1),
            ),
          ]),
        const SizedBox(height: 12),
        SheetButton(
          label: 'ड्राफ्ट में सेव करें',
          primary: true,
          icon: 'check',
          onTap: _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- notifications

const kNotifyTopicLabels = <String, String>{
  'new_praman': 'नया प्रमाण',
  'new_topic': 'नया टॉपिक',
  'trending': 'ट्रेंडिंग',
  'daily': 'आज का प्रमाण',
  'all': 'सभी यूज़र',
};

class NotifyScreen extends StatelessWidget {
  const NotifyScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'सूचना भेजें',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          load: () => _api.raw('GET', '/notify', query: {'limit': '30'}),
          builder: (context, d, refresh) => _NotifyForm(d: d, refresh: refresh),
        ),
      ),
    ],
  );
}

class _NotifyForm extends StatefulWidget {
  const _NotifyForm({required this.d, required this.refresh});
  final Map<String, dynamic> d;
  final Future<void> Function() refresh;
  @override
  State<_NotifyForm> createState() => _NotifyFormState();
}

class _NotifyFormState extends State<_NotifyForm> {
  final _tc = TextEditingController(), _bc = TextEditingController();
  final _link = TextEditingController();
  String _topic = 'all';

  @override
  void dispose() {
    _tc.dispose();
    _bc.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _tc.text.trim(), b = _bc.text.trim();
    if (t.isEmpty || t.length > 80 || b.isEmpty || b.length > 300) {
      showToast('शीर्षक 1–80 और संदेश 1–300 अक्षर हों');
      return;
    }
    if (!await _confirm(
      context,
      '"${kNotifyTopicLabels[_topic] ?? _topic}" पर सूचना भेजें?',
    )) {
      return;
    }
    final link = _link.text.trim();
    await runWrite(
      () => _api.raw(
        'POST',
        '/notify',
        body: {
          'topic': _topic,
          'title': t,
          'body': b,
          if (link.isNotEmpty) 'data': {'link': link},
        },
      ),
      success: 'सूचना भेज दी गई',
    );
    await widget.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final topics = (d['topics'] is List ? d['topics'] as List : const [])
        .whereType<String>()
        .toList();
    if (topics.isNotEmpty && !topics.contains(_topic)) _topic = topics.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d['configured'] == false)
          _card(const ValueKey('notify-off'), [
            _title('FCM अभी सेट नहीं'),
            _sub('सर्वर पर FCM सर्विस-अकाउंट की चाहिए — तब तक भेजना 503 देगा।'),
          ]),
        SortChips<String>(
          options: [for (final t in topics) (t, kNotifyTopicLabels[t] ?? t)],
          value: _topic,
          onChanged: (v) => setState(() => _topic = v),
        ),
        const SizedBox(height: 8),
        AdminField(controller: _tc, label: 'शीर्षक (≤80)'),
        AdminField(controller: _bc, label: 'संदेश (≤300)', maxLines: 3),
        AdminField(controller: _link, label: 'लिंक/डेटा (वैकल्पिक)'),
        const SizedBox(height: 8),
        SheetButton(
          label: 'सूचना भेजें',
          primary: true,
          icon: 'send',
          onTap: _send,
        ),
        const AdminLabel('इतिहास'),
        if (_l(d['items']).isEmpty) _sub('अभी कोई सूचना नहीं भेजी गई'),
        for (final it in _l(d['items']))
          _card(ValueKey('n-${it['id']}'), [
            _title(_s(it['title'])),
            _body(_s(it['body'])),
            _sub(
              '${kNotifyTopicLabels[_s(it['topic'])] ?? it['topic']} · ${_s(it['status'])} · ${_s(it['sent_by'])} · ${_s(it['created_at'])}${_s(it['error']).isEmpty ? '' : ' · ${it['error']}'}',
            ),
          ]),
      ],
    );
  }
}
