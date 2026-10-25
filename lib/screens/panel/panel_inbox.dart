import 'package:flutter/cupertino.dart';

import '../../models/panel_models.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

typedef InboxData = (PanelAlerts, List<PanelLeaf>);

/// नए ग्रंथ: catalogue entries the website added that have no folder decision yet.
class PanelInboxScreen extends StatefulWidget {
  const PanelInboxScreen({super.key});
  @override
  State<PanelInboxScreen> createState() => _PanelInboxScreenState();
}

class _PanelInboxScreenState extends State<PanelInboxScreen> {
  final _busy = <String>{};
  bool _syncing = false;

  Future<void> _run(String key, Future<void> Function() f, String done) async {
    final panel = panelOf(context);
    setState(() => _busy.add(key));
    try {
      await f();
      showToast(done);
      panel.bump();
      await panel.refreshAlerts();
    } on PanelApiException catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _sync() async {
    final panel = panelOf(context);
    setState(() => _syncing = true);
    try {
      final r = await panel.api.syncNow();
      if (!r.ok) {
        showToast('सिंक नहीं हुआ: ${r.error ?? ''}', error: true);
      } else {
        showToast('सिंक पूरा: ${r.count} ग्रंथ, ${r.added.length} नए');
        panel.bump();
        await panel.refreshAlerts();
      }
    } on PanelApiException catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<InboxData>(
      title: 'नए ग्रंथ / Inbox',
      previousPageTitle: 'कंट्रोल',
      load: (api) async {
        final a = await api.alerts();
        var leaves = <PanelLeaf>[];
        try {
          leaves = (await api.structure()).leaves;
        } on PanelApiException {
          // the assign button just needs the list; retry on next reload
        }
        return (a, leaves);
      },
      trailing: _syncing
          ? const CupertinoActivityIndicator()
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _sync,
              child: const Icon(CupertinoIcons.arrow_2_circlepath),
            ),
      builder: (context, data, reload) {
        final a = data.$1;
        final leaves = data.$2;
        final empty = a.newGranths.isEmpty && a.alerts.isEmpty;
        return [
          PadSliver(
            child: SliverMainAxisGroup(
              slivers: [
                SliverList(
                  delegate: SliverChildListDelegate([
                    const DraftBanner(),
                    if (empty)
                      const SizedBox(
                        height: 340,
                        child: MessageView(
                          icon: CupertinoIcons.checkmark_seal,
                          title: 'सब ठीक है',
                          subtitle:
                              'कोई नया ग्रंथ फ़ोल्डर का इंतज़ार नहीं कर रहा। ऊपर दाएँ बटन से वेबसाइट से सिंक करें।',
                        ),
                      ),
                  ]),
                ),
                // Rows are built lazily as they scroll into view.
                SliverList.builder(
                  itemCount: a.newGranths.length + a.alerts.length,
                  itemBuilder: (context, i) => i < a.newGranths.length
                      ? _card(context, a.newGranths[i], leaves, p)
                      : _alert(context, a.alerts[i - a.newGranths.length], p),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }

  Widget _alert(BuildContext context, PanelAlert al, Palette p) {
    final key = 'a:${al.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const Icon(CupertinoIcons.bell_fill, color: AppColors.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(al.message, style: TextStyle(color: p.text, fontSize: 14)),
                  Text(shortTs(al.createdAt), style: TextStyle(color: p.subtext, fontSize: 11.5)),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: _busy.contains(key)
                  ? null
                  : () => _run(key, () => panelOf(context).api.ackAlert(al.id), 'हटाया'),
              child: const Text('ठीक है'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, NewGranth g, List<PanelLeaf> leaves, Palette p) {
    final key = 'g:${g.id}';
    final busy = _busy.contains(key);
    final api = apiOf(context);
    Future<void> assign(String leaf, String msg) => _run(key, () async {
      await api.setGranth(g.id, leaf: leaf);
      await api.ackGranth(g.id);
    }, msg);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Tag('नया', color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.title.isEmpty ? g.id : g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (g.author.isNotEmpty) Text(g.author, style: TextStyle(color: p.subtext, fontSize: 12.5)),
            Text(
              '${g.pramanCount} प्रमाण • ${shortTs(g.firstSeen)}',
              style: TextStyle(color: p.subtext, fontSize: 12.5),
            ),
            if (g.suggestedLeaf.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'सुझाव: ${g.suggestedLabel.isEmpty ? g.suggestedLeaf : g.suggestedLabel}',
                  style: const TextStyle(color: AppColors.blue, fontSize: 13),
                ),
              ),
            const SizedBox(height: 4),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else
              Wrap(
                children: [
                  if (g.suggestedLeaf.isNotEmpty)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () => assign(g.suggestedLeaf, 'फ़ोल्डर तय — ड्राफ्ट में'),
                      child: const Text('सुझाव मानें'),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: leaves.isEmpty
                        ? null
                        : () async {
                            final k = await pickLeaf(context, leaves, title: g.title);
                            if (k != null) await assign(k, 'फ़ोल्डर तय — ड्राफ्ट में');
                          },
                    child: const Text('फ़ोल्डर चुनें'),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => assign('other', 'अन्य में रखा — ड्राफ्ट में'),
                    child: const Text('अन्य में रखें'),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => _run(key, () async {
                      await api.setGranth(g.id, hidden: true);
                      await api.ackGranth(g.id);
                    }, 'छिपाया — ड्राफ्ट में'),
                    child: const Text('छिपाएँ', style: TextStyle(color: AppColors.red)),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => _run(key, () => api.ackGranth(g.id), 'देख लिया'),
                    child: const Text('देख लिया'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
