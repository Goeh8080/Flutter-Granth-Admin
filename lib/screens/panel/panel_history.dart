import 'package:flutter/cupertino.dart';

import '../../models/panel_models.dart';
import '../../services/panel_api.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/motion.dart';
import '../../widgets/toast.dart';
import 'panel_widgets.dart';

/// इतिहास: published versions, diff vs the previous one, and rollback.
class PanelHistoryScreen extends StatelessWidget {
  const PanelHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<PanelVersions>(
      title: 'इतिहास / History',
      previousPageTitle: 'कंट्रोल',
      load: (api) => api.versions(),
      builder: (context, v, reload) => [
        PadSliver(
          child: v.items.isEmpty
              ? const SliverFillRemaining(hasScrollBody: false, child: MessageView(icon: CupertinoIcons.clock, title: 'अभी कोई वर्ज़न नहीं'))
              : SliverList.builder(
                  itemCount: v.items.length,
                  itemBuilder: (context, i) {
                    final it = v.items[i];
                    final live = it.version == v.current;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PressableGlass(
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        onTap: () => pushPanel(context, PanelVersionScreen(version: it.version, live: live)),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: (live ? AppColors.green : AppColors.saffron).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('v${it.version}', style: TextStyle(color: live ? AppColors.green : AppColors.saffron, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.note.isEmpty ? _kind(it.kind) : '${_kind(it.kind)} • ${it.note}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.text, fontSize: 14.5),
                                  ),
                                  Text('${shortTs(it.createdAt)} • ${it.author}${live ? ' • लाइव' : ''}', style: TextStyle(color: p.subtext, fontSize: 12)),
                                ],
                              ),
                            ),
                            Icon(CupertinoIcons.chevron_right, size: 15, color: p.subtext),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _kind(String k) => switch (k) {
    'bootstrap' => 'शुरुआती',
    'publish' => 'प्रकाशन',
    'rollback' => 'रोलबैक',
    _ => k,
  };
}

/// One version: what changed vs the one before, with a Rollback button.
class PanelVersionScreen extends StatefulWidget {
  const PanelVersionScreen({super.key, required this.version, required this.live});
  final int version;
  final bool live;
  @override
  State<PanelVersionScreen> createState() => _PanelVersionScreenState();
}

class _PanelVersionScreenState extends State<PanelVersionScreen> {
  bool _busy = false;

  Future<void> _rollback() async {
    final panel = panelOf(context);
    final ok = await confirmDialog(
      context,
      title: 'v${widget.version} पर रोलबैक?',
      message: 'v${widget.version} की सामग्री से एक नया (ऊँचा) वर्ज़न बनेगा और यूज़र ऐप को मिलेगा। मौजूदा अप्रकाशित ड्राफ्ट बना रहेगा।',
      confirm: 'रोलबैक / Rollback',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await panel.api.rollback(widget.version, note: 'rollback from app');
      panel.bump();
      showToast('रोलबैक हुआ → नया v${r.version}');
      if (mounted) Navigator.of(context).maybePop();
    } on PanelApiException catch (e) {
      showError(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PanelPage<(PanelVersionDetail, Map<String, String>)>(
      title: 'v${widget.version}',
      previousPageTitle: 'इतिहास',
      load: (api) async {
        final d = await api.version(widget.version);
        var labels = <String, String>{};
        try {
          labels = leafLabelMap((await api.structure()).leaves);
        } on PanelApiException {
          // labels are optional
        }
        return (d, labels);
      },
      builder: (context, data, reload) {
        final d = data.$1;
        return [
          PadSliver(
            child: SliverList(
              delegate: SliverChildListDelegate([
                Glass(
                  radius: 18,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.info.kind} • ${shortTs(d.info.createdAt)} • ${d.info.author}', style: TextStyle(color: p.text, fontSize: 14)),
                      if (d.info.note.isNotEmpty) Text(d.info.note, style: TextStyle(color: p.subtext, fontSize: 13)),
                      Text('v${d.against} से तुलना • ${d.info.bytes} bytes', style: TextStyle(color: p.subtext, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DiffView(diff: d.diff, leafLabels: data.$2),
                const SizedBox(height: 18),
                if (widget.live)
                  const EmptyNote('यह अभी लाइव वर्ज़न है', icon: CupertinoIcons.checkmark_circle)
                else
                  PrimaryButton(label: 'इस वर्ज़न पर रोलबैक', icon: CupertinoIcons.arrow_uturn_left, busy: _busy, onPressed: _rollback),
              ]),
            ),
          ),
        ];
      },
    );
  }
}
