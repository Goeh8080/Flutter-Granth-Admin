import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_items.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
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

class _TopicsScreenState extends State<TopicsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<Topic> _all = const [];
  String _local = '';
  String _serverQuery = '';
  late bool _inactive = widget.inactiveOnly;
  bool _loading = true;
  Object? _error;
  int _rev = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = AppScope.of(context, listen: true).revision;
    if (rev != _rev) {
      _rev = rev;
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    setState(() {
      _error = null;
      if (_all.isEmpty) _loading = true;
    });
    try {
      final r = await app.api.topics(search: _serverQuery, onlyInactive: _inactive);
      if (!_inactive && _serverQuery.isEmpty) {
        app.topics = r;
      }
      if (mounted) setState(() => _all = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      if (_all.isNotEmpty) showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Topic> get _visible {
    if (_local.isEmpty) return _all;
    final q = _local.toLowerCase();
    return _all
        .where(
          (t) => t.title.toLowerCase().contains(q) || t.description.toLowerCase().contains(q) || '${t.position}' == q,
        )
        .toList();
  }

  void _open(Topic t) => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => TopicDetailScreen(topic: t)));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = _visible;
    final index = {for (var i = 0; i < items.length; i++) items[i].id: i};
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
                  suggestions: _all.map((e) => oneLine(e.title)).toList(),
                  onChanged: (v) => setState(() => _local = v.trim()),
                  onSubmitted: (v) {
                    // like searchTopic(): server-side search with &topic=
                    _serverQuery = v.trim();
                    _local = '';
                    _load();
                  },
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
                          onPressed: () {
                            _search.clear();
                            _serverQuery = '';
                            _local = '';
                            _load();
                          },
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
