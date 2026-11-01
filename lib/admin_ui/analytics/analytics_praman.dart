import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// प्रमाण एनालिटिक्स
class AnalyticsPramaanScreen extends StatelessWidget {
  const AnalyticsPramaanScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'प्रमाण एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final opens = d.best('praman_open', d.d1T['praman_opens']);
            final cites = d.best('cite_tap', anM(d.d1['ai'])['cite_tap']);
            return [
              anCard([
                anStats([
                  AnStat(
                    'प्रमाण खुले',
                    '$opens',
                    GColors.maroon,
                    'आज ${anI(d.today['praman_open'])}',
                  ),
                  AnStat(
                    'AI से प्रमाण टैप',
                    '$cites',
                    GColors.saffronDark,
                    'आज ${anI(d.today['cite_tap'])}',
                  ),
                  AnStat(
                    'प्रति दिन औसत',
                    '${(opens / d.days).toStringAsFixed(1)}',
                    GColors.brown,
                  ),
                ]),
                anTitle('हर दिन — प्रमाण खुले / AI प्रमाण टैप'),
                anDayBars(d.byDay, const [
                  ('praman_open', 'प्रमाण', GColors.maroon),
                  ('cite_tap', 'AI टैप', GColors.gold),
                ]),
              ]),
              AnTopBlock(d: d, kind: 'praman', title: 'टॉप 5 प्रमाण'),
            ];
          },
        ),
      ),
    ],
  );
}
