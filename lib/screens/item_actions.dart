import 'package:flutter/cupertino.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../widgets/cards.dart';
import '../widgets/form_sheet.dart';
import '../widgets/links.dart';
import '../widgets/motion.dart';
import 'granth_form.dart';
import 'praman_form.dart';
import 'topic_form.dart';

// Shared action menus (long-press in lists, "…" in detail screens).

Future<bool> deleteTopicFlow(BuildContext context, Topic t) async {
  final app = AppScope.of(context);
  if (!await confirmDialog(context, title: 'यह विषय हटाएँ? / Delete this topic?', message: oneLine(t.title))) {
    return false;
  }
  final ok = await runWrite(() => app.api.deleteTopic(t.id), success: 'विषय हटाया गया / Topic deleted');
  if (ok) app.bump();
  return ok;
}

Future<bool> deleteGranthFlow(BuildContext context, Granth g) async {
  final app = AppScope.of(context);
  if (!await confirmDialog(context, title: 'यह ग्रंथ हटाएँ? / Delete this granth?', message: oneLine(g.title))) {
    return false;
  }
  final ok = await runWrite(() => app.api.deleteGranth(g.id), success: 'ग्रंथ हटाया गया / Granth deleted');
  if (ok) app.bump();
  return ok;
}

Future<bool> deletePramanFlow(BuildContext context, Praman p) async {
  final app = AppScope.of(context);
  if (!await confirmDialog(context, title: 'यह प्रमाण हटाएँ? / Delete this praman?', message: oneLine(p.title))) {
    return false;
  }
  final ok = await runWrite(() => app.api.deletePraman(p.id), success: 'प्रमाण हटाया गया / Praman deleted');
  if (ok) app.bump();
  return ok;
}

Future<void> toggleTopic(BuildContext context, Topic t) async {
  final app = AppScope.of(context);
  // Optimistic: flip the dot/label at once; the write (and refetch) syncs afterwards.
  final wasActive = app.activeOf('topic', t.id, t.isActive);
  app.setOptimisticActive('topic', t.id, !wasActive);
  final ok = await runWrite(
    () => app.api.setTopicActive(t, !wasActive),
    success: wasActive ? 'विषय छिपाया गया / Topic hidden' : 'विषय दिखाया गया / Topic visible',
  );
  if (ok) {
    app.bump();
    app.settleOptimisticActive('topic', t.id);
  } else {
    app.clearOptimisticActive('topic', t.id);
  }
}

Future<void> toggleGranth(BuildContext context, Granth g) async {
  final app = AppScope.of(context);
  // Optimistic: flip the dot/label at once; the write (and refetch) syncs afterwards.
  final wasActive = app.activeOf('granth', g.id, g.isActive);
  app.setOptimisticActive('granth', g.id, !wasActive);
  final ok = await runWrite(
    () => app.api.setGranthActive(g, !wasActive),
    success: wasActive ? 'ग्रंथ छिपाया गया / Granth hidden' : 'ग्रंथ दिखाया गया / Granth visible',
  );
  if (ok) {
    app.bump();
    app.settleOptimisticActive('granth', g.id);
  } else {
    app.clearOptimisticActive('granth', g.id);
  }
}

Future<void> togglePraman(BuildContext context, Praman p) async {
  final app = AppScope.of(context);
  // Optimistic: flip the dot/label at once; the write (and refetch) syncs afterwards.
  final wasActive = app.activeOf('praman', p.id, p.isActive);
  app.setOptimisticActive('praman', p.id, !wasActive);
  final ok = await runWrite(
    () => app.api.setPramanActive(p, !wasActive),
    success: wasActive ? 'प्रमाण छिपाया गया / Praman hidden' : 'प्रमाण दिखाया गया / Praman visible',
  );
  if (ok) {
    app.bump();
    app.settleOptimisticActive('praman', p.id);
  } else {
    app.clearOptimisticActive('praman', p.id);
  }
}

Future<void> moveTopicFlow(BuildContext context, Topic t) async {
  final app = AppScope.of(context);
  final n = await numberDialog(
    context,
    title: 'स्थान बदलें / Move to position',
    hint: 'वर्तमान / Current: ${t.position}',
    max: app.topics.isEmpty ? null : app.topics.length,
  );
  if (n == null || n == t.position) return;
  final ok = await runWrite(() => app.api.moveTopicTo(t, n), success: 'स्थान बदला गया / Position changed');
  if (ok) app.bump();
}

Future<void> moveGranthFlow(BuildContext context, Granth g) async {
  final app = AppScope.of(context);
  final n = await numberDialog(
    context,
    title: 'स्थान बदलें / Move to position',
    hint: 'वर्तमान / Current: ${g.position}',
    max: app.granths.isEmpty ? null : app.granths.length,
  );
  if (n == null || n == g.position) return;
  final ok = await runWrite(() => app.api.moveGranthTo(g, n), success: 'स्थान बदला गया / Position changed');
  if (ok) app.bump();
}

Future<void> favoriteFlow(BuildContext context, Praman p, {int? granthId}) async {
  final app = AppScope.of(context);
  final gid = granthId ?? p.granthId;
  if (gid == 0) return;
  final ok = await runWrite(
    () => app.api.setFavorite(pramanId: p.id, granthId: gid),
    success: 'प्रमाण ग्रंथ का डिफ़ॉल्ट बना / Praman is set as default for granth',
  );
  if (ok) app.bump();
}

void showTopicActions(BuildContext context, Topic t, {VoidCallback? onDeleted}) {
  showActions(
    context,
    title: oneLine(t.title),
    actions: [
      SheetAction('संपादित करें / Edit', CupertinoIcons.pencil, () => showTopicForm(context, topic: t)),
      SheetAction(
        t.isActive ? 'छिपाएँ / Hide (In-Active)' : 'दिखाएँ / Show (Active)',
        t.isActive ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
        () => toggleTopic(context, t),
      ),
      SheetAction(
        '+ प्रमाण जोड़ें / Add Praman',
        CupertinoIcons.add_circled,
        () => showPramanForm(context, topicId: t.id),
      ),
      SheetAction('स्थान बदलें / Move to position', CupertinoIcons.number, () => moveTopicFlow(context, t)),
      SheetAction('शेयर / Share', CupertinoIcons.share, () => shareItem('topic', t.id, t.title)),
      SheetAction('हटाएँ / Delete', CupertinoIcons.trash, () async {
        if (await deleteTopicFlow(context, t)) onDeleted?.call();
      }, destructive: true),
    ],
  );
}

void showGranthActions(BuildContext context, Granth g, {VoidCallback? onDeleted}) {
  showActions(
    context,
    title: oneLine(g.title),
    actions: [
      SheetAction('संपादित करें / Edit', CupertinoIcons.pencil, () => showGranthForm(context, granth: g)),
      SheetAction(
        g.isActive ? 'छिपाएँ / Hide (In-Active)' : 'दिखाएँ / Show (Active)',
        g.isActive ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
        () => toggleGranth(context, g),
      ),
      SheetAction(
        '+ प्रमाण जोड़ें / Add Praman',
        CupertinoIcons.add_circled,
        () => showPramanForm(context, granthId: g.id),
      ),
      if (g.pdfUrl.isNotEmpty)
        SheetAction('PDF खोलें / Open PDF', CupertinoIcons.doc_text, () => openExternal(g.pdfUrl)),
      SheetAction('स्थान बदलें / Move to position', CupertinoIcons.number, () => moveGranthFlow(context, g)),
      SheetAction('शेयर / Share', CupertinoIcons.share, () => shareItem('granth', g.id, g.title)),
      SheetAction('हटाएँ / Delete', CupertinoIcons.trash, () async {
        if (await deleteGranthFlow(context, g)) onDeleted?.call();
      }, destructive: true),
    ],
  );
}

void showPramanActions(BuildContext context, Praman p, {int? granthContext, VoidCallback? onDeleted}) {
  showActions(
    context,
    title: oneLine(p.title),
    actions: [
      SheetAction('संपादित करें / Edit', CupertinoIcons.pencil, () => showPramanForm(context, praman: p)),
      SheetAction(
        p.isActive ? 'छिपाएँ / Hide (In-Active)' : 'दिखाएँ / Show (Active)',
        p.isActive ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
        () => togglePraman(context, p),
      ),
      if ((granthContext ?? p.granthId) != 0 && !p.isFavorite)
        SheetAction(
          'ग्रंथ का डिफ़ॉल्ट बनाएँ / Set as granth default',
          CupertinoIcons.heart,
          () => favoriteFlow(context, p, granthId: granthContext),
        ),
      if (p.youtubeWatchUri != null)
        SheetAction(
          'YouTube खोलें / Open YouTube',
          CupertinoIcons.play_rectangle,
          () => openExternal(p.youtubeWatchUri.toString()),
        ),
      SheetAction('शेयर / Share', CupertinoIcons.share, () => shareItem('praman', p.id, p.title)),
      SheetAction('हटाएँ / Delete', CupertinoIcons.trash, () async {
        if (await deletePramanFlow(context, p)) onDeleted?.call();
      }, destructive: true),
    ],
  );
}
