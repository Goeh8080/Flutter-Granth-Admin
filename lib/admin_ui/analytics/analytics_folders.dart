import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// फ़ोल्डर एनालिटिक्स — which folders are opened, by name, with counts.
/// GA4 `folder_open {folder_id}` (names joined server-side from the structure) merged with
/// D1 `/stats/folders` (every folder key with opens + reading time).
class AnalyticsFoldersScreen extends StatefulWidget {
  const AnalyticsFoldersScreen({super.key});
  @override
  State<AnalyticsFoldersScreen> createState() => _AnalyticsFoldersScreenState();
}

class _AnalyticsFoldersScreenState extends State<AnalyticsFoldersScreen> {
  final Map<int, Future<Map<String, dynamic>>> _d1 = {};

  Future<Map<String, dynamic>> _folders(int days) => _d1.putIfAbsent(
    days,
    () => anGet('/stats/folders', query: {'days': '$days'}),
  );

  @override
  Widget build(BuildContext context) => AdminSubPage(
    title: 'फ़ोल्डर एनालिटिक्स',
    slivers: [
      SliverToBoxAdapter(
        child: AnSection(
          builder: (context, d) {
            final opens = d.best('folder_open', d.d1T['folder_opens']);
            return [
              anCard([
                anStats([
                  AnStat(
                    'फ़ोल्डर खुले',
                    '$opens',
                    GColors.saffronDark,
                    'आज ${anI(d.today['folder_open'])}',
                  ),
                ]),
                anTitle('हर दिन — फ़ोल्डर खुले'),
                anDayBars(d.byDay, const [
                  ('folder_open', 'फ़ोल्डर', GColors.saffron),
                ]),
              ]),
              FutureBuilder<Map<String, dynamic>>(
                future: _folders(d.days),
                builder: (context, s) => AnTopBlock(
                  d: d,
                  kind: 'folders',
                  title: 'फ़ोल्डर — नाम सहित (टॉप 5 + पूरी सूची)',
                  color: GColors.saffronDark,
                  d1: [
                    for (final x in anL(
                      (s.data ?? d.d1)['items'] ?? d.d1['top_folders'],
                    ))
                      (anS(x['label']), anI(x['opens'])),
                  ],
                ),
              ),
              anCard([
                anNote(
                  'नोट: ऐप folder_open तभी भेजता है जब यूज़र फ़ोल्डर खोलता है (ग्रंथ खोलने पर नहीं)।',
                ),
              ]),
            ];
          },
        ),
      ),
    ],
  );
}
