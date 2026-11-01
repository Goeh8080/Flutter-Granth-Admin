import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// AI एनालिटिक्स
class AnalyticsAiScreen extends StatelessWidget {
  const AnalyticsAiScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'AI एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final ai1 = anM(d.d1['ai']);
            final ans = d.best(
              'ai_answer',
              d.d1Ev['ai_answer'] ?? ai1['answered'],
            );
            final fail = d.best('ai_fail', d.d1Ev['ai_fail']);
            final ask = [
              d.best('ai_ask', ai1['asked']),
              ans + fail,
            ].reduce((a, b) => a > b ? a : b);
            final rate = ans + fail == 0
                ? 0
                : (fail * 100 / (ans + fail)).round();
            return [
              anCard([
                anStats([
                  AnStat(
                    'AI प्रश्न',
                    '$ask',
                    GColors.maroon,
                    'आज ${anI(d.today['ai_ask'])}',
                  ),
                  AnStat(
                    'AI जवाब',
                    '$ans',
                    GColors.online,
                    'आज ${anI(d.today['ai_answer'])}',
                  ),
                  AnStat(
                    'AI फेल',
                    '$fail',
                    GColors.maroonLight,
                    'आज ${anI(d.today['ai_fail'])}',
                  ),
                  AnStat('फेल दर', '$rate%', GColors.muted),
                  AnStat(
                    'प्रमाण टैप',
                    '${d.best('cite_tap', ai1['cite_tap'])}',
                    GColors.saffronDark,
                  ),
                ]),
                anTitle('हर दिन — AI प्रश्न / जवाब / फेल'),
                anDayBars(d.byDay, const [
                  ('ai_ask', 'प्रश्न', GColors.saffron),
                  ('ai_answer', 'जवाब', GColors.online),
                  ('ai_fail', 'फेल', GColors.maroon),
                ]),
              ]),
              AnTopBlock(
                d: d,
                kind: 'ai_fail',
                title: 'टॉप 5 — फेल हुए प्रश्न',
                color: GColors.maroonLight,
              ),
              anCard([
                anTitle('हाल के फेल प्रश्न (सर्वर लॉग)'),
                for (final x in anL(anM(d.d1['events'])['ai_fails']).take(15))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: anNote(
                      '• ${anS(x['question'])}  (${anS(x['reason'])}, ${anS(x['day'])})',
                    ),
                  ),
                if (anL(anM(d.d1['events'])['ai_fails']).isEmpty)
                  anNote('कोई नहीं'),
              ]),
            ];
          },
        ),
      ),
    ],
  );
}
