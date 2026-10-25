import 'package:flutter/material.dart';

import '../admin/widgets/form_sheet.dart' show runWrite;
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_data.dart';

/// A small on/off switch in the app's colours (no Material Switch / ink / blur).
class AdminSwitch extends StatelessWidget {
  const AdminSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: Pressable(
      onTap: onChanged == null || busy ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? GColors.maroon : GColors.creamDark,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: GColors.paper,
            shape: BoxShape.circle,
            border: busy ? Border.all(color: GColors.saffron, width: 2) : null,
          ),
        ),
      ),
    ),
  );
}

/// "तत्त्व AI चालू / बंद": writes `ai_enabled` of the draft settings (goes live on publish).
class AiToggleCard extends StatefulWidget {
  const AiToggleCard({super.key});
  @override
  State<AiToggleCard> createState() => _AiToggleCardState();
}

class _AiToggleCardState extends State<AiToggleCard> {
  bool _busy = false;

  Future<void> _set(bool v) async {
    setState(() => _busy = true);
    await runWrite(
      () => AdminData.I.saveSettings(aiEnabled: v),
      success: v
          ? 'AI चालू (ड्राफ्ट) / AI on (draft)'
          : 'AI बंद (ड्राफ्ट) / AI off (draft)',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AdminData.I,
    builder: (context, _) {
      final s = AdminData.I.settings;
      final on = s?.aiEnabled ?? true;
      return GCard(
        key: const ValueKey('ai-toggle'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBox(
              tone: Tone.saffron,
              icon: 'sparkles',
              size: 40,
              radius: 12,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'पाठकों के लिए तत्त्व AI',
                    style: GText.sans(
                      size: 15,
                      weight: FontWeight.w800,
                      color: GColors.maroon,
                    ),
                  ),
                  Text(
                    s == null
                        ? 'सेटिंग लोड नहीं हुई'
                        : (on
                              ? 'चालू — पाठक AI से पूछ सकते हैं'
                              : 'बंद — पाठकों को "अभी बंद है" दिखेगा'),
                    style: GText.sans(
                      size: 12.5,
                      color: GColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            AdminSwitch(
              value: on,
              busy: _busy,
              onChanged: s == null ? null : _set,
            ),
          ],
        ),
      );
    },
  );
}
