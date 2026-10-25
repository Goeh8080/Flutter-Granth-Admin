import 'package:flutter/material.dart';

import '../admin_ui/admin_data.dart';
import '../state/router.dart';
import '../theme/colors.dart';
import 'common.dart';

/// The announcement card at the top of the admin Dashboard. It shows the draft's
/// announcement exactly as readers will see it and has NO close button: it stays until the
/// admin removes it (Admin Panel → घोषणा). `pinned` is shown as a label; a pinned
/// announcement cannot be dismissed by readers either.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AdminData.I,
    builder: (context, _) {
      final a = AdminData.I.settings?.announcement;
      final on = a != null && a.enabled && a.text.trim().isNotEmpty;
      if (!on) {
        return Padding(
          key: const ValueKey('announcement-empty'),
          padding: const EdgeInsets.only(bottom: 16),
          child: Pressable(
            onTap: () => AppNav.I.go('#/admin'),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: GColors.paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: GColors.creamDark, width: 1.2),
              ),
              child: Row(
                children: [
                  GIcon('megaphone', size: 20, color: GColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'कोई घोषणा नहीं — पिन की हुई घोषणा जोड़ें',
                      style: GText.sans(
                        size: 14,
                        weight: FontWeight.w600,
                        color: GColors.muted,
                      ),
                    ),
                  ),
                  GIcon('chevron-right', size: 18, color: GColors.muted),
                ],
              ),
            ),
          ),
        );
      }
      final (bg, border, fg, icon) = switch (a.level) {
        'critical' => (
          const Color(0xFFFBE9E7),
          const Color(0xFFD4574A),
          const Color(0xFF8E1B10),
          'alert-triangle',
        ),
        'warn' => (
          const Color(0xFFFFF4DC),
          GColors.gold,
          GColors.brown,
          'alert-triangle',
        ),
        _ => (GColors.pillTopic, GColors.saffron, GColors.brown, 'bell'),
      };
      return Padding(
        key: const ValueKey('announcement'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Pressable(
          onTap: () => AppNav.I.go('#/admin'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GIcon('pin', size: 16, color: fg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        a.pinned
                            ? 'पिन की हुई घोषणा / Pinned'
                            : 'घोषणा / Not pinned — readers can dismiss',
                        key: const ValueKey('announcement-state'),
                        style: GText.sans(
                          size: 12,
                          weight: FontWeight.w800,
                          color: fg,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (a.expiresAt != null)
                      Text(
                        'समाप्ति ${a.expiresAt!.split('T').first}',
                        style: GText.sans(
                          size: 11,
                          weight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: GIcon(icon, size: 20, color: fg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.text,
                        style: GText.sans(
                          size: 14.5,
                          weight: FontWeight.w600,
                          color: fg,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
