import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// विषय एनालिटिक्स
class AnalyticsTopicsScreen extends StatelessWidget {
  const AnalyticsTopicsScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'विषय एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final opens = d.best('topic_open', d.d1T['topic_opens']);
            return [
              anCard([
                anStats([
                  AnStat(
                    'विषय खुले',
                    '$opens',
                    GColors.maroon,
                    'आज ${anI(d.today['topic_open'])}',
                  ),
                  AnStat(
                    'प्रति दिन औसत',
                    '${(opens / d.days).toStringAsFixed(1)}',
                    GColors.brown,
                  ),
                ]),
                anTitle('हर दिन — विषय खुले'),
                anDayBars(d.byDay, const [
                  ('topic_open', 'विषय', GColors.saffron),
                ]),
              ]),
              AnTopBlock(
                d: d,
                kind: 'topics',
                title: 'टॉप 5 विषय',
                color: GColors.saffronDark,
              ),
            ];
          },
        ),
      ),
    ],
  );
}
