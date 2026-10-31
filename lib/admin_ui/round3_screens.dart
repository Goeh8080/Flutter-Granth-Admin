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
        title: 'इवेंट एनालिटिक्स',
        sub: 'फ़ोल्डर/ग्रंथ खुले, PDF, AI जवाब/फेल',
        tone: Tone.saffron,
        onTap: () => _go(const EventsScreen()),
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

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  int _days = 30;

  Widget _top(String title, List<Map<String, dynamic>> rows, String labelKey) =>
      _card(ValueKey(title), [
        _title(title),
        const SizedBox(height: 6),
        if (rows.isEmpty) _sub('अभी कोई डेटा नहीं'),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: _body(
                    _s(r[labelKey]).isEmpty
                        ? _s(r['id'] ?? r['key'])
                        : _s(r[labelKey]),
                  ),
                ),
                Text(
                  '${_i(r['n'])}',
                  style: GText.sans(size: 14, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'इवेंट एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          key: ValueKey(_days),
          load: () =>
              _api.raw('GET', '/stats/events', query: {'days': '$_days'}),
          builder: (context, d, refresh) {
            final t = _m(d['totals']);
            final sup = _m(d['support']), fl = _m(d['ai_flags']);
            final rate =
                (d['ai_fail_rate'] is num ? d['ai_fail_rate'] as num : 0) * 100;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SortChips<int>(
                  options: const [(7, '7 दिन'), (30, '30 दिन'), (90, '90 दिन')],
                  value: _days,
                  onChanged: (v) => setState(() => _days = v),
                ),
                const SizedBox(height: 10),
                _card(const ValueKey('totals'), [
                  _body('फ़ोल्डर खुले: ${_i(t['folder_open'])}'),
                  _body('ग्रंथ खुले: ${_i(t['granth_open'])}'),
                  _body('PDF डाउनलोड: ${_i(t['pdf_download'])}'),
                  _body(
                    'AI जवाब: ${_i(t['ai_answer'])} · फेल: ${_i(t['ai_fail'])} (${rate.toStringAsFixed(1)}%)',
                  ),
                  _body(
                    'सपोर्ट खुले: ${_i(sup['open'])} · नए: ${_i(sup['unread'])}',
                  ),
                  _body('AI फ़्लैग नए: ${_i(fl['new'])}'),
                  if (d['ready'] == false)
                    _sub('सर्वर माइग्रेशन बाकी — अभी डेटा नहीं'),
                ]),
                _top('टॉप फ़ोल्डर', _l(d['top_folders']), 'label'),
                _top('टॉप ग्रंथ', _l(d['top_granths']), 'title'),
                _top('टॉप डाउनलोड', _l(d['top_downloads']), 'title'),
                _card(const ValueKey('fails'), [
                  _title('AI फेल प्रश्न'),
                  if (_l(d['ai_fails']).isEmpty) _sub('कोई नहीं'),
                  for (final f in _l(d['ai_fails']))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _body(
                        '${_s(f['question'])}  ·  ${_s(f['day'])}${_s(f['reason']).isEmpty ? '' : ' · ${f['reason']}'}',
                      ),
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
