import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import 'common.dart';

String oneLine(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

class TopicCard extends StatelessWidget {
  const TopicCard({
    super.key,
    required this.topic,
    required this.index,
    required this.total,
    this.onTap,
    this.onLongPress,
  });
  final Topic topic;
  final int index, total;
  final VoidCallback? onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final t = topic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableGlass(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [AppColors.saffron.withValues(alpha: 0.9), AppColors.maroon.withValues(alpha: 0.85)],
                ),
              ),
              child: Text(
                '${t.position}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'topic-title-${t.id}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        oneLine(t.title),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: p.text, height: 1.45),
                      ),
                    ),
                  ),
                  if (t.description.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        oneLine(t.description),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.subtext, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Tag('${t.pramanCount} प्रमाण', icon: CupertinoIcons.photo_on_rectangle),
                      Tag('${index + 1}/$total', color: AppColors.maroon),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 6), child: StatusDot(t.isActive)),
          ],
        ),
      ),
    );
  }
}

class GranthCard extends StatelessWidget {
  const GranthCard({
    super.key,
    required this.granth,
    required this.index,
    required this.total,
    this.onTap,
    this.onLongPress,
  });
  final Granth granth;
  final int index, total;
  final VoidCallback? onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final g = granth;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableGlass(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(tag: 'granth-img-${g.id}', child: NetImage(g.imageUrl, width: 70, height: 92, radius: 12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${g.position}. ${oneLine(g.title)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: p.text, height: 1.45),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(padding: const EdgeInsets.only(top: 6), child: StatusDot(g.isActive)),
                    ],
                  ),
                  if (g.author.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '✍️ ${g.author.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.saffronDeep,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Tag('${g.pramanCount} प्रमाण', icon: CupertinoIcons.photo_on_rectangle),
                      if (g.pdfUrl.isNotEmpty) const Tag('PDF', icon: CupertinoIcons.doc_text, color: AppColors.blue),
                      if (g.editorImagePath.isNotEmpty)
                        const Tag('विवरण', icon: CupertinoIcons.doc_richtext, color: AppColors.maroon),
                      Tag('${index + 1}/$total', color: AppColors.maroon),
                    ],
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

class PramanCard extends StatelessWidget {
  const PramanCard({
    super.key,
    required this.praman,
    required this.index,
    required this.total,
    this.onTap,
    this.onLongPress,
    this.heroPrefix = 'praman',
  });
  final Praman praman;
  final int index, total;
  final VoidCallback? onTap, onLongPress;
  final String heroPrefix;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final m = praman;
    final thumb = m.imageUrl ?? m.youtubeThumb ?? m.granthImageUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableGlass(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(tag: '$heroPrefix-img-${m.id}', child: NetImage(thumb, width: 84, height: 84, radius: 14)),
                if (m.hasYoutube)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      CupertinoIcons.play_circle_fill,
                      color: Colors.white,
                      size: 22,
                      shadows: [Shadow(blurRadius: 6)],
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          oneLine(m.title),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text, height: 1.45),
                        ),
                      ),
                      if (m.isFavorite)
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 2),
                          child: Icon(CupertinoIcons.heart_fill, color: AppColors.red, size: 16),
                        ),
                      const SizedBox(width: 6),
                      Padding(padding: const EdgeInsets.only(top: 6), child: StatusDot(m.isActive)),
                    ],
                  ),
                  if (m.description.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        oneLine(m.description),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.subtext, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (m.granthTitle.isNotEmpty) Tag(oneLine(m.granthTitle), icon: CupertinoIcons.book),
                      if (m.pageNumber > 0) Tag('पृ. ${m.pageNumber}', color: AppColors.blue),
                      Tag('${index + 1}/$total', color: AppColors.maroon),
                    ],
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
