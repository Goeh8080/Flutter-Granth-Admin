import 'package:flutter/material.dart';

import '../admin/models/ai_models.dart';
import '../admin/screens/panel/panel_widgets.dart' show shortTs;
import '../admin/services/panel_api.dart';
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../admin/widgets/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import 'admin_actions.dart' show AdminPill, SortChips;
import 'admin_data.dart';
import 'admin_kit.dart';
import 'admin_widgets.dart';

PanelApi get _api => AdminData.I.app.panel.api;

/// Parses "a, b ,c" into at most 10 tags of at most 30 chars (CONTRACT §4.3 limits).
List<String> parseTags(String raw) {
  final out = <String>[];
  for (final t in raw.split(RegExp(r'[,،\n]'))) {
    final s = t.trim();
    if (s.isEmpty || out.contains(s)) continue;
    out.add(s.length > 30 ? s.substring(0, 30) : s);
    if (out.length == 10) break;
  }
  return out;
}

/// Client-side check mirroring the server (question 5..500, answer 50..2000). Null = ok.
String? validateKnowledge(
  String q,
  String a, {
  int qMin = 5,
  int qMax = 500,
  int aMin = 50,
  int aMax = 2000,
}) {
  final ql = q.trim().runes.length, al = a.trim().runes.length;
  if (ql < qMin || ql > qMax) return 'सवाल $qMin–$qMax अक्षर का हो (अभी $ql)';
  if (al < aMin || al > aMax) return 'जवाब $aMin–$aMax अक्षर का हो (अभी $al)';
  return null;
}

class _Load<T> extends StatefulWidget {
  const _Load({required this.load, required this.builder, super.key});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  @override
  State<_Load<T>> createState() => _LoadState<T>();
}

class _LoadState<T> extends State<_Load<T>> {
  T? _v;
  Object? _err;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    if (mounted) setState(() => _busy = _v == null);
    try {
      final v = await widget.load();
      if (mounted)
        setState(() {
          _v = v;
          _err = null;
          _busy = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _err = e;
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_v != null) return widget.builder(context, _v as T, _go);
    if (_busy) return const EmptyState(title: 'लोड हो रहा है…', spinner: true);
    return EmptyState(
      title: 'लोड नहीं हो सका',
      body: '$_err',
      actionLabel: 'फिर कोशिश करें',
      onAction: _go,
    );
  }
}

// ---------------------------------------------------------------------------- key points

class AiKnowledgeScreen extends StatefulWidget {
  const AiKnowledgeScreen({super.key});
  @override
  State<AiKnowledgeScreen> createState() => _AiKnowledgeScreenState();
}

class _AiKnowledgeScreenState extends State<AiKnowledgeScreen> {
  int _rev = 0;
  void _reload() => setState(() => _rev++);

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'AI Key Points',
    trailing: Pill(
      icon: 'plus',
      label: 'नया',
      tone: PillTone.maroon,
      onTap: () async {
        if (await showKnowledgeEditor(context)) _reload();
      },
    ),
    slivers: [
      SliverToBoxAdapter(
        child: _Load<AiKnowledgeList>(
          key: ValueKey(_rev),
          load: () => _api.aiKnowledge(limit: 200),
          builder: (context, list, refresh) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GCard(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '"अगर सवाल यह हो, तो जवाब यह" — यहाँ जोड़ा गया हर बिंदु तुरंत लाइव होता है (प्रकाशित करने की ज़रूरत नहीं)। ${list.total}/${list.maxItems} बिंदु।',
                  style: GText.sans(
                    size: 13,
                    color: GColors.muted,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (list.items.isEmpty)
                const EmptyState(
                  title: 'अभी कोई key point नहीं',
                  body: 'ऊपर "नया" दबाकर जोड़ें।',
                ),
              for (final k in list.items) _KbCard(k, onChanged: refresh),
            ],
          ),
        ),
      ),
    ],
  );
}

class _KbCard extends StatelessWidget {
  const _KbCard(this.k, {required this.onChanged});
  final AiKnowledge k;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: RepaintBoundary(
      child: Opacity(
        opacity: k.visible ? 1 : 0.6,
        child: GCard(
          key: ValueKey('kb-${k.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'प्र. ${k.question}',
                style: GText.sans(
                  size: 15,
                  weight: FontWeight.w800,
                  color: GColors.maroon,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'उ. ${k.answer}',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: GText.sans(size: 14, height: 1.45),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in k.tags)
                    Pill(label: '#$t', tone: PillTone.topic),
                  if (!k.visible) const Pill(icon: 'eye-off', label: 'छिपा'),
                  AdminPill(
                    label: 'संपादित',
                    icon: 'pen-line',
                    onTap: () async {
                      if (await showKnowledgeEditor(context, item: k))
                        await onChanged();
                    },
                  ),
                  AdminPill(
                    label: k.visible ? 'छिपाएँ' : 'दिखाएँ',
                    icon: k.visible ? 'eye-off' : 'eye',
                    onTap: () async {
                      if (await runWrite(
                        () => _api.aiKnowledgeUpdate(k.id, visible: !k.visible),
                        success: k.visible ? 'छिपाया' : 'दिखाया',
                      ))
                        await onChanged();
                    },
                  ),
                  AdminPill(
                    label: 'हटाएँ',
                    icon: 'trash-2',
                    danger: true,
                    onTap: () async {
                      final yes = await confirmPopTitled(
                        context,
                        title: 'यह key point हटाएँ?',
                        message: k.question,
                        confirm: 'हटाएँ',
                        destructive: true,
                      );
                      if (yes &&
                          await runWrite(
                            () => _api.aiKnowledgeDelete(k.id),
                            success: 'हटाया गया',
                          ))
                        await onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Create (item == null) or edit a key point. Returns true if something was saved.
Future<bool> showKnowledgeEditor(
  BuildContext context, {
  AiKnowledge? item,
  String question = '',
  String answer = '',
}) async {
  final r = await showPop<bool>(
    context,
    (_) => _KbSheet(item: item, question: question, answer: answer),
  );
  return r ?? false;
}

class _KbSheet extends StatefulWidget {
  const _KbSheet({this.item, this.question = '', this.answer = ''});
  final AiKnowledge? item;
  final String question, answer;
  @override
  State<_KbSheet> createState() => _KbSheetState();
}

class _KbSheetState extends State<_KbSheet> {
  late final _q = TextEditingController(
    text: widget.item?.question ?? widget.question,
  );
  late final _a = TextEditingController(
    text: widget.item?.answer ?? widget.answer,
  );
  late final _t = TextEditingController(
    text: (widget.item?.tags ?? const []).join(', '),
  );
  late bool _visible = widget.item?.visible ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    _t.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = validateKnowledge(_q.text, _a.text);
    if (err != null) return showToast(err, error: true);
    setState(() => _busy = true);
    final tags = parseTags(_t.text);
    final it = widget.item;
    final ok = await runWrite(() async {
      if (it == null) {
        await _api.aiKnowledgeCreate(
          question: _q.text.trim(),
          answer: _a.text.trim(),
          tags: tags,
          visible: _visible,
        );
      } else {
        await _api.aiKnowledgeUpdate(
          it.id,
          question: _q.text.trim(),
          answer: _a.text.trim(),
          tags: tags,
          visible: _visible,
        );
      }
    }, success: 'सहेजा गया — तुरंत लाइव');
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetCard(
    children: [
      SheetHead(
        title: widget.item == null ? 'नया key point' : 'key point संपादित',
        onBack: () => Navigator.pop(context, false),
      ),
      AdminField(
        controller: _q,
        label: 'अगर सवाल यह हो… (5–500)',
        maxLines: 3,
        counter: '${_q.text.trim().runes.length}',
        onChanged: (_) => setState(() {}),
      ),
      AdminField(
        controller: _a,
        label: 'तो जवाब यह है… (50–2000)',
        maxLines: 8,
        counter: '${_a.text.trim().runes.length}',
        onChanged: (_) => setState(() {}),
      ),
      AdminField(
        controller: _t,
        label: 'टैग (अल्पविराम से, अधिकतम 10)',
        hint: 'व्रत, पूजा',
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              'पाठकों के लिए दिखे',
              style: GText.sans(
                size: 15,
                weight: FontWeight.w800,
                color: GColors.maroon,
              ),
            ),
          ),
          AdminSwitch(
            value: _visible,
            onChanged: (v) => setState(() => _visible = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SheetButton(
        label: 'सहेजें',
        primary: true,
        enabled: !_busy,
        onTap: _save,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------- question inbox

enum QStatus { all, newQ, answered, rejected }

class AiQuestionsScreen extends StatefulWidget {
  const AiQuestionsScreen({super.key});
  @override
  State<AiQuestionsScreen> createState() => _AiQuestionsScreenState();
}

class _AiQuestionsScreenState extends State<AiQuestionsScreen> {
  QStatus _st = QStatus.newQ;
  int _rev = 0;
  void _reload() => setState(() => _rev++);

  static String _wire(QStatus s) => switch (s) {
    QStatus.all => 'all',
    QStatus.newQ => 'new',
    QStatus.answered => 'answered',
    QStatus.rejected => 'rejected',
  };

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'यूज़र के सवाल',
    trailing: Pill(
      label: 'सब पढ़ा',
      onTap: () async {
        if (await runWrite(
          () => _api.aiQuestionsMarkRead(),
          success: 'सब पढ़ा हुआ चिह्नित',
        ))
          _reload();
      },
    ),
    slivers: [
      SliverToBoxAdapter(
        child: _Load<AiQuestionList>(
          key: ValueKey('$_rev-${_st.name}'),
          load: () => _api.aiQuestions(status: _wire(_st), limit: 100),
          builder: (context, list, refresh) {
            final c = list.counts;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SortChips<QStatus>(
                  options: [
                    (QStatus.newQ, 'नए ${c.newCount}'),
                    (QStatus.answered, 'जवाब दिए ${c.answered}'),
                    (QStatus.rejected, 'अस्वीकृत ${c.rejected}'),
                    (QStatus.all, 'सब ${c.total}'),
                  ],
                  value: _st,
                  onChanged: (v) => setState(() => _st = v),
                ),
                const SizedBox(height: 10),
                if (list.items.isEmpty)
                  const EmptyState(
                    title: 'कोई सवाल नहीं',
                    body: 'पाठकों के भेजे सवाल यहाँ दिखेंगे।',
                  ),
                for (final q in list.items) _QCard(q, onChanged: refresh),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _QCard extends StatelessWidget {
  const _QCard(this.q, {required this.onChanged});
  final AiQuestion q;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = q.isAnswered
        ? ('जवाब दिया', PillTone.maroon)
        : q.isRejected
        ? ('अस्वीकृत', PillTone.plain)
        : ('नया', PillTone.topic);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RepaintBoundary(
        child: GCard(
          key: ValueKey('q-${q.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!q.read && q.isNew)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: GColors.saffron,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      q.question,
                      style: GText.sans(
                        size: 15,
                        weight: FontWeight.w800,
                        color: GColors.maroon,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (q.who.isNotEmpty) 'पूछने वाला #${q.who}',
                  if (q.createdAt.isNotEmpty) shortTs(q.createdAt),
                  if (q.context.isNotEmpty) q.context,
                ].join(' · '),
                style: GText.sans(size: 12, color: GColors.muted),
              ),
              if (q.isAnswered && q.answer.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  q.answer,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: GText.sans(size: 14, height: 1.45),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(label: label, tone: tone),
                  if (q.verified) const Pill(icon: 'shield', label: 'verified'),
                  if (q.isAnswered)
                    Pill(
                      label: q.seenByUser ? 'पाठक ने देखा' : 'अभी नहीं देखा',
                    ),
                  AdminPill(
                    label: q.isAnswered ? 'जवाब बदलें' : 'जवाब दें',
                    icon: 'send',
                    onTap: () async {
                      if (q.isNew && !q.read)
                        _api.aiQuestionMark(q.id, read: true).ignore();
                      if (await showAnswerSheet(context, q)) await onChanged();
                    },
                  ),
                  if (!q.isRejected)
                    AdminPill(
                      label: 'अस्वीकार',
                      icon: 'x',
                      onTap: () async {
                        final yes = await confirmPopTitled(
                          context,
                          title: 'यह सवाल अस्वीकार करें?',
                          message: 'पूछने वाले को कुछ नहीं दिखेगा।',
                          confirm: 'अस्वीकार',
                          destructive: true,
                        );
                        if (yes &&
                            await runWrite(
                              () => _api.aiQuestionReject(q.id),
                              success: 'अस्वीकृत',
                            ))
                          await onChanged();
                      },
                    ),
                  if (!q.isNew)
                    AdminPill(
                      label: 'फिर खोलें',
                      icon: 'refresh-cw',
                      onTap: () async {
                        if (await runWrite(
                          () => _api.aiQuestionMark(q.id, reopen: true),
                          success: 'फिर नया किया',
                        ))
                          await onChanged();
                      },
                    ),
                  AdminPill(
                    label: 'हटाएँ',
                    icon: 'trash-2',
                    danger: true,
                    onTap: () async {
                      final yes = await confirmPopTitled(
                        context,
                        title: 'यह सवाल हटाएँ?',
                        message: q.question,
                        confirm: 'हटाएँ',
                        destructive: true,
                      );
                      if (yes &&
                          await runWrite(
                            () => _api.aiQuestionDelete(q.id),
                            success: 'हटाया गया',
                          ))
                        await onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showAnswerSheet(BuildContext context, AiQuestion q) async =>
    (await showPop<bool>(context, (_) => _AnswerSheet(q))) ?? false;

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet(this.q);
  final AiQuestion q;
  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  late final _a = TextEditingController(text: widget.q.answer);
  bool _kb = false, _busy = false;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final a = _a.text.trim();
    final len = a.runes.length;
    if (len < 1 || len > 2000)
      return showToast('जवाब 1–2000 अक्षर का हो (अभी $len)', error: true);
    if (_kb && validateKnowledge(widget.q.question.padRight(5), a) != null)
      return showToast(
        'key point बनाने के लिए जवाब 50–2000 अक्षर का हो (अभी $len)',
        error: true,
      );
    setState(() => _busy = true);
    final ok = await runWrite(() async {
      await _api.aiQuestionAnswer(widget.q.id, a, addToKnowledge: _kb);
    }, success: _kb ? 'जवाब भेजा और key point जोड़ा' : 'जवाब भेजा गया');
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetCard(
    children: [
      SheetHead(title: 'जवाब दें', onBack: () => Navigator.pop(context, false)),
      Text(
        widget.q.question,
        style: GText.sans(
          size: 15,
          weight: FontWeight.w700,
          color: GColors.maroon,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      AdminField(
        controller: _a,
        label: 'आपका जवाब (1–2000)',
        maxLines: 8,
        counter: '${_a.text.trim().runes.length}',
        onChanged: (_) => setState(() {}),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              'AI key point में भी जोड़ें',
              style: GText.sans(
                size: 15,
                weight: FontWeight.w800,
                color: GColors.maroon,
              ),
            ),
          ),
          AdminSwitch(
            key: const ValueKey('add-kb'),
            value: _kb,
            onChanged: (v) => setState(() => _kb = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SheetButton(
        label: 'जवाब भेजें',
        primary: true,
        enabled: !_busy,
        onTap: _send,
      ),
    ],
  );
}
