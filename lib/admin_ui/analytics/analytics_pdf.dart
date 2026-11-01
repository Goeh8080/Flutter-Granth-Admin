import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// PDF एनालिटिक्स
class AnalyticsPdfScreen extends StatelessWidget {
  const AnalyticsPdfScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'PDF एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final gen = d.best(
              'pdf_generate',
              d.d1T['pdf_ok'] ?? anM(d.d1['pdf'])['ok'],
            );
            final dl = d.best('pdf_download', d.d1Ev['pdf_download']);
            final fail = d.best('pdf_fail', anM(d.d1['pdf'])['fail']);
            final rate = gen + fail == 0
                ? 0
                : (fail * 100 / (gen + fail)).round();
            return [
              anCard([
                anStats([
                  AnStat(
                    'PDF बने',
                    '$gen',
                    GColors.maroon,
                    'आज ${anI(d.today['pdf_generate'])}',
                  ),
                  AnStat(
                    'PDF डाउनलोड',
                    '$dl',
                    GColors.saffronDark,
                    'आज ${anI(d.today['pdf_download'])}',
                  ),
                  AnStat(
                    'PDF फेल',
                    '$fail',
                    GColors.maroonLight,
                    'आज ${anI(d.today['pdf_fail'])}',
                  ),
                  AnStat('फेल दर', '$rate%', GColors.muted),
                  AnStat(
                    'सब समय: बने',
                    '${anI(anM(d.ga['all_time'])['pdf_generate'])}',
                    GColors.brown,
                  ),
                  AnStat(
                    'सब समय: डाउनलोड',
                    '${anI(anM(d.ga['all_time'])['pdf_download'])}',
                    GColors.brown,
                  ),
                ]),
                anTitle('हर दिन — PDF बने / डाउनलोड / फेल'),
                anDayBars(d.byDay, const [
                  ('pdf_generate', 'बने', GColors.maroon),
                  ('pdf_download', 'डाउनलोड', GColors.saffron),
                  ('pdf_fail', 'फेल', GColors.gold),
                ]),
              ]),
              AnTopBlock(
                d: d,
                kind: 'pdf_generate',
                title: 'टॉप 5 — सबसे ज़्यादा PDF बने (ग्रंथ)',
              ),
              AnTopBlock(
                d: d,
                kind: 'downloads',
                title: 'टॉप 5 — सबसे ज़्यादा डाउनलोड',
                color: GColors.saffronDark,
                d1: [
                  for (final x in anL(anM(d.d1['events'])['top_downloads']))
                    (anS(x['title']), anI(x['n'])),
                ],
              ),
            ];
          },
        ),
      ),
    ],
  );
}
