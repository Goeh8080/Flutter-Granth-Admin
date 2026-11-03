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
import 'analytics/analytics_home.dart' show AnalyticsCard;
import 'analytics/analytics_kit.dart' show anHBars;

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
  int _sup = 0, _flags = 0, _corr = 0;

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
    try {
      final c = await _api.raw(
        'GET',
        '/ai/flags',
        query: {'kind': 'correction', 'status': 'new', 'limit': '1'},
      );
      if (mounted) setState(() => _corr = _i(c['total']));
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
        key: const ValueKey('r3-corrections'),
        icon: 'check',
        title: 'AI सुधार',
        sub: 'पाठकों के सुधार — स्वीकारें तो AI नोट (सुधार) बनता है',
        badge: _corr,
        tone: Tone.saffron,
        onTap: () => _go(const AiCorrectionsScreen()),
      ),
      AdminTile(
        key: const ValueKey('r3-highlights'),
        icon: 'sparkles',
        title: 'ट्रेंडिंग / आज का प्रमाण',
        sub: 'config में जाता है — ड्राफ्ट, फिर प्रकाशित करें',
        tone: Tone.saffron,
        onTap: () => _go(const HighlightsScreen()),
      ),
      const AnalyticsCard(),
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

// ---------------------------------------------------------------------------- AI corrections (Round 7)

/// Server limits for an approved correction (= `/ai/knowledge` answer limits).
const kCorrectionMin = 50, kCorrectionMax = 2000;

/// Pending user corrections (`GET /ai/flags?kind=correction`). Approve → visible knowledge item tagged सुधार
/// (`POST /ai/flags/{id}/approve {answer}`); Reject → `POST /ai/flags/{id}/reject`.
class AiCorrectionsScreen extends StatefulWidget {
  const AiCorrectionsScreen({super.key});
  @override
  State<AiCorrectionsScreen> createState() => _AiCorrectionsScreenState();
}

class _AiCorrectionsScreenState extends State<AiCorrectionsScreen> {
  String _st = 'new';

  Future<String?> _editAnswer(String initial) => showDialog<String>(
    context: context,
    builder: (c) => CorrectionApproveDialog(initial: initial),
  );

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'AI सुधार',
    slivers: [
      SliverToBoxAdapter(
        child: _Load(
          key: ValueKey('corr$_st'),
          load: () => _api.raw(
            'GET',
            '/ai/flags',
            query: {'kind': 'correction', 'status': _st, 'limit': '100'},
          ),
          builder: (context, d, refresh) {
            final items = _l(d['items']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sub(
                  'स्वीकारने पर सुधार "AI Key Notes" में (टैग: सुधार) जाता है और AI उसे इस्तेमाल करता है।',
                ),
                const SizedBox(height: 8),
                SortChips<String>(
                  options: const [
                    ('new', 'लंबित'),
                    ('reviewed', 'निपटाए'),
                    ('all', 'सब'),
                  ],
                  value: _st,
                  onChanged: (v) => setState(() => _st = v),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty) const EmptyState(title: 'कोई सुधार नहीं'),
                for (final f in items)
                  _card(ValueKey('corr-${f['id']}'), [
                    _sub('प्रश्न'),
                    _title(_s(f['question'])),
                    const SizedBox(height: 6),
                    _sub('पुराना AI जवाब'),
                    _body(_s(f['answer'])),
                    const SizedBox(height: 6),
                    _sub('सुधार'),
                    _body(_s(f['correction'])),
                    const SizedBox(height: 4),
                    _sub(
                      [
                        shortTs(_s(f['created_at'])),
                        _s(f['lang']),
                        if (_s(f['app_version']).isNotEmpty)
                          'ऐप ${f['app_version']}',
                        if (f['resolution'] == 'approved')
                          'स्वीकृत · नोट #${_i(f['knowledge_id'])}',
                        if (f['resolution'] == 'rejected') 'अस्वीकृत',
                        if (_s(f['reviewed_by']).isNotEmpty)
                          _s(f['reviewed_by']),
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    if (f['resolution'] == null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          Pill(
                            key: ValueKey('corr-approve-${f['id']}'),
                            label: 'स्वीकारें',
                            tone: PillTone.maroon,
                            onTap: () async {
                              final a = await _editAnswer(_s(f['correction']));
                              if (a == null) return;
                              if (await runWrite(
                                () => _api.raw(
                                  'POST',
                                  '/ai/flags/${f['id']}/approve',
                                  body: {'answer': a},
                                ),
                                success: 'स्वीकारा — AI नोट बना',
                              )) {
                                refresh();
                              }
                            },
                          ),
                          Pill(
                            key: ValueKey('corr-reject-${f['id']}'),
                            label: 'अस्वीकारें',
                            onTap: () async {
                              if (!await _confirm(context, 'सुधार अस्वीकारें?'))
                                return;
                              if (await runWrite(
                                () => _api.raw(
                                  'POST',
                                  '/ai/flags/${f['id']}/reject',
                                ),
                                success: 'अस्वीकारा',
                              )) {
                                refresh();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ]),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class CorrectionApproveDialog extends StatefulWidget {
  const CorrectionApproveDialog({super.key, required this.initial});
  final String initial;
  @override
  State<CorrectionApproveDialog> createState() =>
      CorrectionApproveDialogState();
}

class CorrectionApproveDialogState extends State<CorrectionApproveDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _c.text.trim().runes.length;
    final ok = n >= kCorrectionMin && n <= kCorrectionMax;
    return AlertDialog(
      title: const Text('सुधार स्वीकारें'),
      content: TextField(
        key: const ValueKey('corr-answer'),
        controller: _c,
        maxLines: 6,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          helperText:
              'AI नोट का जवाब ($kCorrectionMin–$kCorrectionMax अक्षर) · अभी $n',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('रद्द करें'),
        ),
        TextButton(
          key: const ValueKey('corr-approve-ok'),
          onPressed: ok ? () => Navigator.pop(context, _c.text.trim()) : null,
          child: const Text('स्वीकारें'),
        ),
      ],
    );
  }
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
      _PramanPicker(
        id: _pid.text.trim(),
        onPick: (id) => setState(() => _pid.text = id),
      ),
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

/// Round-3 (#6): the daily/trending प्रमाण is picked from the app's content by name (with its
/// ग्रंथ), never typed as an id. The stored value stays the praman id (contract unchanged).
class _PramanPicker extends StatelessWidget {
  const _PramanPicker({required this.id, required this.onPick});
  final String id;
  final ValueChanged<String> onPick;

  static String granthOf(dynamic p) {
    final t = '${p.granthTitle}'.trim();
    if (t.isNotEmpty) return t;
    for (final g in AdminData.I.granths) {
      if (g.id == p.granthId) return g.title;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    dynamic cur;
    for (final p in AdminData.I.pramans) {
      if (p.id == id) cur = p;
    }
    final title = id.isEmpty
        ? 'प्रमाण चुनें…'
        : cur == null
        ? 'प्रमाण #$id (सूची में नहीं मिला)'
        : (cur.title as String).trim().isEmpty
        ? 'प्रमाण #$id'
        : cur.title as String;
    final g = cur == null ? '' : granthOf(cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        key: const ValueKey('praman-picker'),
        onTap: () async {
          final r = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const _PramanSearchSheet(),
          );
          if (r != null) onPick(r);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GColors.gold.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const GIcon('search', size: 18, color: GColors.maroon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GText.sans(size: 14, weight: FontWeight.w600),
                    ),
                    if (g.isNotEmpty)
                      Text(
                        'ग्रंथ: $g',
                        style: GText.sans(size: 12, color: GColors.muted),
                      ),
                  ],
                ),
              ),
              if (id.isNotEmpty)
                IconButton(
                  tooltip: 'हटाएँ',
                  onPressed: () => onPick(''),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PramanSearchSheet extends StatefulWidget {
  const _PramanSearchSheet();
  @override
  State<_PramanSearchSheet> createState() => _PramanSearchSheetState();
}

class _PramanSearchSheetState extends State<_PramanSearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final all = AdminData.I.pramans;
    final hits = [
      for (final p in all)
        if (q.isEmpty ||
            p.title.toLowerCase().contains(q) ||
            p.id == q ||
            _PramanPicker.granthOf(p).toLowerCase().contains(q))
          p,
    ].take(200).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const ValueKey('praman-search'),
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'प्रमाण या ग्रंथ का नाम खोजें',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: hits.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty ? 'प्रमाण लोड नहीं हुए' : 'कुछ नहीं मिला',
                          style: GText.sans(size: 14, color: GColors.muted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: hits.length,
                        itemBuilder: (_, i) {
                          final p = hits[i];
                          final g = _PramanPicker.granthOf(p);
                          return ListTile(
                            title: Text(
                              p.title.trim().isEmpty
                                  ? 'प्रमाण #${p.id}'
                                  : p.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              g.isEmpty ? '#${p.id}' : '$g · #${p.id}',
                            ),
                            onTap: () => Navigator.pop(context, p.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- analytics

/// Round 6: GA reads never fail the screen. On any error (e.g. 503 ga_not_configured)
/// returns an empty map with `_ga_error` set, so the UI renders zeros plus a notice.
Future<Map<String, dynamic>> gaSafe(
  PanelApi api,
  String path, {
  Map<String, String>? query,
}) async {
  try {
    return await api.raw('GET', path, query: query);
  } catch (e) {
    return {'_ga_error': gaErrorText(e)};
  }
}

String gaErrorText(Object e) => e is PanelApiException
    ? 'GA उपलब्ध नहीं (${e.code}${e.status == null ? '' : ' · ${e.status}'}) — शून्य दिखाए गए हैं'
    : 'GA उपलब्ध नहीं — शून्य दिखाए गए हैं';

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
/// Round-2: folder sections with charts (fl_chart) like the old design.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

String _dur(Object? s) {
  final n = _i(s);
  if (n < 60) return '$n से.';
  final h = n ~/ 3600, m = (n % 3600) ~/ 60;
  return h > 0 ? '$h घं. $m मि.' : '$m मि.';
}

Widget _tile(String label, String value, {Color color = GColors.maroon}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: GColors.pill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GColors.creamDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GText.sans(
                size: 20,
                weight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GText.sans(size: 11.5, color: GColors.muted, height: 1.25),
          ),
        ],
      ),
    );

Widget _tiles(List<(String, String, Color)> items) => LayoutBuilder(
  builder: (context, c) {
    final cols = c.maxWidth > 520 ? 4 : (c.maxWidth > 340 ? 3 : 2);
    final w = (c.maxWidth - (cols - 1) * 8) / cols;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          SizedBox(
            width: w,
            child: _tile(it.$1, it.$2, color: it.$3),
          ),
      ],
    );
  },
);

/// One line (or bar) chart of `key` over `by_day` rows (`day`: yyyy-mm-dd).
Widget _dayChart(
  List<Map<String, dynamic>> rows,
  String key, {
  Color color = GColors.saffron,
  bool bars = false,
  double Function(num v)? map,
}) {
  // Round-3: horizontal bars, one row per day (newest first), exact counts.
  final items = <(String, num)>[
    for (final r in rows.reversed)
      if ((map == null ? _i(r[key]) : map(r[key] is num ? r[key] as num : 0)) >
          0)
        (
          () {
            final d = _s(r['day'] ?? r['date']);
            return d.length >= 10 ? d.substring(5) : d;
          }(),
          map == null ? _i(r[key]) : map(r[key] is num ? r[key] as num : 0),
        ),
  ];
  return anHBars(items, color: color, empty: 'इस अवधि में अभी कोई डेटा नहीं');
}

/// Horizontal bars for a ranked list (label, n).
Widget _rankBars(
  List<(String, num)> items, {
  Color color = GColors.maroon,
  int take = 10,
}) {
  if (items.isEmpty) return _sub('अभी कोई डेटा नहीं');
  final list = items.take(take).toList();
  final maxN = list.fold<num>(0, (a, b) => b.$2 > a ? b.$2 : a);
  return Column(
    children: [
      for (final it in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      it.$1.isEmpty ? '(खाली)' : it.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GText.sans(size: 12.5),
                    ),
                  ),
                  Text(
                    '${_i(it.$2)}',
                    style: GText.sans(size: 12.5, weight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: maxN <= 0 ? 0 : it.$2 / maxN,
                  minHeight: 7,
                  color: color,
                  backgroundColor: GColors.meterTrack,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Donut with legend.
Widget _donut(List<(String, num)> parts) {
  // Round-3: shares shown as horizontal bars (name + count + %), no pie.
  final total = parts.fold<num>(0, (a, b) => a + b.$2);
  if (total <= 0) return _sub('अभी कोई डेटा नहीं');
  final sorted = [...parts]..sort((a, b) => b.$2.compareTo(a.$2));
  return anHBars([
    for (final p in sorted)
      ('${p.$1} (${(p.$2 * 100 / total).round()}%)', p.$2),
  ]);
}

/// A collapsible "folder" section.
Widget _folder(
  String key,
  String icon,
  String title,
  List<Widget> children, {
  bool open = false,
  String? badge,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: GCard(
    key: ValueKey('fold-$key'),
    child: Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: open,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        leading: Text(icon, style: const TextStyle(fontSize: 22)),
        title: Text(
          title,
          style: GText.sans(
            size: 15.5,
            weight: FontWeight.w800,
            color: GColors.maroon,
          ),
        ),
        trailing: badge == null
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GColors.pillMaroon,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: GText.sans(
                    size: 12,
                    weight: FontWeight.w800,
                    color: GColors.maroon,
                  ),
                ),
              ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  ),
);

Widget _chartTitle(String t) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 6),
  child: Text(t, style: GText.sans(size: 13, weight: FontWeight.w800)),
);

class _EventsScreenState extends State<EventsScreen> {
  int _days = 30;
  String _kind = 'granths';

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'एनालिटिक्स (GA4)',
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------------------------------------------------------------- live + today
            _Load(
              key: const ValueKey('ga-live'),
              load: () => gaSafe(_api, '/ga/live'),
              builder: (context, d, refresh) {
                final rtm = _m(d['realtime']), td = _m(d['today']);
                final mins = _l(rtm['by_minute']);
                final aiQ = _i(td['ai_ask']) > 0
                    ? _i(td['ai_ask'])
                    : _i(td['ai_answer']) + _i(td['ai_fail']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d['_ga_error'] != null)
                      _card(const ValueKey('ga-err'), [
                        _sub(_s(d['_ga_error'])),
                      ]),
                    _folder(
                      'live',
                      '🟢',
                      'लाइव यूज़र',
                      [
                        _tiles([
                          (
                            'अभी ऑनलाइन (30 मि.)',
                            '${_i(d['live_users'])}',
                            GColors.online,
                          ),
                          (
                            'ऑफ़लाइन यूज़र',
                            '${_i(d['offline_users'])}',
                            GColors.muted,
                          ),
                          (
                            'कुल यूज़र (अब तक)',
                            '${_i(d['total_users'])}',
                            GColors.maroon,
                          ),
                          (
                            'कुल रनटाइम (अब तक)',
                            _dur(d['total_engagement_s']),
                            GColors.saffronDark,
                          ),
                        ]),
                        _chartTitle('पिछले 30 मिनट — हर मिनट सक्रिय यूज़र'),
                        _dayChart(
                          [
                            for (final m in mins)
                              {
                                'day': '-${_i(m['minutes_ago'])}m',
                                'n': m['active_users'],
                              },
                          ],
                          'n',
                          color: GColors.online,
                          bars: true,
                        ),
                        _chartTitle('पिछले 30 मिनट के इवेंट'),
                        _rankBars(
                          [
                            for (final e in _l(rtm['events']))
                              (_s(e['event']), _i(e['n'])),
                          ],
                          color: GColors.online,
                          take: 12,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: refresh,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('रीफ़्रेश'),
                          ),
                        ),
                      ],
                      open: true,
                      badge: '${_i(d['live_users'])} ऑनलाइन',
                    ),
                    _folder('today', '📅', 'आज', [
                      _tiles([
                        (
                          'आज सक्रिय यूज़र',
                          '${_i(td['active_users'])}',
                          GColors.maroon,
                        ),
                        (
                          'आज नए यूज़र',
                          '${_i(td['new_users'])}',
                          GColors.online,
                        ),
                        (
                          'आज ऐप खुला',
                          '${_i(td['app_opens'])}',
                          GColors.saffron,
                        ),
                        (
                          'आज के इंस्टॉल',
                          '${_i(td['installs'])}',
                          GColors.gold,
                        ),
                        (
                          'आज PDF बने',
                          '${_i(td['pdf_generate'])}',
                          GColors.maroon,
                        ),
                        (
                          'आज PDF डाउनलोड',
                          '${_i(td['pdf_download'])}',
                          GColors.saffronDark,
                        ),
                        ('आज AI प्रश्न', '$aiQ', GColors.brown),
                        (
                          'AI जवाब / फेल',
                          '${_i(td['ai_answer'])} / ${_i(td['ai_fail'])}',
                          GColors.maroonLight,
                        ),
                        (
                          'Sync सफल / फेल',
                          '${_i(td['sync_ok'])} / ${_i(td['sync_fail'])}',
                          GColors.muted,
                        ),
                        (
                          'आज स्क्रीन व्यू',
                          '${_i(td['screen_views'])}',
                          GColors.saffron,
                        ),
                        (
                          'ग्रंथ / प्रमाण खुले',
                          '${_i(td['granth_open'])} / ${_i(td['praman_open'])}',
                          GColors.gold,
                        ),
                        (
                          'आज रनटाइम',
                          _dur(td['engagement_s']),
                          GColors.saffronDark,
                        ),
                      ]),
                      const SizedBox(height: 6),
                      _sub(
                        'आज के आँकड़े: GA रिपोर्ट या पिछले 30 मिनट का रियलटाइम, जो बड़ा हो।',
                      ),
                    ], open: true),
                  ],
                );
              },
            ),
            // ---------------------------------------------------------------- period
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
                  gaSafe(_api, '/ga/overview', query: {'days': '$_days'}),
                  gaSafe(_api, '/support/unread'),
                ]);
                return {...r[0], 'support': r[1]};
              },
              builder: (context, d, refresh) {
                final t = _m(d['totals']), at = _m(d['all_time']);
                final rt = _m(d['retention']), sup = _m(d['support']);
                final byDay = _l(d['by_day']);
                final aiQ = _i(t['ai_ask']) > 0
                    ? _i(t['ai_ask'])
                    : _i(t['ai_answer']) + _i(t['ai_fail']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d['_ga_error'] != null)
                      _card(const ValueKey('ga-err2'), [
                        _sub(_s(d['_ga_error'])),
                      ]),
                    _folder('users', '👥', 'यूज़र ($_days दिन)', [
                      _tiles([
                        (
                          'सक्रिय यूज़र',
                          '${_i(t['active_users'])}',
                          GColors.maroon,
                        ),
                        ('नए यूज़र', '${_i(t['new_users'])}', GColors.online),
                        (
                          'इंस्टॉल (अवधि)',
                          '${_i(t['installs'])}',
                          GColors.gold,
                        ),
                        (
                          'इंस्टॉल अब तक',
                          '${_i(at['installs'])}',
                          GColors.saffronDark,
                        ),
                        (
                          'DAU / WAU / MAU',
                          '${_i(rt['dau'])}/${_i(rt['wau'])}/${_i(rt['mau'])}',
                          GColors.brown,
                        ),
                        (
                          'कुल रनटाइम',
                          _dur(t['engagement_s']),
                          GColors.saffron,
                        ),
                        (
                          'औसत समय / यूज़र',
                          _dur(t['avg_engagement_s_per_user']),
                          GColors.muted,
                        ),
                        ('सेशन', '${_i(t['sessions'])}', GColors.maroonLight),
                      ]),
                      _chartTitle('रोज़ के सक्रिय यूज़र'),
                      _dayChart(byDay, 'active_users', color: GColors.maroon),
                      _chartTitle('रोज़ के इंस्टॉल'),
                      _dayChart(
                        byDay,
                        'installs',
                        color: GColors.gold,
                        bars: true,
                      ),
                      _chartTitle('रोज़ का रनटाइम (मिनट)'),
                      _dayChart(
                        byDay,
                        'engagement_s',
                        color: GColors.saffronDark,
                        bars: true,
                        map: (v) => v / 60,
                      ),
                    ], open: true),
                    _folder('opens', '📱', 'ऐप खुलना', [
                      _tiles([
                        (
                          'ऐप खुला (सेशन)',
                          '${_i(t['app_opens'])}',
                          GColors.saffron,
                        ),
                        (
                          'ऐप खुला अब तक',
                          '${_i(at['app_opens'])}',
                          GColors.maroon,
                        ),
                        (
                          'स्क्रीन व्यू',
                          '${_i(t['screen_views'])}',
                          GColors.gold,
                        ),
                      ]),
                      _chartTitle('रोज़ ऐप खुला'),
                      _dayChart(byDay, 'app_opens', color: GColors.saffron),
                      _chartTitle('सबसे ज़्यादा देखी स्क्रीन'),
                      _rankBars([
                        for (final s in _l(d['screens']))
                          (_s(s['screen']), _i(s['views'])),
                      ]),
                    ]),
                    _folder('pdf', '📄', 'PDF', [
                      _tiles([
                        ('PDF बने', '${_i(t['pdf_generate'])}', GColors.maroon),
                        (
                          'PDF बने अब तक',
                          '${_i(at['pdf_generate'])}',
                          GColors.brown,
                        ),
                        (
                          'PDF डाउनलोड',
                          '${_i(t['pdf_download'])}',
                          GColors.saffron,
                        ),
                        (
                          'डाउनलोड अब तक',
                          '${_i(at['pdf_download'])}',
                          GColors.saffronDark,
                        ),
                        (
                          'PDF फेल',
                          '${_i(t['pdf_fail'])}',
                          GColors.maroonLight,
                        ),
                      ]),
                      _chartTitle('रोज़ PDF बने'),
                      _dayChart(
                        byDay,
                        'pdf_generate',
                        color: GColors.maroon,
                        bars: true,
                      ),
                      _chartTitle('रोज़ PDF डाउनलोड'),
                      _dayChart(
                        byDay,
                        'pdf_download',
                        color: GColors.saffron,
                        bars: true,
                      ),
                    ]),
                    _folder('ai', '✨', 'AI प्रश्न', [
                      _tiles([
                        ('AI प्रश्न', '$aiQ', GColors.brown),
                        ('जवाब मिले', '${_i(t['ai_answer'])}', GColors.online),
                        ('फेल', '${_i(t['ai_fail'])}', GColors.maroonLight),
                        (
                          'फेल दर',
                          '${((t['ai_fail_rate'] is num ? t['ai_fail_rate'] as num : 0) * 100).toStringAsFixed(1)}%',
                          GColors.muted,
                        ),
                      ]),
                      _chartTitle('जवाब बनाम फेल'),
                      _donut([
                        ('जवाब मिले', _i(t['ai_answer'])),
                        ('फेल', _i(t['ai_fail'])),
                      ]),
                      _chartTitle('रोज़ AI प्रश्न'),
                      _dayChart(
                        byDay,
                        _i(t['ai_ask']) > 0 ? 'ai_ask' : 'ai_answer',
                        color: GColors.brown,
                      ),
                    ]),
                    _folder('content', '📚', 'ग्रंथ / प्रमाण / फ़ोल्डर', [
                      _donut([
                        ('फ़ोल्डर खुले', _i(t['folder_open'])),
                        ('ग्रंथ खुले', _i(t['granth_open'])),
                        ('प्रमाण खुले', _i(t['praman_open'])),
                        ('विषय खुले', _i(t['topic_open'])),
                        ('संदर्भ टैप', _i(t['cite_tap'])),
                      ]),
                      _chartTitle('रोज़ ग्रंथ खुले'),
                      _dayChart(byDay, 'granth_open', color: GColors.gold),
                    ]),
                    _folder('sync', '🔄', 'Sync और सपोर्ट', [
                      _tiles([
                        ('Sync सफल', '${_i(t['sync_ok'])}', GColors.online),
                        (
                          'Sync फेल',
                          '${_i(t['sync_fail'])}',
                          GColors.maroonLight,
                        ),
                        ('सपोर्ट खुले', '${_i(sup['open'])}', GColors.saffron),
                        ('सपोर्ट नए', '${_i(sup['unread'])}', GColors.maroon),
                      ]),
                      _chartTitle('रोज़ Sync फेल'),
                      _dayChart(
                        byDay,
                        'sync_fail',
                        color: GColors.maroonLight,
                        bars: true,
                      ),
                    ]),
                    _folder('devices', '🔧', 'वर्ज़न और डिवाइस', [
                      _chartTitle('ऐप वर्ज़न (सक्रिय यूज़र)'),
                      _rankBars([
                        for (final v in _l(d['versions']))
                          (_s(v['version']), _i(v['active_users'])),
                      ], color: GColors.saffron),
                      _chartTitle('Android वर्ज़न'),
                      _rankBars([
                        for (final v in _l(d['os']))
                          (_s(v['os']), _i(v['active_users'])),
                      ], color: GColors.gold),
                      _chartTitle('डिवाइस'),
                      _rankBars([
                        for (final v in _l(d['devices']))
                          (_s(v['model']), _i(v['active_users'])),
                      ], color: GColors.brown),
                    ]),
                  ],
                );
              },
            ),
            // ---------------------------------------------------------------- top items
            const SizedBox(height: 4),
            SortChips<String>(
              options: kGaKinds,
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: 10),
            _Load(
              key: ValueKey('top$_kind$_days'),
              load: () => gaSafe(
                _api,
                '/ga/top',
                query: {'kind': _kind, 'days': '$_days'},
              ),
              builder: (context, d, refresh) => _folder(
                'top',
                '🏆',
                'टॉप: ${kGaKinds.firstWhere((k) => k.$1 == _kind, orElse: () => (_kind, _kind)).$2}',
                [
                  _tiles([('कुल', '${_i(d['total'])}', GColors.maroon)]),
                  if (d['_ga_error'] != null) _sub(_s(d['_ga_error'])),
                  if (d['dims_missing'] == true)
                    _sub(
                      'GA4 में कस्टम डाइमेंशन "${_s(d['param'])}" बनाना बाकी — तब तक सिर्फ़ कुल गिनती। $kGaDimsUrl',
                    ),
                  _chartTitle('सबसे ज़्यादा'),
                  _rankBars([
                    for (final r in _l(d['items']))
                      (
                        _s(r['label']).isEmpty ? _s(r['id']) : _s(r['label']),
                        _i(r['n']),
                      ),
                  ], take: 25),
                  _chartTitle('रोज़ाना'),
                  _dayChart(
                    _l(d['by_day']),
                    'n',
                    color: GColors.saffron,
                    bars: true,
                  ),
                ],
                open: true,
                badge: '${_i(d['total'])}',
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
  'bhakt_id_enabled': 'भक्त ID (डिफ़ॉल्ट बंद)',
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
