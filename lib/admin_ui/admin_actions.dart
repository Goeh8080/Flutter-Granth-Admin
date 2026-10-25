import 'package:flutter/material.dart';

import '../admin/screens/granth_form.dart';
import '../admin/screens/item_actions.dart';
import '../admin/screens/praman_form.dart';
import '../admin/screens/topic_form.dart';
import '../admin/screens/panel/panel_folders.dart';
import '../admin/screens/panel/panel_widgets.dart' show pushPanel;
import '../admin/widgets/form_sheet.dart' show runWrite;
import '../models/models.dart' as u;
import '../models/structure.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'admin_data.dart';
import 'folder_picker.dart';

/// The admin-only buttons shared by the Granth / Topic / Pramaan cards. Every write goes
/// through the existing admin flows (`item_actions.dart`) or [AdminData]; every destructive
/// one asks first in the confirmPop style.

// ---------------------------------------------------------------- granth

void editGranth(BuildContext context, u.Granth g) {
  final w = AdminData.I.wGranth(g.id);
  if (w != null) showGranthForm(context, granth: w);
}

Future<void> removeGranth(BuildContext context, u.Granth g) async {
  final w = AdminData.I.wGranth(g.id);
  if (w != null) await deleteGranthFlow(context, w);
}

/// Show / hide in the reader app: control-server `hidden_granth_ids` (a draft until published).
Future<void> toggleGranthHidden(BuildContext context, u.Granth g) async {
  final hide = !AdminData.I.isHidden(g.id);
  await runWrite(
    () => AdminData.I.setHidden([g.id], hide),
    success: hide
        ? 'ग्रंथ छिपाया (ड्राफ्ट) / Granth hidden (draft)'
        : 'ग्रंथ दिखाया (ड्राफ्ट) / Granth shown (draft)',
  );
}

/// Pick the folder (leaf group) a granth sits in: writes the granth's `leaf` override.
Future<void> pickFolder(BuildContext context, u.Granth g) async {
  final data = AdminData.I;
  final current = data.index.placements[g.id]?.key ?? kOtherId;
  final index = data.index;
  final picked = await showFolderPicker(
    context,
    structure: data.structure,
    granthTitle: g.title,
    current: current,
    countFor: (path) => switch (path) {
      [final r] when r == kOtherId => index.other.length,
      [final r] => index.inReligion(r).length,
      [final r, final gr] => index.inGroup(r, gr).length,
      [final r, final gr, final sub] => index.inGroup(r, gr, sub).length,
      _ => 0,
    },
  );
  if (picked == null || picked == current) return;
  await runWrite(
    () => AdminData.I.setLeaf(g.id, picked),
    success: 'फ़ोल्डर बदला (ड्राफ्ट) / Folder set (draft)',
  );
}

/// Folder editor (create / rename / icon / delete / reorder) opened at [path].
void editFolders(
  BuildContext context, {
  List<String> path = const [],
  bool add = false,
}) => pushPanel(context, PanelFoldersScreen(initialPath: path, startAdd: add));

// ---------------------------------------------------------------- topic / praman

void addPraman(BuildContext context, {int? topicId, int? granthId}) =>
    showPramanForm(context, topicId: topicId, granthId: granthId);

void editTopic(BuildContext context, u.Topic t) {
  final w = AdminData.I.wTopic(t.id);
  if (w != null) showTopicForm(context, topic: w);
}

Future<void> removeTopic(BuildContext context, u.Topic t) async {
  final w = AdminData.I.wTopic(t.id);
  if (w != null) await deleteTopicFlow(context, w);
}

Future<void> toggleTopicHidden(BuildContext context, u.Topic t) async {
  final w = AdminData.I.wTopic(t.id);
  if (w != null) await toggleTopic(context, w);
}

void editPraman(BuildContext context, u.Praman p) {
  final w = AdminData.I.wPraman(p.id);
  if (w != null) showPramanForm(context, praman: w);
}

Future<void> removePraman(BuildContext context, u.Praman p) async {
  final w = AdminData.I.wPraman(p.id);
  if (w != null) await deletePramanFlow(context, w);
}

Future<void> togglePramanHidden(BuildContext context, u.Praman p) async {
  final w = AdminData.I.wPraman(p.id);
  if (w != null) await togglePraman(context, w);
}

// ---------------------------------------------------------------- shared widgets

/// One small admin action pill; [danger] draws it in the maroon "destructive" tone.
class AdminPill extends StatelessWidget {
  const AdminPill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
    this.fontSize = 12,
    this.height = 34,
  });
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool danger;
  final double fontSize;
  final double height;
  @override
  Widget build(BuildContext context) => Pill(
    label: label,
    icon: icon,
    tone: danger ? PillTone.maroon : PillTone.plain,
    onTap: onTap,
    minHeight: height,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    fontSize: fontSize,
    weight: FontWeight.w700,
    iconSize: 14,
  );
}

/// Small "hidden" badge.
class HiddenBadge extends StatelessWidget {
  const HiddenBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: GColors.maroon,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GIcon('eye-off', size: 12, color: GColors.paper),
        const SizedBox(width: 4),
        Text(
          'छिपा / Hidden',
          style: GText.sans(
            size: 11,
            weight: FontWeight.w700,
            color: GColors.paper,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

/// A horizontal row of sort chips (the first is the default).
class SortChips<T> extends StatelessWidget {
  const SortChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: options.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Center(
            child: Row(
              children: [
                GIcon('arrow-up-down', size: 14, color: GColors.muted),
                const SizedBox(width: 6),
              ],
            ),
          );
        }
        final o = options[i - 1];
        return Pill(
          label: o.$2,
          tone: o.$1 == value ? PillTone.maroon : PillTone.plain,
          onTap: () => onChanged(o.$1),
          minHeight: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          fontSize: 13,
          weight: FontWeight.w700,
        );
      },
    ),
  );
}
