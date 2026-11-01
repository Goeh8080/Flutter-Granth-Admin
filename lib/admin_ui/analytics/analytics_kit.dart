import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../admin/services/panel_api.dart';
import '../../theme/colors.dart';
import '../../widgets/common.dart';
import '../admin_data.dart';

/// Round-3 analytics kit: data access (worker D1 + GA4 + presence) and charts in the old
/// Cloudflare-panel style (public/admin/app.js `barChart`: rounded day bars, a top/bottom grid
/// line, the max value top-left, first/last day under the axis).
PanelApi get anApi => AdminData.I.app.panel.api;

int anI(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String anS(Object? v) => v == null ? '' : '$v';
Map<String, dynamic> anM(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> anL(Object? v) =>
    v is List ? v.map(anM).toList() : <Map<String, dynamic>>[];

/// GET that never throws: errors come back as `{'_error': text}`.
Future<Map<String, dynamic>> anGet(
  String path, {
  Map<String, String>? query,
}) async {
  try {
    return await anApi.raw('GET', path, query: query);
  } on PanelApiException catch (e) {
    return {'_error': '${e.code}${e.status == null ? '' : ' · ${e.status}'}'};
  } catch (e) {
    return {'_error': '$e'};
  }
}

/// Everything a section page needs for a range, loaded in parallel.
class AnData {
  AnData(this.days, this.ga, this.live, this.d1, this.presence);
  final int days;
  final Map<String, dynamic> ga, live, d1, presence;
  Map<String, dynamic> get gaT => anM(ga['totals']);
  Map<String, dynamic> get today => anM(live['today']);
  Map<String, dynamic> get d1T => anM(d1['totals']);
  Map<String, dynamic> get d1Ev => anM(anM(d1['events'])['totals']);
  List<Map<String, dynamic>> get byDay =>
      anFillDays(anL(ga['by_day']), days, ga['start_date'], ga['reset_at']);
  List<String> get errors => [
    if (ga['_error'] != null) 'GA: ${ga['_error']}',
    if (d1['_error'] != null) 'D1: ${d1['_error']}',
  ];

  /// Best estimate of a counter: GA4 and the worker's own D1 counters are two independent
  /// channels from the same app, so the larger one is the most complete.
  int best(String gaKey, [num? d1]) => math.max(anI(gaT[gaKey]), anI(d1));

  static Future<AnData> load(int days) async {
    final q = {'days': '$days'};
    final r = await Future.wait([
      anGet('/ga/overview', query: q),
      anGet('/ga/live'),
      anGet('/stats/overview', query: q),
      anGet('/live'),
    ]);
    return AnData(days, r[0], r[1], r[2], r[3]);
  }

  Future<Map<String, dynamic>> top(String kind) =>
      anGet('/ga/top', query: {'kind': kind, 'days': '$days'});
}

/// Today as `YYYY-MM-DD` in IST (the GA property's day).
String anIstToday([DateTime? now]) => (now ?? DateTime.now())
    .toUtc()
    .add(const Duration(hours: 5, minutes: 30))
    .toIso8601String()
    .substring(0, 10);

/// GA leaves out days without any event, so a chart of only the returned rows squeezes the
/// timeline and shows wrong first/last dates. Rebuild one row per day from the range start
/// (the later of `days` ago and the analytics reset day) to today; missing days are zeros.
List<Map<String, dynamic>> anFillDays(
  List<Map<String, dynamic>> rows,
  int days,
  Object? startDate,
  Object? resetAt, {
  DateTime? now,
}) {
  final today = DateTime.parse('${anIstToday(now)}T00:00:00Z');
  var start = DateTime.utc(today.year, today.month, today.day - (days - 1));
  final sd = anS(startDate);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sd)) {
    final d = DateTime.parse('${sd}T00:00:00Z');
    if (d.isAfter(start)) start = d;
  } else {
    final r = DateTime.tryParse(anS(resetAt));
    if (r != null) {
      final rd = DateTime.parse('${anIstToday(r)}T00:00:00Z');
      if (rd.isAfter(start)) start = rd;
    }
  }
  if (start.isAfter(today)) start = today;
  final byDay = {for (final r in rows) anS(r['day']): r};
  return [
    for (
      var d = start;
      !d.isAfter(today);
      d = DateTime.utc(d.year, d.month, d.day + 1)
    )
      byDay[d.toIso8601String().substring(0, 10)] ??
          {'day': d.toIso8601String().substring(0, 10)},
  ];
}

/// id → real name for GA top lists, from the content the admin app already loaded.
Map<String, String> anNames(String kind) {
  final a = AdminData.I;
  return switch (kind) {
    'praman' => {
      for (final p in a.pramans)
        p.id: p.title.isNotEmpty ? p.title : 'प्रमाण #${p.id}',
    },
    'topics' => {
      for (final t in a.topics)
        t.id: t.title.isNotEmpty ? t.title : 'विषय #${t.id}',
    },
    'granths' || 'downloads' || 'pdf_generate' => {
      for (final g in a.granths)
        g.id: g.title.isNotEmpty ? g.title : 'ग्रंथ #${g.id}',
    },
    _ => const {},
  };
}

String anDur(Object? s) {
  final n = anI(s);
  if (n < 60) return '$n से.';
  final h = n ~/ 3600, m = (n % 3600) ~/ 60;
  if (h >= 24) return '${h ~/ 24} दिन ${h % 24} घं.';
  return h > 0 ? '$h घं. $m मि.' : '$m मि.';
}

String anNum(num n) => n >= 100000
    ? '${(n / 100000).toStringAsFixed(1)} लाख'
    : n >= 1000
    ? '${(n / 1000).toStringAsFixed(1)}k'
    : '$n';

/// `2026-10-31T12:06:00Z` → `31-10-2026 17:36 IST`.
String anIst(Object? iso) {
  final d = DateTime.tryParse(anS(iso));
  if (d == null) return '-';
  final t = d.toUtc().add(const Duration(hours: 5, minutes: 30));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${p(t.day)}-${p(t.month)}-${t.year} ${p(t.hour)}:${p(t.minute)} IST';
}

const anColors = [
  GColors.saffron,
  GColors.maroon,
  GColors.gold,
  GColors.online,
  GColors.brown,
];

Widget anTitle(String t) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 8),
  child: Text(
    t,
    style: GText.sans(
      size: 13.5,
      weight: FontWeight.w800,
      color: GColors.brown,
    ),
  ),
);

Widget anNote(String t) =>
    Text(t, style: GText.sans(size: 12, color: GColors.muted, height: 1.35));

Widget anCard(List<Widget> children, {Key? key}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: GCard(
    key: key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);

class AnStat {
  const AnStat(this.label, this.value, [this.color = GColors.maroon, this.sub]);
  final String label, value;
  final Color color;
  final String? sub;
}

Widget anStats(List<AnStat> items) => LayoutBuilder(
  builder: (context, c) {
    final cols = c.maxWidth > 520 ? 4 : (c.maxWidth > 330 ? 3 : 2);
    final w = (c.maxWidth - (cols - 1) * 8) / cols;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: GColors.pill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GColors.creamDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    it.value,
                    style: GText.sans(
                      size: 20,
                      weight: FontWeight.w800,
                      color: it.color,
                    ),
                  ),
                ),
                Text(
                  it.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GText.sans(
                    size: 11.5,
                    color: GColors.muted,
                    height: 1.25,
                  ),
                ),
                if (it.sub != null)
                  Text(
                    it.sub!,
                    style: GText.sans(size: 10.5, color: GColors.muted),
                  ),
              ],
            ),
          ),
      ],
    );
  },
);

/// Old Cloudflare-panel day chart: one rounded bar per day (several series side by side).
Widget anDayBars(
  List<Map<String, dynamic>> rows,
  List<(String key, String label, Color color)> series, {
  bool duration = false,
}) {
  if (rows.isEmpty) {
    return anNote(
      'अभी कोई डेटा नहीं (GA रिपोर्ट में 24-48 घंटे लगते हैं; आज का डेटा ऊपर रियलटाइम से है)',
    );
  }
  double v(Map<String, dynamic> r, String k) =>
      r[k] is num ? (r[k] as num).toDouble() : 0;
  var maxY = 0.0;
  for (final r in rows) {
    for (final s in series) {
      maxY = math.max(maxY, v(r, s.$1));
    }
  }
  if (maxY <= 0) {
    return anNote(
      'इस अवधि में अभी कोई डेटा नहीं (${anS(rows.first['day'])} से; GA रिपोर्ट में 24-48 घंटे लगते हैं)',
    );
  }
  final top = maxY;
  final n = rows.length;
  final rodW = math.max(1.5, math.min(14.0, 220 / (n * series.length)));
  String day(int i) {
    final d = anS(rows[i]['day']);
    return d.length >= 10 ? d.substring(5) : d;
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (series.length > 1)
        Wrap(
          spacing: 12,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.$3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    s.$2,
                    style: GText.sans(size: 11.5, color: GColors.muted),
                  ),
                ],
              ),
          ],
        ),
      Text(
        duration ? anDur(maxY) : anNum(maxY),
        style: GText.sans(size: 10.5, color: GColors.muted),
      ),
      SizedBox(
        height: 150,
        child: BarChart(
          BarChartData(
            maxY: top,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: top,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: GColors.creamDark, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  getTitlesWidget: (x, m) {
                    final i = x.toInt();
                    if (i != 0 && i != n - 1 && (n < 9 || i != n ~/ 2)) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      day(i),
                      style: GText.sans(size: 10, color: GColors.muted),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => GColors.brown,
                getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                  '${day(g.x)}\n${series[ri].$2}: ${duration ? anDur(rod.toY) : rod.toY.toInt()}',
                  GText.sans(size: 11, color: Colors.white),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 1,
                  barRods: [
                    for (final s in series)
                      BarChartRodData(
                        toY: v(rows[i], s.$1),
                        color: s.$3,
                        width: rodW,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Top-5 vertical bar graph with a numbered legend underneath.
Widget anTop5(
  List<(String label, num n)> items, {
  Color color = GColors.maroon,
}) {
  final list = items.where((e) => e.$2 > 0).take(5).toList();
  if (list.isEmpty) return anNote('अभी कोई डेटा नहीं');
  final maxN = list.fold<num>(0, (a, b) => math.max(a, b.$2)).toDouble();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 140,
        child: BarChart(
          BarChartData(
            maxY: maxN * 1.15,
            minY: 0,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxN <= 0 ? 1 : maxN * 1.15,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: GColors.creamDark, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 16,
                  getTitlesWidget: (x, m) => Text(
                    anNum(list[x.toInt()].$2),
                    style: GText.sans(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: GColors.brown,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  getTitlesWidget: (x, m) => Text(
                    '${x.toInt() + 1}',
                    style: GText.sans(size: 11, color: GColors.muted),
                  ),
                ),
              ),
            ),
            barTouchData: BarTouchData(enabled: false),
            barGroups: [
              for (var i = 0; i < list.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: list[i].$2.toDouble(),
                      color: i == 0
                          ? color
                          : color.withValues(alpha: 0.55 + 0.1 * (4 - i) / 4),
                      width: 26,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '${i + 1}. ${list[i].$1} — ${list[i].$2}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GText.sans(size: 12.5, color: GColors.text),
          ),
        ),
    ],
  );
}

/// GA `/ga/top` answer → (label, n) list.
/// Server labels win unless they are just the raw id; then [names] (local content) is used.
List<(String, num)> anTopItems(
  Map<String, dynamic> t, {
  Map<String, String> names = const {},
}) {
  final out = <(String, num)>[];
  for (final x in anL(t['items'])) {
    final id = anS(x['id']), label = anS(x['label']);
    final raw = label.isEmpty || label == id || label == '#$id';
    final name = id == '(not set)' || id.isEmpty
        ? 'अज्ञात (id नहीं भेजी गई)'
        : raw
        ? (names[id] ?? (label.isEmpty ? id : label))
        : label;
    out.add((name, anI(x['n'])));
  }
  return anMerge(out, const []);
}

/// Merge two ranked lists (GA + D1) by label taking the larger count per label.
List<(String, num)> anMerge(List<(String, num)> a, List<(String, num)> b) {
  final m = <String, num>{};
  for (final e in [...a, ...b]) {
    m[e.$1] = math.max(m[e.$1] ?? 0, e.$2);
  }
  final out = m.entries.map((e) => (e.key, e.value)).toList()
    ..sort((x, y) => y.$2.compareTo(x.$2));
  return out;
}

/// 7 / 30 / 90 day chips.
class AnRange extends StatelessWidget {
  const AnRange({super.key, required this.days, required this.onChanged});
  final int days;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Wrap(
      spacing: 8,
      children: [
        for (final d in const [7, 30, 90])
          ChoiceChip(
            label: Text('$d दिन'),
            selected: d == days,
            selectedColor: GColors.saffron.withValues(alpha: 0.25),
            onSelected: (_) => onChanged(d),
          ),
      ],
    ),
  );
}

/// Loads [AnData] for a range and rebuilds; pull-to-refresh and range chips built in.
class AnSection extends StatefulWidget {
  const AnSection({super.key, required this.builder});
  final List<Widget> Function(BuildContext context, AnData d) builder;
  @override
  State<AnSection> createState() => _AnSectionState();
}

class _AnSectionState extends State<AnSection> {
  int _days = 30;
  AnData? _d;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final d = await AnData.load(_days);
    if (mounted) {
      setState(() {
        _d = d;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AnRange(
                days: _days,
                onChanged: (v) {
                  _days = v;
                  _load();
                },
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh, color: GColors.maroon),
            ),
          ],
        ),
        if (d == null)
          const EmptyState(title: 'लोड हो रहा है…', spinner: true)
        else ...[
          if (_busy)
            const LinearProgressIndicator(minHeight: 2, color: GColors.saffron),
          if (d.errors.isNotEmpty)
            anCard([anNote('कुछ स्रोत उपलब्ध नहीं: ${d.errors.join(' · ')}')]),
          ...widget.builder(context, d),
          anNote(
            'स्रोत: GA4 (${d.days} दिन) + सर्वर D1 काउंटर — दोनों में से बड़ा मान; "आज" = GA आज + रियलटाइम।',
          ),
        ],
      ],
    );
  }
}

/// Async top list block (GA `/ga/top`), optionally merged with a D1 list.
class AnTopBlock extends StatelessWidget {
  const AnTopBlock({
    super.key,
    required this.d,
    required this.kind,
    required this.title,
    this.d1 = const [],
    this.color = GColors.maroon,
    this.names,
  });
  final AnData d;
  final String kind, title;
  final List<(String, num)> d1;
  final Color color;

  /// id → name; defaults to [anNames] for [kind].
  final Map<String, String>? names;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: d.top(kind),
    builder: (context, s) {
      final t = s.data ?? const {};
      return anCard([
        anTitle(title),
        if (!s.hasData)
          const LinearProgressIndicator(minHeight: 2, color: GColors.saffron)
        else ...[
          ...() {
            final all = anMerge(
              anTopItems(t, names: names ?? anNames(kind)),
              d1,
            ).where((e) => e.$2 > 0).toList();
            return [
              anTop5(all, color: color),
              if (all.isNotEmpty) anFullList(all, color: color),
            ];
          }(),
          if (t['dims_missing'] == true)
            anNote(
              'GA में custom dimension "${anS(t['param'])}" रजिस्टर नहीं है।',
            ),
        ],
      ]);
    },
  );
}

/// "पूरी सूची": every opened item by name with its count, highest first (collapsed by default).
Widget anFullList(List<(String, num)> items, {Color color = GColors.maroon}) =>
    Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'पूरी सूची (${items.length})',
          style: GText.sans(size: 13, weight: FontWeight.w700, color: color),
        ),
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
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
                    anNum(items[i].$2),
                    style: GText.sans(
                      size: 12.5,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
