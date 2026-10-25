import 'package:flutter/cupertino.dart';

import '../../models/panel_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_scaffold.dart';
import 'panel_inbox.dart';
import 'panel_widgets.dart';

/// आँकड़े: analytics collected anonymously from the user app.
class PanelDashboardScreen extends StatefulWidget {
  const PanelDashboardScreen({super.key});
  @override
  State<PanelDashboardScreen> createState() => _PanelDashboardScreenState();
}

class _PanelDashboardScreenState extends State<PanelDashboardScreen> {
  int days = 7;

  @override
  Widget build(BuildContext context) {
    return PanelPage<StatsOverview>(
      key: ValueKey('stats$days'),
      title: 'आँकड़े / Stats',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.statsOverview(days: days),
      builder: (context, s, reload) => [
        PadSliver(
          child: SliverList(
            delegate: SliverChildListDelegate([
              Segments<int>(value: days, items: const {7: '7 दिन', 30: '30 दिन', 90: '90 दिन'}, onChanged: (v) => setState(() => days = v)),
              const SizedBox(height: 14),
              ...statsCards(context, s),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Dashboard body (also used by tests and the hub preview).
List<Widget> statsCards(BuildContext context, StatsOverview s) {
  final t = s.totals;
  final days = s.days;
  final widgets = <Widget>[];

  if (s.newGranthsPending > 0) {
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StatCard(
          icon: CupertinoIcons.tray_arrow_down_fill,
          color: AppColors.gold,
          label: 'नए ग्रंथ',
          value: '${s.newGranthsPending}',
          sub: '${s.newGranthsPending} नए ग्रंथों को फ़ोल्डर चाहिए — देखने के लिए दबाएँ',
          onTap: () => pushPanel(context, const PanelInboxScreen()),
        ),
      ),
    );
  }

  if (s.isEmpty) {
    widgets.add(
      const SectionCard(
        title: 'अभी कोई डेटा नहीं',
        icon: CupertinoIcons.chart_bar_alt_fill,
        child: EmptyNote(
          'जैसे ही यूज़र ऐप चलेगा और एनालिटिक्स चालू होगा, यहाँ इंस्टॉल, उपयोग-समय और सबसे ज़्यादा देखे गए ग्रंथ दिखेंगे।\n(ऐप में कोई व्यक्तिगत जानकारी नहीं जाती।)',
        ),
      ),
    );
  }

  widgets.add(
    CardGrid(
      children: [
        StatCard(icon: CupertinoIcons.device_phone_portrait, label: 'कुल इंस्टॉल', value: fmtNum(t.totalInstalls), sub: t.firstInstallDay == null ? null : 'पहला: ${t.firstInstallDay}'),
        StatCard(icon: CupertinoIcons.plus_circle_fill, color: AppColors.green, label: 'नए इंस्टॉल ($daysद)', value: fmtNum(t.newInstallsInRange)),
        StatCard(icon: CupertinoIcons.sun_max_fill, color: AppColors.gold, label: 'आज सक्रिय', value: fmtNum(t.active1d)),
        StatCard(icon: CupertinoIcons.calendar, color: AppColors.blue, label: '7 दिन सक्रिय', value: fmtNum(t.active7d)),
        StatCard(icon: CupertinoIcons.calendar_today, color: AppColors.blue, label: '30 दिन सक्रिय', value: fmtNum(t.active30d)),
        StatCard(icon: CupertinoIcons.person_2_fill, label: '$daysद में यूज़र', value: fmtNum(t.usersInRange)),
        StatCard(icon: CupertinoIcons.time_solid, color: AppColors.maroon, label: 'कुल समय ($daysद)', value: fmtDur(t.totalFgS), sub: 'अब तक: ${fmtDur(t.totalFgSAllTime)}'),
        StatCard(icon: CupertinoIcons.timer, color: AppColors.maroon, label: 'औसत समय / यूज़र', value: fmtDur(t.avgFgSPerActiveUser), sub: 'रोज़: ${fmtDur(t.avgFgSPerActiveUserDay)}'),
      ],
    ),
  );
  widgets.add(const SizedBox(height: 12));

  if (s.dau.isNotEmpty) {
    widgets.add(
      SectionCard(
        title: 'रोज़ सक्रिय यूज़र',
        icon: CupertinoIcons.chart_bar_fill,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiniChart(values: [for (final d in s.dau) d.n]),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(s.dau.first.day, style: const TextStyle(fontSize: 11)), Text(s.dau.last.day, style: const TextStyle(fontSize: 11))],
            ),
          ],
        ),
      ),
    );
  }

  widgets.add(
    SectionCard(
      title: 'टॉप ग्रंथ — सबसे ज़्यादा खुले',
      icon: CupertinoIcons.book_fill,
      child: s.topGranthsOpens.isEmpty
          ? const EmptyNote('अभी कोई ग्रंथ नहीं खुला')
          : BarList(rows: [for (final g in s.topGranthsOpens) BarRow(g.title.isEmpty ? g.id : g.title, g.opens.toDouble(), '${fmtNum(g.opens)} बार')]),
    ),
  );
  widgets.add(
    SectionCard(
      title: 'टॉप ग्रंथ — सबसे ज़्यादा समय',
      icon: CupertinoIcons.time,
      child: s.topGranthsWatch.isEmpty
          ? const EmptyNote('अभी समय का डेटा नहीं')
          : BarList(
              color: AppColors.maroon,
              rows: [for (final g in s.topGranthsWatch) BarRow(g.title.isEmpty ? g.id : g.title, g.watchS.toDouble(), fmtDur(g.watchS))],
            ),
    ),
  );
  widgets.add(
    SectionCard(
      title: 'टॉप फ़ोल्डर',
      icon: CupertinoIcons.folder_fill,
      child: s.topFolders.isEmpty
          ? const EmptyNote('अभी कोई फ़ोल्डर नहीं खुला')
          : BarList(
              color: AppColors.gold,
              rows: [for (final f in s.topFolders) BarRow(f.label.isEmpty ? f.key : f.label, f.opens.toDouble(), '${fmtNum(f.opens)} बार • ${fmtDur(f.watchS)}')],
            ),
    ),
  );
  if (s.religions.isNotEmpty) {
    widgets.add(
      SectionCard(
        title: 'धर्म अनुसार उपयोग',
        icon: CupertinoIcons.square_grid_2x2_fill,
        child: BarList(
          color: AppColors.blue,
          rows: [for (final f in s.religions) BarRow(f.label.isEmpty ? f.key : f.label, f.watchS.toDouble(), fmtDur(f.watchS))],
        ),
      ),
    );
  }
  widgets.add(
    SectionCard(
      title: 'स्क्रीन (समय)',
      icon: CupertinoIcons.device_phone_portrait,
      child: s.screens.isEmpty
          ? const EmptyNote('अभी स्क्रीन का डेटा नहीं')
          : BarList(rows: [for (final x in s.screens) BarRow(screenLabel(x.name), x.watchS.toDouble(), fmtDur(x.watchS))]),
    ),
  );

  final versions = s.installsByVersion.isNotEmpty
      ? [for (final v in s.installsByVersion) BarRow('v${v.name}', v.n.toDouble(), '${v.n}')]
      : [for (final e in s.versions.entries) BarRow('v${e.key}', e.value.toDouble(), '${e.value}')];
  widgets.add(
    SectionCard(
      title: 'ऐप वर्ज़न',
      icon: CupertinoIcons.number,
      child: versions.isEmpty ? const EmptyNote('अभी कोई वर्ज़न डेटा नहीं') : BarList(color: AppColors.green, rows: versions),
    ),
  );

  final syncTotal = s.syncOk + s.syncFail;
  final pdfTotal = s.pdfOk + s.pdfFail;
  widgets.add(
    SectionCard(
      title: 'सिंक और PDF समस्याएँ',
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardGrid(
            children: [
              StatCard(
                icon: CupertinoIcons.arrow_2_circlepath,
                color: s.syncFail > 0 ? AppColors.red : AppColors.green,
                label: 'सिंक फ़ेल',
                value: '${s.syncFail}',
                sub: syncTotal == 0 ? 'कोई सिंक नहीं' : '$syncTotal में से (${(s.syncFailRate * 100).toStringAsFixed(1)}%)',
              ),
              StatCard(
                icon: CupertinoIcons.doc_richtext,
                color: s.pdfFail > 0 ? AppColors.red : AppColors.green,
                label: 'PDF फ़ेल',
                value: '${s.pdfFail}',
                sub: pdfTotal == 0 ? 'कोई PDF नहीं' : '$pdfTotal में से',
              ),
            ],
          ),
          if (s.failureKinds.isNotEmpty) ...[
            const SizedBox(height: 12),
            BarList(color: AppColors.red, rows: [for (final f in s.failureKinds) BarRow(f.name, f.n.toDouble(), '${f.n}')]),
          ],
        ],
      ),
    ),
  );

  if (s.aiAsked > 0) {
    widgets.add(
      SectionCard(
        title: 'AI उपयोग',
        icon: CupertinoIcons.sparkles,
        child: CardGrid(
          children: [
            StatCard(icon: CupertinoIcons.chat_bubble_2_fill, label: 'सवाल पूछे', value: fmtNum(s.aiAsked)),
            StatCard(icon: CupertinoIcons.checkmark_seal_fill, color: AppColors.green, label: 'जवाब मिले', value: fmtNum(s.aiAnswered)),
          ],
        ),
      ),
    );
  }
  widgets.add(const SizedBox(height: 4));
  return widgets;
}
