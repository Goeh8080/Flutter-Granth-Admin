import '../core/api_client.dart';
import '../models/models.dart';

export '../core/api_client.dart';

/// One method per action of the web admin panel (see API_NOTES.md).
class GranthApi {
  GranthApi(this.client);
  final ApiClient client;

  // ---------- helpers ----------
  void _ensureOk(Map<String, dynamic> r, String fallback) {
    if (r['success'] == true) return;
    final msg = asStr(r['message'] ?? r['msg'] ?? r['error']);
    throw ApiException(msg.isNotEmpty ? msg : fallback);
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> r) {
    _ensureOk(r, 'डेटा लोड नहीं हुआ / Could not load data');
    return asMapList(r['data']);
  }

  // ---------- auth ----------
  Future<bool> login(String username, String password) async {
    await client.clearCookie();
    final r = await client.postJson('get_user', {'username': username, 'password': password}, requireLogin: false);
    final ok = r['success'] == true;
    if (!ok) await client.clearCookie();
    return ok;
  }

  Future<void> logout() async {
    try {
      await client.get('logout');
    } catch (_) {
      // ignore: logout body is not JSON on the web either
    } finally {
      await client.clearCookie();
    }
  }

  /// get_feedbacks is the one read action that enforces the session server-side.
  Future<bool> checkSession() async {
    if (!await client.hasCookie) return false;
    final r = await client.get('get_feedbacks');
    return r['success'] == true && r['isLogin'] != false;
  }

  // ---------- reads ----------
  Future<Stats> stats() async {
    final r = await client.get('get_stats');
    _ensureOk(r, 'आँकड़े लोड नहीं हुए / Could not load stats');
    return Stats.fromJson(asMap(r['data']));
  }

  Future<List<Topic>> topics({String search = '', bool onlyInactive = false}) async {
    final q = <String, String>{};
    if (search.trim().isNotEmpty) q['topic'] = search.trim();
    if (onlyInactive) {
      q
        ..clear()
        ..['disabled'] = '1';
    }
    final r = await client.get('get_topics', query: q);
    // the web treats anything but success:false as data
    if (r['success'] == false) _ensureOk(r, 'विषय लोड नहीं हुए / Could not load topics');
    return asMapList(r['data']).map(Topic.fromJson).toList();
  }

  Future<Topic> topic(int id) async {
    final r = await client.get('get_topic', query: {'topic': '$id'});
    _ensureOk(r, 'विषय नहीं मिला / Topic not found');
    return Topic.fromJson(asMap(r['data']));
  }

  Future<List<Granth>> granths({String search = ''}) async {
    final r = await client.get('get_granths', query: search.trim().isEmpty ? null : {'granth': search.trim()});
    return _list(r).map(Granth.fromJson).toList();
  }

  Future<Granth> granth(int id) async {
    final r = await client.get('get_granth', query: {'granth': '$id'});
    _ensureOk(r, 'ग्रंथ नहीं मिला / Granth not found');
    return Granth.fromJson(asMap(r['data']));
  }

  /// Exactly one filter is sent, as in script.js (later ones win there:
  /// id > youtube > granthId > topicId > search).
  Future<List<Praman>> pramans({String search = '', int? topicId, int? granthId, bool youtube = false, int? id}) async {
    Map<String, String>? q;
    if (search.trim().isNotEmpty) q = {'praman': search.trim()};
    if (topicId != null) q = {'topicId': '$topicId'};
    if (granthId != null) q = {'granthId': '$granthId'};
    if (youtube) q = {'is_youtube': '1'};
    if (id != null) q = {'id': '$id'};
    final r = await client.get('get_pramans', query: q);
    return _list(r).map(Praman.fromJson).toList();
  }

  Future<Praman> praman(int id) async {
    final r = await client.get('get_praman', query: {'praman': '$id'});
    _ensureOk(r, 'प्रमाण नहीं मिला / Praman not found');
    return Praman.fromJson(asMap(r['data']));
  }

  Future<List<FeedbackItem>> feedbacks() async {
    final r = await client.get('get_feedbacks', requireLogin: true);
    return _list(r).map(FeedbackItem.fromJson).toList();
  }

  // ---------- writes (formats copied from script.js; never exercised in tests) ----------
  Future<void> saveTopic({int? id, required String title, String description = '', required bool isActive}) async {
    final r = await client.postJson('create_topic', {
      'title': title,
      'isActive': isActive ? '1' : '0',
      'description': description,
      'formType': id == null ? 'add' : 'edit',
      'id': id == null ? '' : '$id',
    });
    _ensureOk(r, 'विषय सहेजा नहीं गया / Topic not saved');
  }

  Future<void> deleteTopic(int id) => _getWrite('delete_topic', id, 'विषय हटाया नहीं गया / Topic not deleted');
  Future<void> deleteGranth(int id) => _getWrite('delete_granth', id, 'ग्रंथ हटाया नहीं गया / Granth not deleted');
  Future<void> deletePraman(int id) => _getWrite('delete_praman', id, 'प्रमाण हटाया नहीं गया / Praman not deleted');
  Future<void> deleteFeedback(int id) =>
      _getWrite('delete_feedback', id, 'फीडबैक हटाया नहीं गया / Feedback not deleted');

  Future<void> _getWrite(String action, int id, String err) async {
    final r = await client.get(action, query: {'id': '$id'}, requireLogin: true);
    // The web panel ignores the delete response; only fail on an explicit false.
    if (r['success'] == false) _ensureOk(r, err);
  }

  Future<void> saveGranth({
    int? id,
    required String title,
    required String author,
    String description = '',
    String pdfUrl = '',
    required bool isActive,
    String? imagePath,
    String? editorImagePath,
  }) async {
    final r = await client.postMultipart(
      'create_granth',
      {
        'title': title,
        'author': author,
        'description': description,
        'granthPDF': pdfUrl,
        'formType': id == null ? 'add' : 'edit',
        'id': id == null ? '' : '$id',
        'isActive': isActive ? '1' : '0',
      },
      files: [
        if (imagePath != null) UploadFile('image', imagePath),
        if (editorImagePath != null) UploadFile('editorImage', editorImagePath),
      ],
    );
    _ensureOk(r, 'ग्रंथ सहेजा नहीं गया / Granth not saved');
  }

  Future<void> savePraman({
    int? id,
    required String title,
    required bool isActive,
    String description = '',
    required int topicId,
    required int granthId,
    String chapterNumber = '',
    String pageNumber = '',
    String youtubeUrl = '',
    String youtubeDesc = '',
    String youtubeStart = '',
    String? imagePath,
  }) async {
    final r = await client.postMultipart(
      'create_praman',
      {
        'title': title,
        'isActive': isActive ? '1' : '0',
        'description': description,
        'topic_id': '$topicId',
        'granth_id': '$granthId',
        'chapterNumber': chapterNumber,
        'youtube_url': youtubeUrl,
        'youtube_desc': youtubeDesc,
        'youtube_start': youtubeStart,
        'pageNumber': pageNumber,
        'formType': id == null ? 'add' : 'edit',
        'id': id == null ? '' : '$id',
      },
      files: [if (imagePath != null) UploadFile('image', imagePath)],
    );
    _ensureOk(r, 'प्रमाण सहेजा नहीं गया / Praman not saved');
  }

  /// Toggle visibility by re-submitting the full edit payload (no dedicated endpoint exists).
  Future<void> setTopicActive(Topic t, bool active) =>
      saveTopic(id: t.id, title: t.title, description: t.description, isActive: active);

  Future<void> setGranthActive(Granth g, bool active) => saveGranth(
    id: g.id,
    title: g.title,
    author: g.author,
    description: g.description,
    pdfUrl: g.pdfUrl,
    isActive: active,
  );

  Future<void> setPramanActive(Praman p, bool active) => savePraman(
    id: p.id,
    title: p.title,
    isActive: active,
    description: p.description,
    topicId: p.topicId,
    granthId: p.granthId,
    chapterNumber: '${p.chapterNumber}',
    pageNumber: '${p.pageNumber}',
    youtubeUrl: p.youtubeUrl,
    youtubeDesc: p.youtubeDesc,
    youtubeStart: '${p.youtubeStart}',
  );

  /// topic-sort.php: `{"topics": [full objects in new order]}`
  Future<void> saveTopicOrder(List<Topic> ordered) async {
    final r = await client.postJson('update_topic_order', {'topics': ordered.map((t) => t.raw).toList()});
    _ensureOk(r, 'क्रम सहेजा नहीं गया / Order not saved');
  }

  /// granth-sort.php: `{"granths": [full objects in new order]}` (web ignores the response)
  Future<void> saveGranthOrder(List<Granth> ordered) async {
    final r = await client.postJson('update_granth_order', {'granths': ordered.map((g) => g.raw).toList()});
    if (r['success'] == false) _ensureOk(r, 'क्रम सहेजा नहीं गया / Order not saved');
  }

  Future<void> moveTopicTo(Topic t, int newPosition) async {
    final r = await client.postJson('update_topic_orderByNumber', {
      'topicId': t.id,
      'currentPostion': t.position,
      'newPosition': '$newPosition',
    });
    _ensureOk(r, 'स्थान नहीं बदला / Position not changed');
  }

  Future<void> moveGranthTo(Granth g, int newPosition) async {
    final r = await client.postJson('update_granth_orderByNumber', {
      'granthId': g.id,
      'currentPostion': g.position,
      'newPosition': '$newPosition',
    });
    _ensureOk(r, 'स्थान नहीं बदला / Position not changed');
  }

  Future<void> setFavorite({required int pramanId, required int granthId}) async {
    final r = await client.postJson('set_pramanAsFavorate', {'praman': '$pramanId', 'granthId': '$granthId'});
    _ensureOk(r, 'डिफ़ॉल्ट सेट नहीं हुआ / Could not set default');
  }

  Future<void> createFeedback({
    required String name,
    required String mob,
    required String description,
    int? topicId,
    int? granthId,
    int? pramanId,
    String? imagePath,
  }) async {
    final r = await client.postMultipart(
      'create_feedback',
      {
        'description': description,
        'topic_id': topicId == null ? '' : '$topicId',
        'granth_id': granthId == null ? '' : '$granthId',
        'praman_id': pramanId == null ? '' : '$pramanId',
        'mob': mob,
        'fname': name,
      },
      files: [if (imagePath != null) UploadFile('image', imagePath)],
      requireLogin: false,
    );
    _ensureOk(r, 'फीडबैक सहेजा नहीं गया / Feedback not saved');
  }
}
