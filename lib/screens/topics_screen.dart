import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/perf.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_items.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/grid_kit.dart';
import '../widgets/toast.dart';
import 'home_shell.dart';
import 'item_actions.dart';
import 'reorder_screen.dart';
import 'topic_detail_screen.dart';
import 'topic_form.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key, this.inactiveOnly = false});
  final bool inactiveOnly;
  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> with RevisionReload<TopicsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<Topic> _all = const [];
  String _local = '';
  String _serverQuery = '';
  late bool _inactive = widget.inactiveOnly;
  bool _loading = true;
  String _sort = 'position';
  bool _desc = false;
  Object? _error;
  final _debounce = Debouncer();
  final _memo = Memo<(List<Topic>, String, String, bool), ({List<Topic> items, Map<int, int> index})>();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show what the app already holds at once, refresh behind it.
    final cached = AppScope.of(context).topics;
    if (!_inactive && cached.isNotEmpty) {
      _all = cached;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _debounce.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    final app = AppScope.of(context);
    if (_error != null || (_all.isEmpty && !_loading)) {
      setState(() {
        _error = null;
        if (_all.isEmpty) _loading = true;
      });
    }
    try {
      final r = await app.api.topics(search: _serverQuery, onlyInactive: _inactive);
      if (!_inactive && _serverQuery.isEmpty) {
        app.topics = r;
      }
      if (mounted) {
        setState(() {
          _all = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
      if (_all.isNotEmpty) showError(e);
    }
  }

  ({List<Topic> items, Map<int, int> index}) get _view => _memo.get((_all, _local, _sort, _desc), () {
    final items = _visible;
    return (items: items, index: {for (var i = 0; i < items.length; i++) items[i].id: i});
  });

  Object? _titlesFor;
  List<String> _titlesCache = const [];
  List<String> get _titles {
    if (!identical(_titlesFor, _all)) {
      _titlesFor = _all;
      _titlesCache = _all.map((e) => oneLine(e.title)).toList();
    }
    return _titlesCache;
  }

  List<Topic> get _visible {
    final base = _local.isEmpty
        ? _all
        : () {
            final q = _local.toLowerCase();
            return _all
                .where(
                  (t) =>
                      t.title.toLowerCase().contains(q) ||
                      t.description.toLowerCase().contains(q) ||
                      '${t.position}' == q,
                )
                .toList();
          }();
    return switch (_sort) {
      'title' => sortedBy(base, (t) => t.title, desc: _desc),
      'praman' => sortedBy(base, (t) => t.pramanCount, desc: _desc),
      'granth' => sortedBy(base, (t) => t.granthCount, desc: _desc),
      _ => _desc ? base.reversed.toList() : base,
    };
  }

  void _open(Topic t) => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => TopicDetailScreen(topic: t)));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (:items, :index) = _view;
    final app = AppScope.of(context);
    return GlassPage(
      title: widget.inactiveOnly ? 'निष्क्रिय विषय' : 'विषय / Topics',
      controller: _scroll,
      previousPageTitle: widget.inactiveOnly ? 'Back' : null,
      bottomInset: widget.inactiveOnly ? 0 : kTabBarHeight + 20,
      onRefresh: _load,
      trailing: widget.inactiveOnly
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassIconButton(
                  CupertinoIcons.arrow_up_arrow_down,
                  tooltip: 'Reorder',
                  onTap: () async {
                    final list = _inactive || _serverQuery.isNotEmpty ? await app.api.topics() : _all;
                    if (!context.mounted) return;
                    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => ReorderScreen.topics(list)));
                  },
                ),
                const SizedBox(width: 8),
                GlassIconButton(CupertinoIcons.add, tooltip: 'New topic', onTap: () => showTopicForm(context)),
              ],
            ),
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SliverToBoxAdapter(
            child: Column(
              children: [
                SuggestSearchField(
                  controller: _search,
                  placeholder: 'विषय खोजें / Search topic',
                  suggestions: _titles,
                  onChanged: (v) => _debounce(() {
                    if (mounted) setState(() => _local = v.trim());
                  }),
                  onSubmitted: (v) => _debounce.now(() {
                    // like searchTopic(): server-side search with &topic=
                    _serverQuery = v.trim();
                    _local = '';
                    _load();
                  }),
                ),
                const SizedBox(height: 10),
                SortBar(
                  options: const [
                    SortOpt('position', 'क्रम'),
                    SortOpt('title', 'नाम'),
                    SortOpt('praman', 'प्रमाण'),
                    SortOpt('granth', 'ग्रंथ'),
                  ],
                  sortKey: _sort,
                  desc: _desc,
                  onChanged: (k, d) => setState(() {
                    _desc = k != _sort && (k == 'praman' || k == 'granth') ? true : d;
                    _sort = k;
                  }),
                ),
                if (!widget.inactiveOnly) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<bool>(
                      groupValue: _inactive,
                      backgroundColor: p.fieldFill,
                      thumbColor: p.dark ? const Color(0xFF3A3340) : Colors.white,
                      children: const {
                        false: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('सभी / All')),
                        true: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('निष्क्रिय / Inactive')),
                      },
                      onValueChanged: (v) {
                        _debounce.dispose();
                        setState(() {
                          _inactive = v ?? false;
                          _serverQuery = '';
                          _search.clear();
                          _local = '';
                        });
                        _load();
                      },
                    ),
                  ),
                ],
                if (_serverQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'खोज: "$_serverQuery" — ${_all.length} परिणाम',
                            style: TextStyle(color: p.subtext, fontSize: 13),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          onPressed: () => _debounce.now(() {
                            _search.clear();
                            _serverQuery = '';
                            _local = '';
                            _load();
                          }),
                          child: const Text('हटाएँ / Clear', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_loading && _all.isEmpty)
          const SliverToBoxAdapter(child: LoadingView())
        else if (_error != null && _all.isEmpty)
          SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.wifi_exclamationmark, title: '$_error', onRetry: _load),
          )
        else if (items.isEmpty)
          const SliverToBoxAdapter(
            child: MessageView(icon: CupertinoIcons.doc_text_search, title: 'कोई विषय नहीं / No topics'),
          )
        else
          PadSliver(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AnimatedItemsSliver<Topic>(
              items: items,
              idOf: (t) => t.id,
              itemBuilder: (ctx, t, i) => TopicCard(
                topic: t,
                index: index[t.id] ?? i,
                total: items.length,
                onTap: () => _open(t),
                onLongPress: () => showTopicActions(context, t),
              ),
            ),
          ),
      ],
    );
  }
}
