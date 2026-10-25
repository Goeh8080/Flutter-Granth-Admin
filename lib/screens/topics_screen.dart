import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/catalog_store.dart';
import '../services/order.dart';
import '../services/search.dart';
import '../services/storage.dart';
import '../state/places.dart';
import '../state/router.dart';
import '../state/ui_prefs.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/live_panel.dart';
import '../widgets/panel.dart';
import '../widgets/pop.dart';
import '../admin_ui/admin_actions.dart';
import '../admin_ui/admin_data.dart';

/// `Th` — Topics / विषय / प्रश्नोत्तरी.
class TopicsPanel extends StatefulWidget {
  const TopicsPanel({super.key});
  @override
  State<TopicsPanel> createState() => _TopicsPanelState();
}

enum TopicSort { number, name, pramans, hidden }

class _TopicsPanelState extends State<TopicsPanel> with LivePanel {
  TopicSort _sort = TopicSort.number;
  String _q = Places.query('topic-list-place');
  final _log = SearchLogger();
  final _ledger = PopLedger();
  List<Topic>? _src;

  SearchDoc _doc(Topic t) => CatalogStore.I.topicDoc(t);

  @override
  void dispose() {
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = CatalogStore.I.topics;
    if (!identical(all, _src)) {
      _src = all;
    }
    var rows = searchRows(all, _q, _doc);
    if (_q.trim().isEmpty) {
      rows = [...rows];
      stableSort(rows, (a, b) => numericCompare(a.position, b.position));
      final d = AdminData.I;
      switch (_sort) {
        case TopicSort.number:
          break;
        case TopicSort.name:
          stableSort(
            rows,
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
        case TopicSort.pramans:
          stableSort(rows, (a, b) => b.pramanCount.compareTo(a.pramanCount));
        case TopicSort.hidden:
          stableSort(
            rows,
            (a, b) =>
                (d.activeTopic(a) ? 1 : 0).compareTo(d.activeTopic(b) ? 1 : 0),
          );
      }
    }
    _log.track(_q, rows.length);
    final cols = UiPrefs.I.cols(
      Store.kTopicCols,
      allowed: const [1, 2],
      fallback: 2,
    );
    final dx = panelDx();
    return SliverMainAxisGroup(
      slivers: [
        StickyHeader(
          child: Entry(
            index: 0,
            dx: dx,
            child: PageHeader(
              tone: Tone.saffron,
              icon: 'clipboard-list',
              title: 'Topics',
              subtitle: 'विषय / प्रश्नोत्तरी',
              trailing: Pressable(
                onTap: () => addPraman(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: GColors.maroon,
                    border: Border.all(color: GColors.maroon),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '+ प्रमाण जोड़ें',
                    style: GText.sans(
                      size: 12,
                      weight: FontWeight.w700,
                      color: GColors.paper,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              tools: Tools(
                grid: GridSwitch(
                  options: const [1, 2],
                  value: cols,
                  onChanged: (v) => UiPrefs.I.setCols(Store.kTopicCols, v),
                ),
                search: SearchField(
                  placeholder: 'विषय खोजें — mans, गीता, मृत्यु',
                  initial: _q,
                  onChanged: (v) {
                    Places.setQuery('topic-list-place', v);
                    setState(() => _q = v);
                  },
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SortChips<TopicSort>(
              options: const [
                (TopicSort.number, 'क्रम'),
                (TopicSort.name, 'नाम'),
                (TopicSort.pramans, 'प्रमाण'),
                (TopicSort.hidden, 'छिपे पहले'),
              ],
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        // Keyed by the column count: switching 1×1 / 2×2 / 3×3 re-lays out the grid and
        // replays the staggered card entry, so the change is visible and animated.
        KeyedSubtree(
          key: ValueKey('grid-$cols'),
          child: gridSliver(
            count: rows.length,
            cols: cols,
            gap: 14,
            item: (context, i) {
              final id = '$cols:${rows[i].id}';
              return Entry(
                index: i + 1,
                dx: dx,
                ledger: _ledger,
                id: id,
                child: CardPop(
                  ledger: _ledger,
                  id: id,
                  group: '$cols',
                  index: i + 1,
                  child: TopicCard(
                    topic: rows[i],
                    index: i + 1,
                    total: rows.length,
                    padding: cols == 2 ? 12 : 16,
                  ),
                ),
              );
            },
          ),
        ),
        if (rows.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              title: 'कोई विषय नहीं',
              body: 'सिंक पूरा होने पर विषय यहाँ दिखेंगे।',
            ),
          ),
      ],
    );
  }
}

class TopicCard extends StatelessWidget {
  const TopicCard({
    super.key,
    required this.topic,
    required this.index,
    required this.total,
    this.padding = 16,
  });
  final Topic topic;
  final int index;
  final int total;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = topic;
    final n = t.pramanCount;
    void open() => AppNav.I.go('#/pramans?topic=${t.id}');
    final active = AdminData.I.activeTopic(t);
    return Opacity(
      opacity: active ? 1 : 0.6,
      child: GCard(
        padding: EdgeInsets.all(padding),
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.position}. ${t.title}',
              style: GText.script(size: 18, color: GColors.maroon),
            ),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                t.description,
                style: GText.sans(size: 14, color: GColors.muted, height: 1.55),
              ),
            ],
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 12),
              width: double.infinity,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: GColors.creamDark)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (n > 0)
                    Pill(
                      icon: 'image',
                      label: '$n प्रमाण',
                      tone: PillTone.maroon,
                      onTap: open,
                    ),
                  if (n > 0)
                    Pill(icon: 'library', label: '$index/$total', onTap: open),
                  if (!active) const HiddenBadge(),
                  AdminPill(
                    label: 'संपादित',
                    icon: 'pen-line',
                    onTap: () => editTopic(context, t),
                  ),
                  AdminPill(
                    label: '+ प्रमाण',
                    icon: 'plus',
                    onTap: () =>
                        addPraman(context, topicId: int.tryParse(t.id)),
                  ),
                  AdminPill(
                    label: active ? 'छिपाएँ' : 'दिखाएँ',
                    icon: active ? 'eye-off' : 'eye',
                    onTap: () => toggleTopicHidden(context, t),
                  ),
                  AdminPill(
                    label: 'हटाएँ',
                    icon: 'trash-2',
                    danger: true,
                    onTap: () => removeTopic(context, t),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
