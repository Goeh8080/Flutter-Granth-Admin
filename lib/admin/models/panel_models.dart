// Typed models for the Granth control server (Cloudflare Worker `granth-admin`).
// Shapes follow CONTRACT.md §3. Every parser is defensive: a missing or oddly typed field
// falls back to a default instead of throwing, so a newer server never crashes the app.

int pInt(Object? v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String)
    return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt() ?? d;
  return d;
}

double pDouble(Object? v, [double d = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? d;
  return d;
}

String pStr(Object? v, [String d = '']) {
  if (v == null) return d;
  if (v is String) return v;
  return v.toString();
}

String? pStrN(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool pBool(Object? v, [bool d = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return d;
}

Map<String, dynamic> pMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<T> pList<T>(Object? v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) {
      try {
        out.add(f(Map<String, dynamic>.from(e)));
      } catch (_) {
        // skip one malformed row rather than failing the whole list
      }
    }
  }
  return out;
}

List<String> pStrList(Object? v) =>
    v is List ? [for (final e in v) pStr(e)] : const [];

// ---------------------------------------------------------------- session / me

class PanelLogin {
  final String token;
  final int expiresIn;
  final String username;
  const PanelLogin({
    required this.token,
    required this.expiresIn,
    required this.username,
  });
  factory PanelLogin.fromJson(Map<String, dynamic> j) => PanelLogin(
    token: pStr(j['token']),
    expiresIn: pInt(j['expires_in'], 86400),
    username: pStr(j['username'], 'goutam'),
  );
}

class PanelMe {
  final String username;
  final String auth;
  final int version;
  final bool hasDraft;
  final int baseVersion;
  final int nextVersion;

  /// `owner` or `admin` (contract 3.3 `/me`).
  final String role;
  final bool canManageAdmins;
  const PanelMe({
    required this.username,
    required this.auth,
    required this.version,
    required this.hasDraft,
    required this.baseVersion,
    required this.nextVersion,
    this.role = 'admin',
    this.canManageAdmins = false,
  });
  factory PanelMe.fromJson(Map<String, dynamic> j) {
    final role = pStr(j['role'], 'admin');
    return PanelMe(
      username: pStr(j['username']),
      auth: pStr(j['auth']),
      version: pInt(j['version']),
      hasDraft: pBool(j['has_draft']),
      baseVersion: pInt(j['base_version']),
      nextVersion: pInt(j['next_version']),
      role: role,
      canManageAdmins: pBool(j['can_manage_admins'], role == 'owner'),
    );
  }
  bool get isOwner => role == 'owner';
}

class PanelSession {
  final String sid, client, kind, createdAt, lastSeen;
  final bool current;
  const PanelSession({
    required this.sid,
    required this.client,
    required this.kind,
    required this.createdAt,
    required this.lastSeen,
    required this.current,
  });
  factory PanelSession.fromJson(Map<String, dynamic> j) => PanelSession(
    sid: pStr(j['sid']),
    client: pStr(j['client']),
    kind: pStr(j['kind']),
    createdAt: pStr(j['created_at']),
    lastSeen: pStr(j['last_seen']),
    current: pBool(j['current']),
  );
}

// ---------------------------------------------------------------- granths

class PanelLeaf {
  final String key, label, religion, religionId, group;
  final bool visible;
  const PanelLeaf({
    required this.key,
    required this.label,
    required this.religion,
    required this.religionId,
    required this.group,
    required this.visible,
  });
  factory PanelLeaf.fromJson(Map<String, dynamic> j) => PanelLeaf(
    key: pStr(j['key']),
    label: pStr(j['label']),
    religion: pStr(j['religion']),
    religionId: pStr(j['religion_id']),
    group: pStr(j['group']),
    visible: pBool(j['visible'], true),
  );
  bool get isOther => key == 'other';
}

class PanelGranth {
  final String id, title, author;
  final String? cover;
  final int pramanCount;
  final bool active;
  final String leaf, leafLabel, source, defaultLeaf, firstSeen;
  final bool hidden, isNew, noPraman;
  final int opens7d, watchS7d;

  /// 1-based catalogue number (null when unknown).
  final int? position;
  const PanelGranth({
    required this.id,
    required this.title,
    required this.author,
    required this.cover,
    required this.pramanCount,
    required this.active,
    required this.leaf,
    required this.leafLabel,
    required this.source,
    required this.defaultLeaf,
    required this.hidden,
    required this.isNew,
    required this.firstSeen,
    required this.noPraman,
    required this.opens7d,
    required this.watchS7d,
    this.position,
  });
  factory PanelGranth.fromJson(Map<String, dynamic> j) => PanelGranth(
    id: pStr(j['id']),
    title: pStr(j['title']),
    author: pStr(j['author']),
    cover: pStrN(j['cover']),
    pramanCount: pInt(j['praman_count']),
    active: pBool(j['active'], true),
    leaf: pStr(j['leaf'], 'other'),
    leafLabel: pStr(j['leaf_label']),
    source: pStr(j['source']),
    defaultLeaf: pStr(j['default_leaf']),
    hidden: pBool(j['hidden']),
    isNew: pBool(j['is_new']),
    firstSeen: pStr(j['first_seen']),
    noPraman: pBool(j['no_praman']),
    opens7d: pInt(j['opens_7d']),
    watchS7d: pInt(j['watch_s_7d']),
    position: j['position'] == null ? null : pInt(j['position']),
  );
}

class PanelSync {
  final String? lastOk;
  final int lastCount;
  final String? lastError;
  const PanelSync({this.lastOk, this.lastCount = 0, this.lastError});
  factory PanelSync.fromJson(Map<String, dynamic> j) => PanelSync(
    lastOk: pStrN(j['sync_last_ok']),
    lastCount: pInt(j['sync_last_count']),
    lastError: pStrN(j['sync_last_error']),
  );
}

class PanelGranthList {
  final List<PanelGranth> items;
  final List<PanelLeaf> leaves;
  final bool draft;
  final int baseVersion, total, hiddenCount;
  final PanelSync sync;
  const PanelGranthList({
    required this.items,
    required this.leaves,
    required this.draft,
    required this.baseVersion,
    required this.total,
    required this.hiddenCount,
    required this.sync,
  });
  factory PanelGranthList.fromJson(Map<String, dynamic> j) {
    final items = pList(j['items'], PanelGranth.fromJson);
    return PanelGranthList(
      items: items,
      leaves: pList(j['leaves'], PanelLeaf.fromJson),
      draft: pBool(j['draft']),
      baseVersion: pInt(j['base_version']),
      total: j.containsKey('total') ? pInt(j['total']) : items.length,
      hiddenCount: pInt(j['hidden_count']),
      sync: PanelSync.fromJson(pMap(j['sync'])),
    );
  }
}

// ---------------------------------------------------------------- structure

class StructureIcons {
  final List<String> group, religion, tones;
  const StructureIcons({
    this.group = const [],
    this.religion = const [],
    this.tones = const [],
  });
  factory StructureIcons.fromJson(Map<String, dynamic> j) => StructureIcons(
    group: pStrList(j['group']),
    religion: pStrList(j['religion']),
    tones: pStrList(j['tones']),
  );
}

class PanelStructure {
  /// The raw tree (kept as maps so unknown fields survive a round-trip PUT).
  final Map<String, dynamic> structure;
  final Map<String, int> counts;
  final List<PanelLeaf> leaves;
  final StructureIcons icons;
  final bool draft;
  final int baseVersion;
  const PanelStructure({
    required this.structure,
    required this.counts,
    required this.leaves,
    required this.icons,
    required this.draft,
    required this.baseVersion,
  });
  factory PanelStructure.fromJson(Map<String, dynamic> j) => PanelStructure(
    structure: pMap(j['structure']),
    counts: {for (final e in pMap(j['counts']).entries) e.key: pInt(e.value)},
    leaves: pList(j['leaves'], PanelLeaf.fromJson),
    icons: StructureIcons.fromJson(pMap(j['icons'])),
    draft: pBool(j['draft']),
    baseVersion: pInt(j['base_version']),
  );
}

// ---------------------------------------------------------------- diff / draft / versions

class DiffChange {
  final String from, to;
  const DiffChange(this.from, this.to);
  factory DiffChange.fromJson(Map<String, dynamic> j) =>
      DiffChange(_v(j['from']), _v(j['to']));
  static String _v(Object? v) =>
      v == null ? '—' : (v is bool ? (v ? 'हाँ' : 'नहीं') : v.toString());
}

class DiffGranth {
  final String id, title;
  final DiffChange? leaf, hidden;
  const DiffGranth({
    required this.id,
    required this.title,
    this.leaf,
    this.hidden,
  });
  factory DiffGranth.fromJson(Map<String, dynamic> j) => DiffGranth(
    id: pStr(j['id']),
    title: pStr(j['title']),
    leaf: j['leaf'] is Map ? DiffChange.fromJson(pMap(j['leaf'])) : null,
    hidden: j['hidden'] is Map ? DiffChange.fromJson(pMap(j['hidden'])) : null,
  );
}

class DiffFolder {
  final String path, change, title;
  final List<DiffField> fields;
  const DiffFolder({
    required this.path,
    required this.change,
    required this.title,
    required this.fields,
  });
  factory DiffFolder.fromJson(Map<String, dynamic> j) => DiffFolder(
    path: pStr(j['path']),
    change: pStr(j['change']),
    title: pStr(j['title']),
    fields: pList(j['fields'], DiffField.fromJson),
  );
}

class DiffField {
  final String field, from, to;
  const DiffField(this.field, this.from, this.to);
  factory DiffField.fromJson(Map<String, dynamic> j) => DiffField(
    pStr(j['field']),
    DiffChange._v(j['from']),
    DiffChange._v(j['to']),
  );
}

class PanelDiff {
  final List<DiffGranth> granths;
  final List<DiffFolder> folders;
  final List<DiffField> settings;
  final int hiddenCount, catalogTotal, changed;
  final List<String> warnings;
  const PanelDiff({
    this.granths = const [],
    this.folders = const [],
    this.settings = const [],
    this.hiddenCount = 0,
    this.catalogTotal = 0,
    this.changed = 0,
    this.warnings = const [],
  });
  factory PanelDiff.fromJson(Map<String, dynamic> j) {
    final granths = pList(j['granths'], DiffGranth.fromJson);
    final folders = pList(j['folders'], DiffFolder.fromJson);
    final settings = pList(j['settings'], DiffField.fromJson);
    return PanelDiff(
      granths: granths,
      folders: folders,
      settings: settings,
      hiddenCount: pInt(j['hidden_count']),
      catalogTotal: pInt(j['catalog_total']),
      changed: j.containsKey('changed')
          ? pInt(j['changed'])
          : granths.length + folders.length + settings.length,
      warnings: pStrList(j['warnings']),
    );
  }
  bool get isEmpty =>
      changed == 0 && granths.isEmpty && folders.isEmpty && settings.isEmpty;

  /// The server asks for `force:true` when more than 50% of the catalogue would be hidden.
  bool get needsForce =>
      (catalogTotal > 0 && hiddenCount * 2 > catalogTotal) ||
      warnings.any(
        (w) => w.contains('50%') || w.toLowerCase().contains('force'),
      );
}

class PanelDraft {
  final bool exists;
  final int baseVersion, nextVersion;
  final String? updatedAt;
  final PanelDiff diff;
  const PanelDraft({
    required this.exists,
    required this.baseVersion,
    required this.nextVersion,
    this.updatedAt,
    required this.diff,
  });
  factory PanelDraft.fromJson(Map<String, dynamic> j) => PanelDraft(
    exists: pBool(j['exists']),
    baseVersion: pInt(j['base_version'] ?? j['from_version']),
    nextVersion: pInt(j['next_version']),
    updatedAt: pStrN(j['updated_at']),
    diff: PanelDiff.fromJson(pMap(j['diff'])),
  );
}

class PublishResult {
  final int version;
  final String etag;
  final bool signed;
  final List<String> warnings;
  final int? rolledBackTo;
  const PublishResult({
    required this.version,
    required this.etag,
    required this.signed,
    required this.warnings,
    this.rolledBackTo,
  });
  factory PublishResult.fromJson(Map<String, dynamic> j) => PublishResult(
    version: pInt(j['version']),
    etag: pStr(j['etag']),
    signed: pBool(j['signed']),
    warnings: pStrList(j['warnings']),
    rolledBackTo: j['rolled_back_to'] == null
        ? null
        : pInt(j['rolled_back_to']),
  );
}

class PanelVersion {
  final int version, bytes;
  final String etag, kind, note, author, createdAt;
  const PanelVersion({
    required this.version,
    required this.etag,
    required this.kind,
    required this.note,
    required this.author,
    required this.createdAt,
    required this.bytes,
  });
  factory PanelVersion.fromJson(Map<String, dynamic> j) => PanelVersion(
    version: pInt(j['version']),
    etag: pStr(j['etag']),
    kind: pStr(j['kind']),
    note: pStr(j['note']),
    author: pStr(j['author']),
    createdAt: pStr(j['created_at']),
    bytes: pInt(j['bytes']),
  );
}

class PanelVersions {
  final List<PanelVersion> items;
  final int current;
  const PanelVersions(this.items, this.current);
  factory PanelVersions.fromJson(Map<String, dynamic> j) => PanelVersions(
    pList(j['items'], PanelVersion.fromJson),
    pInt(j['current']),
  );
}

class PanelVersionDetail {
  final PanelVersion info;
  final int against;
  final PanelDiff diff;
  const PanelVersionDetail(this.info, this.against, this.diff);
  factory PanelVersionDetail.fromJson(Map<String, dynamic> j) =>
      PanelVersionDetail(
        PanelVersion.fromJson(j),
        pInt(j['against']),
        PanelDiff.fromJson(pMap(j['diff'])),
      );
}

// ---------------------------------------------------------------- alerts

class NewGranth {
  final String id,
      title,
      author,
      firstSeen,
      suggestedLeaf,
      suggestedLabel,
      suggestionSource;
  final String? cover;
  final int pramanCount;
  const NewGranth({
    required this.id,
    required this.title,
    required this.author,
    required this.cover,
    required this.pramanCount,
    required this.firstSeen,
    required this.suggestedLeaf,
    required this.suggestedLabel,
    required this.suggestionSource,
  });
  factory NewGranth.fromJson(Map<String, dynamic> j) => NewGranth(
    id: pStr(j['id']),
    title: pStr(j['title']),
    author: pStr(j['author']),
    cover: pStrN(j['cover']),
    pramanCount: pInt(j['praman_count']),
    firstSeen: pStr(j['first_seen']),
    suggestedLeaf: pStr(j['suggested_leaf'], 'other'),
    suggestedLabel: pStr(j['suggested_label']),
    suggestionSource: pStr(j['suggestion_source']),
  );
}

class PanelAlert {
  final String id, kind, ref, message, createdAt;
  const PanelAlert({
    required this.id,
    required this.kind,
    required this.ref,
    required this.message,
    required this.createdAt,
  });
  factory PanelAlert.fromJson(Map<String, dynamic> j) => PanelAlert(
    id: pStr(j['id']),
    kind: pStr(j['kind']),
    ref: pStr(j['ref']),
    message: pStr(j['message']),
    createdAt: pStr(j['created_at']),
  );
}

class PanelAlerts {
  final List<NewGranth> newGranths;
  final List<PanelAlert> alerts;
  final int count;
  const PanelAlerts({
    required this.newGranths,
    required this.alerts,
    required this.count,
  });
  factory PanelAlerts.fromJson(Map<String, dynamic> j) {
    final n = pList(j['new_granths'], NewGranth.fromJson);
    final a = pList(j['alerts'], PanelAlert.fromJson);
    return PanelAlerts(
      newGranths: n,
      alerts: a,
      count: j.containsKey('count') ? pInt(j['count']) : n.length + a.length,
    );
  }
}

class SyncResult {
  final bool ok;
  final int count, changed;
  final List<String> added, removed;
  final String? error;
  const SyncResult({
    required this.ok,
    required this.count,
    required this.changed,
    required this.added,
    required this.removed,
    this.error,
  });
  factory SyncResult.fromJson(Map<String, dynamic> j) => SyncResult(
    ok: pBool(j['ok']),
    count: pInt(j['count']),
    changed: pInt(j['changed']),
    added: pStrList(j['added']),
    removed: pStrList(j['removed']),
    error: pStrN(j['error']),
  );
}

// ---------------------------------------------------------------- settings / audit

class PanelAnnouncement {
  final bool enabled;
  final String text, id, level;
  final String? expiresAt;

  /// CONTRACT §4.2: `announcement.pinned` (true = undismissable card in the reader app).
  final bool pinned;
  const PanelAnnouncement({
    this.enabled = false,
    this.text = '',
    this.id = '',
    this.level = 'info',
    this.expiresAt,
    this.pinned = false,
  });
  factory PanelAnnouncement.fromJson(Map<String, dynamic> j) =>
      PanelAnnouncement(
        enabled: pBool(j['enabled']),
        text: pStr(j['text']),
        id: pStr(j['id']),
        level: pStr(j['level'], 'info'),
        expiresAt: pStrN(j['expires_at']),
        pinned: pBool(j['pinned']),
      );
}

class PanelSettings {
  final bool aiEnabled, analyticsEnabled;
  final double analyticsSample;
  final PanelAnnouncement announcement;
  final String aiEndpoint;
  final List<String> levels;
  final String base, signingPublicKey;
  final int publishedVersion;
  final bool signed, draft;

  /// CONTRACT §4.1: `ui.grid` of the draft (1|2|3) or null = not set (the app defaults to 3).
  final int? uiGrid;
  const PanelSettings({
    this.uiGrid,
    required this.aiEnabled,
    required this.analyticsEnabled,
    required this.analyticsSample,
    required this.announcement,
    required this.aiEndpoint,
    required this.levels,
    required this.base,
    required this.signingPublicKey,
    required this.publishedVersion,
    required this.signed,
    required this.draft,
  });
  factory PanelSettings.fromJson(Map<String, dynamic> j) {
    final flags = pMap(j['flags']);
    final info = pMap(j['info']);
    final levels = pStrList(j['levels']);
    return PanelSettings(
      aiEnabled: pBool(flags['ai_enabled'], true),
      analyticsEnabled: pBool(flags['analytics_enabled'], true),
      analyticsSample: pDouble(flags['analytics_sample'], 1).clamp(0.0, 1.0),
      announcement: PanelAnnouncement.fromJson(pMap(j['announcement'])),
      aiEndpoint: pStr(j['ai_endpoint']),
      levels: levels.isEmpty ? const ['info', 'warn', 'critical'] : levels,
      base: pStr(info['base']),
      signingPublicKey: pStr(info['signing_public_key']),
      publishedVersion: pInt(info['published_version']),
      signed: pBool(info['signed']),
      draft: pBool(j['draft']),
      uiGrid: (() {
        final g = pMap(j['ui'])['grid'];
        final n = g is num ? g.toInt() : int.tryParse('$g');
        return n != null && n >= 1 && n <= 3 ? n : null;
      })(),
    );
  }
}

class AuditItem {
  final int id;
  final String ts, actor, action, detail;
  const AuditItem({
    required this.id,
    required this.ts,
    required this.actor,
    required this.action,
    required this.detail,
  });
  factory AuditItem.fromJson(Map<String, dynamic> j) => AuditItem(
    id: pInt(j['id']),
    ts: pStr(j['ts']),
    actor: pStr(j['actor']),
    action: pStr(j['action']),
    detail: pStr(j['detail']),
  );
}

// ---------------------------------------------------------------- stats

class TopGranth {
  final String id, title;
  final int opens, watchS, avgWatchS;
  const TopGranth({
    required this.id,
    required this.title,
    required this.opens,
    required this.watchS,
    required this.avgWatchS,
  });
  factory TopGranth.fromJson(Map<String, dynamic> j) => TopGranth(
    id: pStr(j['id']),
    title: pStr(j['title']),
    opens: pInt(j['opens']),
    watchS: pInt(j['watch_s']),
    avgWatchS: pInt(j['avg_watch_s']),
  );
}

class TopFolder {
  final String key, label;
  final int opens, watchS, avgWatchS;
  const TopFolder({
    required this.key,
    required this.label,
    required this.opens,
    required this.watchS,
    this.avgWatchS = 0,
  });
  factory TopFolder.fromJson(Map<String, dynamic> j) => TopFolder(
    key: pStr(j['key']),
    label: pStr(j['label'], pStr(j['key'])),
    opens: pInt(j['opens']),
    watchS: pInt(j['watch_s']),
    avgWatchS: pInt(j['avg_watch_s']),
  );
}

class DayPoint {
  final String day;
  final int n, fgS;
  const DayPoint(this.day, this.n, this.fgS);
}

class NameCount {
  final String name;
  final int n;
  const NameCount(this.name, this.n);
}

class ScreenTime {
  final String name;
  final int watchS;
  const ScreenTime(this.name, this.watchS);
}

class StatsTotals {
  final int totalInstalls, active1d, active7d, active30d, newInstallsInRange;
  final String? firstInstallDay;
  final int totalFgS,
      totalFgSAllTime,
      avgFgSPerActiveUser,
      avgFgSPerActiveUserDay;
  final int sessions,
      granthWatchS,
      folderWatchS,
      granthOpens,
      folderOpens,
      topicOpens,
      pramanOpens,
      usersInRange;
  final double avgSessionsPerActiveUserDay;
  const StatsTotals({
    this.totalInstalls = 0,
    this.active1d = 0,
    this.active7d = 0,
    this.active30d = 0,
    this.newInstallsInRange = 0,
    this.firstInstallDay,
    this.totalFgS = 0,
    this.totalFgSAllTime = 0,
    this.avgFgSPerActiveUser = 0,
    this.avgFgSPerActiveUserDay = 0,
    this.sessions = 0,
    this.avgSessionsPerActiveUserDay = 0,
    this.granthWatchS = 0,
    this.folderWatchS = 0,
    this.granthOpens = 0,
    this.folderOpens = 0,
    this.topicOpens = 0,
    this.pramanOpens = 0,
    this.usersInRange = 0,
  });
  factory StatsTotals.fromJson(Map<String, dynamic> j) => StatsTotals(
    totalInstalls: pInt(j['total_installs']),
    active1d: pInt(j['active_1d']),
    active7d: pInt(j['active_7d']),
    active30d: pInt(j['active_30d']),
    newInstallsInRange: pInt(j['new_installs_in_range']),
    firstInstallDay: pStrN(j['first_install_day']),
    totalFgS: pInt(j['total_fg_s']),
    totalFgSAllTime: pInt(j['total_fg_s_all_time']),
    avgFgSPerActiveUser: pInt(j['avg_fg_s_per_active_user']),
    avgFgSPerActiveUserDay: pInt(j['avg_fg_s_per_active_user_day']),
    sessions: pInt(j['sessions']),
    avgSessionsPerActiveUserDay: pDouble(j['avg_sessions_per_active_user_day']),
    granthWatchS: pInt(j['granth_watch_s']),
    folderWatchS: pInt(j['folder_watch_s']),
    granthOpens: pInt(j['granth_opens']),
    folderOpens: pInt(j['folder_opens']),
    topicOpens: pInt(j['topic_opens']),
    pramanOpens: pInt(j['praman_opens']),
    usersInRange: pInt(j['users_in_range']),
  );
}

class StatsOverview {
  final int days;
  final String since;
  final StatsTotals totals;
  final List<DayPoint> dau;
  final List<DayPoint> newInstalls;
  final List<NameCount> installsByVersion, installsByOs, failureKinds;
  final Map<String, int> versions;
  final int syncOk, syncFail, pdfOk, pdfFail, aiAsked, aiAnswered, aiCiteTap;
  final double syncFailRate;
  final List<ScreenTime> screens;
  final List<TopGranth> topGranthsOpens, topGranthsWatch;
  final List<TopFolder> topFolders, topFoldersWatch, religions;
  final int newGranthsPending;

  const StatsOverview({
    required this.days,
    required this.since,
    required this.totals,
    required this.dau,
    required this.newInstalls,
    required this.installsByVersion,
    required this.installsByOs,
    required this.failureKinds,
    required this.versions,
    required this.syncOk,
    required this.syncFail,
    required this.syncFailRate,
    required this.pdfOk,
    required this.pdfFail,
    required this.aiAsked,
    required this.aiAnswered,
    required this.aiCiteTap,
    required this.screens,
    required this.topGranthsOpens,
    required this.topGranthsWatch,
    required this.topFolders,
    required this.topFoldersWatch,
    required this.religions,
    required this.newGranthsPending,
  });

  factory StatsOverview.fromJson(Map<String, dynamic> j) {
    final sync = pMap(j['sync']);
    final pdf = pMap(j['pdf']);
    final ai = pMap(j['ai']);
    final screensRaw =
        (j['screens'] is List && (j['screens'] as List).isNotEmpty)
        ? j['screens']
        : j['top_screens'];
    final syncOk = pInt(sync['ok']), syncFail = pInt(sync['fail']);
    return StatsOverview(
      days: pInt(j['days'], 7),
      since: pStr(j['since']),
      totals: StatsTotals.fromJson(pMap(j['totals'])),
      dau: pList(
        j['dau'],
        (m) => DayPoint(pStr(m['day']), pInt(m['n']), pInt(m['fg_s'])),
      ),
      newInstalls: pList(
        j['new_installs'],
        (m) => DayPoint(pStr(m['day']), pInt(m['n']), 0),
      ),
      installsByVersion: pList(
        j['installs_by_version'],
        (m) => NameCount(pStr(m['app']), pInt(m['n'])),
      ),
      installsByOs: pList(
        j['installs_by_os'],
        (m) => NameCount(pStr(m['os']), pInt(m['n'])),
      ),
      failureKinds: pList(
        j['failure_kinds'],
        (m) => NameCount(pStr(m['kind']), pInt(m['n'])),
      ),
      versions: {
        for (final e in pMap(j['versions']).entries) e.key: pInt(e.value),
      },
      syncOk: syncOk,
      syncFail: syncFail,
      syncFailRate: sync.containsKey('fail_rate')
          ? pDouble(sync['fail_rate'])
          : (syncOk + syncFail == 0 ? 0 : syncFail / (syncOk + syncFail)),
      pdfOk: pInt(pdf['ok']),
      pdfFail: pInt(pdf['fail']),
      aiAsked: pInt(ai['asked']),
      aiAnswered: pInt(ai['answered']),
      aiCiteTap: pInt(ai['cite_tap']),
      screens: pList(
        screensRaw,
        (m) => ScreenTime(pStr(m['scr'] ?? m['screen']), pInt(m['watch_s'])),
      ),
      topGranthsOpens: pList(j['top_granths_opens'], TopGranth.fromJson),
      topGranthsWatch: pList(j['top_granths_watch'], TopGranth.fromJson),
      topFolders: pList(j['top_folders'], TopFolder.fromJson),
      topFoldersWatch: pList(j['top_folders_watch'], TopFolder.fromJson),
      religions: pList(j['religions'], TopFolder.fromJson),
      newGranthsPending: pInt(j['new_granths_pending']),
    );
  }

  /// True while no install has reported anything yet (nice empty state instead of a wall of zeros).
  bool get isEmpty =>
      totals.totalInstalls == 0 &&
      totals.totalFgSAllTime == 0 &&
      totals.granthOpens == 0 &&
      topGranthsOpens.isEmpty &&
      topFolders.isEmpty;
}

class GranthStatsList {
  final int days;
  final List<TopGranth> items;
  const GranthStatsList(this.days, this.items);
  factory GranthStatsList.fromJson(Map<String, dynamic> j) =>
      GranthStatsList(pInt(j['days']), pList(j['items'], TopGranth.fromJson));
}

class FolderStatsList {
  final int days;
  final List<TopFolder> items;
  const FolderStatsList(this.days, this.items);
  factory FolderStatsList.fromJson(Map<String, dynamic> j) =>
      FolderStatsList(pInt(j['days']), pList(j['items'], TopFolder.fromJson));
}

class SeriesPoint {
  final String day;
  final int opens, watchS;
  const SeriesPoint(this.day, this.opens, this.watchS);
}

class StatsSeries {
  final int days;
  final String kind, id;
  final List<SeriesPoint> series;
  const StatsSeries(this.days, this.kind, this.id, this.series);
  factory StatsSeries.fromJson(Map<String, dynamic> j) => StatsSeries(
    pInt(j['days']),
    pStr(j['kind']),
    pStr(j['id']),
    pList(
      j['series'],
      (m) => SeriesPoint(pStr(m['day']), pInt(m['opens']), pInt(m['watch_s'])),
    ),
  );
}

// ---------------------------------------------------------------- admins (owner only, contract 3.5)

class PanelAdmin {
  final String username, role, createdAt, updatedAt;
  final String? createdBy, lastSeen;
  final bool disabled, you;
  final int activeSessions;
  const PanelAdmin({
    required this.username,
    required this.role,
    required this.disabled,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.activeSessions,
    required this.lastSeen,
    required this.you,
  });
  factory PanelAdmin.fromJson(Map<String, dynamic> j) => PanelAdmin(
    username: pStr(j['username']),
    role: pStr(j['role'], 'admin'),
    disabled: pBool(j['disabled']),
    createdAt: pStr(j['created_at']),
    updatedAt: pStr(j['updated_at']),
    createdBy: pStrN(j['created_by']),
    activeSessions: pInt(j['active_sessions']),
    lastSeen: pStrN(j['last_seen']),
    you: pBool(j['you']),
  );
  bool get isOwner => role == 'owner';
}

class PanelAdminList {
  final List<PanelAdmin> items;
  final List<String> roles;
  final int minPasswordLength;
  const PanelAdminList({
    required this.items,
    required this.roles,
    required this.minPasswordLength,
  });
  factory PanelAdminList.fromJson(Map<String, dynamic> j) {
    final roles = pStrList(j['roles']);
    return PanelAdminList(
      items: pList(j['items'], PanelAdmin.fromJson),
      roles: roles.isEmpty ? const ['owner', 'admin'] : roles,
      minPasswordLength: pInt(j['min_password_length'], 10),
    );
  }
}

/// Username rule of `POST /admins` (contract 3.5).
final RegExp kAdminUsername = RegExp(r'^[a-z0-9][a-z0-9_.-]{2,31}$');

/// Error text for a new admin username / password, or null when fine.
String? adminUsernameError(String raw) {
  final u = raw.trim().toLowerCase();
  if (!kAdminUsername.hasMatch(u))
    return 'यूज़रनेम: 3–32 अक्षर, a-z 0-9 _ . - / username 3–32 chars';
  return null;
}

String? adminPasswordError(String pw, String username, {int min = 10}) {
  if (pw.length < min || pw.length > 256)
    return 'पासवर्ड $min–256 अक्षर का हो / password $min–256 chars';
  if (pw.toLowerCase() == username.trim().toLowerCase()) {
    return 'पासवर्ड यूज़रनेम जैसा नहीं हो सकता / must differ from username';
  }
  return null;
}

// ---------------------------------------------------------------- contacts / विशेष जानकार (contract 3.6)

class PanelContact {
  final String id, name, role, phone;
  final bool whatsapp, visible;
  final int order;
  const PanelContact({
    required this.id,
    required this.name,
    this.role = '',
    this.phone = '',
    this.whatsapp = false,
    this.visible = true,
    this.order = 0,
  });
  factory PanelContact.fromJson(Map<String, dynamic> j) => PanelContact(
    id: pStr(j['id']),
    name: pStr(j['name']),
    role: pStr(j['role']),
    phone: pStr(j['phone']),
    whatsapp: pBool(j['whatsapp']),
    visible: pBool(j['visible'], true),
    order: pInt(j['order']),
  );
  PanelContact copyWith({
    String? name,
    String? role,
    String? phone,
    bool? whatsapp,
    bool? visible,
  }) => PanelContact(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    phone: phone ?? this.phone,
    whatsapp: whatsapp ?? this.whatsapp,
    visible: visible ?? this.visible,
    order: order,
  );

  /// Body item for `PUT /contacts` (a missing id is generated by the server).
  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'role': role,
    'phone': phone,
    'whatsapp': phone.isNotEmpty && whatsapp,
    'visible': visible,
  };
}

class PanelContacts {
  final String title;
  final List<PanelContact> items;
  final int maxContacts, baseVersion, nextVersion;
  final bool hasDraft;
  const PanelContacts({
    required this.title,
    required this.items,
    required this.maxContacts,
    required this.hasDraft,
    required this.baseVersion,
    required this.nextVersion,
  });
  factory PanelContacts.fromJson(Map<String, dynamic> j) => PanelContacts(
    title: pStr(pMap(j['page'])['title'], kContactsTitle),
    items: pList(j['items'], PanelContact.fromJson),
    maxContacts: pInt(j['max_contacts'], 50),
    hasDraft: pBool(j['has_draft']),
    baseVersion: pInt(j['base_version']),
    nextVersion: pInt(j['next_version']),
  );
}

const kContactsTitle = 'विशेष जानकार';

final RegExp kPhoneRe = RegExp(r'^(\+[0-9]{1,19}|[0-9]{1,20})$');

/// Spaces / hyphens are stripped (the server does the same); returns the cleaned number.
String cleanPhone(String raw) => raw.replaceAll(RegExp(r'[\s\-]'), '');

/// Error text for one contact, or null when valid (mirrors the server rules of contract 1.8).
String? contactError(PanelContact c) {
  final n = c.name.trim();
  if (n.isEmpty || n.length > 80)
    return 'नाम ज़रूरी है (≤80 अक्षर) / name required';
  if (c.role.trim().length > 80) return 'भूमिका ≤80 अक्षर / role max 80 chars';
  if (c.phone.isNotEmpty && !kPhoneRe.hasMatch(c.phone)) {
    return 'फ़ोन: अंक, शुरू में एक + (≤20) / phone: digits, optional leading +';
  }
  if (c.whatsapp && c.phone.isEmpty)
    return 'व्हाट्सऐप के लिए नंबर चाहिए / WhatsApp needs a number';
  return null;
}
