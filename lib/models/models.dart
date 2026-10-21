import 'parse.dart';

export 'parse.dart';

const String kSiteBase = 'https://granth.wnmsolutions.com';

/// Turns a server-relative path such as `uploads/x.jpg` or `/granths/x.jpg` into a full URL.
String? mediaUrl(String? path) {
  if (path == null) return null;
  final p = path.trim();
  if (p.isEmpty) return null;
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  return '$kSiteBase/${p.startsWith('/') ? p.substring(1) : p}';
}

class Stats {
  final int topics, granths, pramans;
  const Stats({this.topics = 0, this.granths = 0, this.pramans = 0});
  factory Stats.fromJson(Map<String, dynamic> j) =>
      Stats(topics: asInt(j['topics']), granths: asInt(j['granths']), pramans: asInt(j['pramans']));
}

class Topic {
  final int id;
  final String title, description, createdAt;
  final int position, pramanCount, granthCount;
  final bool isActive;
  final Map<String, dynamic> raw;
  const Topic({
    required this.id,
    required this.title,
    this.description = '',
    this.position = 0,
    this.pramanCount = 0,
    this.granthCount = 0,
    this.isActive = true,
    this.createdAt = '',
    this.raw = const {},
  });
  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
    id: asInt(j['id']),
    title: asStr(j['title']),
    description: asStr(j['description']),
    position: asInt(j['position']),
    pramanCount: asInt(j['praman_count']),
    granthCount: asInt(j['granth_count']),
    isActive: asFlag(j['isActive']),
    createdAt: asStr(j['created_at']),
    raw: j,
  );
}

class Granth {
  final int id;
  final String title, author, description, pdfUrl, imagePath, editorImagePath, createdAt;
  final int position, pramanCount;
  final int? topicId;
  final bool isActive;
  final Map<String, dynamic> raw;
  const Granth({
    required this.id,
    required this.title,
    this.author = '',
    this.description = '',
    this.pdfUrl = '',
    this.imagePath = '',
    this.editorImagePath = '',
    this.position = 0,
    this.pramanCount = 0,
    this.topicId,
    this.isActive = true,
    this.createdAt = '',
    this.raw = const {},
  });
  String? get imageUrl => mediaUrl(imagePath);
  String? get editorImageUrl => mediaUrl(editorImagePath);
  factory Granth.fromJson(Map<String, dynamic> j) => Granth(
    id: asInt(j['id']),
    title: asStr(j['title']),
    author: asStr(j['author']),
    description: asStr(j['description']),
    pdfUrl: asStr(j['granthURL']).trim(),
    imagePath: asStr(j['imagePath']),
    editorImagePath: asStr(j['editorImagePath']),
    position: asInt(j['position']),
    pramanCount: asInt(j['pramanCount']),
    topicId: j['topic_id'] == null ? null : asInt(j['topic_id']),
    isActive: asFlag(j['isActive']),
    createdAt: asStr(j['created_at']),
    raw: j,
  );
}

class Praman {
  final int id, topicId, granthId, pageNumber, chapterNumber, youtubeStart;
  final String title, description, imagePath, youtubeUrl, youtubeDesc;
  final String topicTitle, granthTitle, granthImagePath, editorImagePath, createdAt;
  final bool isActive, isFavorite;
  final Map<String, dynamic> raw;
  const Praman({
    required this.id,
    required this.title,
    this.description = '',
    this.topicId = 0,
    this.granthId = 0,
    this.pageNumber = 0,
    this.chapterNumber = 0,
    this.imagePath = '',
    this.youtubeUrl = '',
    this.youtubeStart = 0,
    this.youtubeDesc = '',
    this.topicTitle = '',
    this.granthTitle = '',
    this.granthImagePath = '',
    this.editorImagePath = '',
    this.isActive = true,
    this.isFavorite = false,
    this.createdAt = '',
    this.raw = const {},
  });
  String? get imageUrl => mediaUrl(imagePath);
  String? get granthImageUrl => mediaUrl(granthImagePath);
  String? get editorImageUrl => mediaUrl(editorImagePath);
  bool get hasYoutube => youtubeUrl.trim().isNotEmpty;
  String get youtubeId => extractYoutubeId(youtubeUrl);
  String? get youtubeThumb => hasYoutube ? 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg' : null;
  Uri? get youtubeWatchUri => hasYoutube
      ? Uri.parse(
          'https://www.youtube.com/watch?v=$youtubeId'
          '${youtubeStart > 0 ? '&t=${youtubeStart}s' : ''}',
        )
      : null;

  factory Praman.fromJson(Map<String, dynamic> j) => Praman(
    id: asInt(j['id']),
    title: asStr(j['title']),
    description: asStr(j['description']),
    topicId: asInt(j['topic_id']),
    granthId: asInt(j['granth_id']),
    pageNumber: asInt(j['pageNumber']),
    chapterNumber: asInt(j['chapterNumber']),
    imagePath: asStr(j['image_path']),
    youtubeUrl: asStr(j['youtube_url']),
    youtubeStart: asInt(j['youtube_start']),
    youtubeDesc: asStr(j['youtube_desc']),
    topicTitle: asStr(j['topic_title']),
    granthTitle: asStr(j['granth_title']),
    granthImagePath: asStr(j['granth_image']),
    editorImagePath: asStr(j['editorImagePath']),
    isActive: asFlag(j['isActive']),
    isFavorite: asFlag(j['is_favorate']),
    createdAt: asStr(j['created_at']),
    raw: j,
  );
}

class FeedbackItem {
  final int id, topicId, granthId, pramanId, status;
  final String name, description, mob, image, topicTitle, granthTitle, pramanTitle;
  const FeedbackItem({
    required this.id,
    this.name = '',
    this.description = '',
    this.mob = '',
    this.image = '',
    this.topicId = 0,
    this.granthId = 0,
    this.pramanId = 0,
    this.status = 0,
    this.topicTitle = '',
    this.granthTitle = '',
    this.pramanTitle = '',
  });
  String? get imageUrl => mediaUrl(image);
  factory FeedbackItem.fromJson(Map<String, dynamic> j) => FeedbackItem(
    id: asInt(j['id']),
    name: asStr(j['name']),
    description: asStr(j['description']),
    mob: asStr(j['mob']),
    image: asStr(j['image']),
    topicId: asInt(j['topic_id']),
    granthId: asInt(j['granth_id']),
    pramanId: asInt(j['praman_id']),
    status: asInt(j['status']),
    topicTitle: asStr(j['topic_title']),
    granthTitle: asStr(j['granth_title']),
    pramanTitle: asStr(j['praman_title']),
  );
}

/// Accepts a bare video id ("HLhZeRregP0") or any common YouTube URL form.
String extractYoutubeId(String input) {
  final s = input.trim();
  if (s.isEmpty) return '';
  final patterns = [
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{6,})'),
    RegExp(r'[?&]v=([A-Za-z0-9_-]{6,})'),
    RegExp(r'/(?:embed|shorts|live)/([A-Za-z0-9_-]{6,})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) return m.group(1)!;
  }
  return s;
}
