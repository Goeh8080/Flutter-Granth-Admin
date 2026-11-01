import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// ग्रंथ एनालिटिक्स
class AnalyticsGranthScreen extends StatelessWidget {
  const AnalyticsGranthScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'ग्रंथ एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final opens = d.best('granth_open', d.d1T['granth_opens']);
            final folders = d.best('folder_open', d.d1T['folder_opens']);
            return [
              anCard([
                anStats([
                  AnStat(
                    'ग्रंथ खुले',
                    '$opens',
                    GColors.maroon,
                    'आज ${anI(d.today['granth_open'])}',
                  ),
                  AnStat(
                    'फ़ोल्डर खुले',
                    '$folders',
                    GColors.saffronDark,
                    'आज ${anI(d.today['folder_open'])}',
                  ),
                  AnStat(
                    'पढ़ने का समय',
                    anDur(d.d1T['granth_watch_s']),
                    GColors.online,
                  ),
                  AnStat(
                    'औसत/ग्रंथ खुलना',
                    opens == 0
                        ? '-'
                        : anDur(anI(d.d1T['granth_watch_s']) ~/ opens),
                    GColors.brown,
                  ),
                ]),
                anTitle('हर दिन — ग्रंथ / फ़ोल्डर खुले'),
                anDayBars(d.byDay, const [
                  ('granth_open', 'ग्रंथ', GColors.maroon),
                  ('folder_open', 'फ़ोल्डर', GColors.saffron),
                ]),
              ]),
              AnTopBlock(
                d: d,
                kind: 'granths',
                title: 'ग्रंथ — नाम सहित (टॉप 5 + पूरी सूची)',
                d1: [
                  for (final x in anL(d.d1['top_granths_opens']))
                    (anS(x['title']), anI(x['opens'])),
                ],
              ),
              anCard([
                anTitle('टॉप 5 ग्रंथ — पढ़ने का समय (D1)'),
                anTop5([
                  for (final x in anL(d.d1['top_granths_watch']))
                    (anS(x['title']), anI(x['watch_s']) ~/ 60),
                ], color: GColors.online),
                anNote('मान = मिनट'),
              ]),
              AnTopBlock(
                d: d,
                kind: 'folders',
                title: 'टॉप 5 फ़ोल्डर',
                color: GColors.saffronDark,
                d1: [
                  for (final x in anL(d.d1['top_folders']))
                    (anS(x['label']), anI(x['opens'])),
                ],
              ),
            ];
          },
        ),
      ),
    ],
  );
}
