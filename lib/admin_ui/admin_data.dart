import 'dart:async';

import 'package:flutter/foundation.dart';

import '../admin/core/app_state.dart';
import '../admin/models/models.dart' as w;
import '../admin/models/panel_models.dart';
import '../models/models.dart' as u;
import '../models/structure.dart';
import '../services/catalog_store.dart';
import '../services/shelves.dart';
import 'arrange_granths.dart';

/// The admin app's data hub. It loads the two back ends (the wnm site: topics / granths / pramans,
/// and the control server: structure, granth placement, hidden ids, settings) and hands the
/// result to the user app's own screens in the user app's own model types, so those screens
/// (cards, search, order, folders) run unmodified on admin data.
///
/// Rules this class enforces:
///  * the admin sees EVERY granth, hidden ones too, marked as hidden ([isHidden]);
///  * placement is the control server's `leaf` (it already merges overrides and keywords), so a
///    card is in the folder the readers will see it in;
///  * hide / show is `hidden_granth_ids` (draft until published), never a delete.
class AdminData extends ChangeNotifier {
  AdminData(this.app, {bool warmSearch = true}) : _warm = warmSearch {
    app.addListener(_onApp);
  }

  /// Set once in `main` (and in tests). Screens read the shared instance.
  static AdminData? _i;
  static AdminData get I => _i!;
  static set I(AdminData v) => _i = v;
  static bool get isSet => _i != null;

  final AppState app;
  final bool _warm;

  PanelGranthList? list;
  PanelStructure? structureData;
  PanelSettings? settings;

  bool loading = false;
  String? error;
  bool controlError = false;

  /// Bumped on each applied load (cheap change signal for selectors).
  int version = 0;

  Structure structure = Structure.empty;
  ShelfIndex? _index;
  List<u.Granth> granths = const [];
  List<u.Topic> topics = const [];
  List<u.Praman> pramans = const [];
  final Map<String, PanelGranth> _byId = {};
  Set<String> hiddenIds = const {};

  Map<String, w.Granth> _wGranths = const {};

  void _onApp() {
    // The old admin screens still call app.bump() after a write: reload then.
    if (_seenRev != app.revision) {
      _seenRev = app.revision;
      unawaited(refresh(quiet: true));
    }
  }

  int _seenRev = 0;

  @override
  void dispose() {
    app.removeListener(_onApp);
    super.dispose();
  }

  bool get controlReady => app.panel.loggedIn;
  PanelMe? get me => app.panel.me;
  bool get isOwner => me?.isOwner ?? false;

  /// The folder index of the Granth tab (all granths, hidden ones included).
  ShelfIndex get index =>
      _index ??= ShelfIndex.build(structure, granths, overrides: _overrides());

  Map<String, String> _overrides() => {
    for (final e in _byId.values)
      if (e.leaf.isNotEmpty) e.id: e.leaf,
  };

  bool isHidden(String granthId) => hiddenIds.contains(granthId);
  PanelGranth? panelGranth(String id) => _byId[id];
  w.Granth? wGranth(String id) => _wGranths[id];
  w.Topic? wTopic(String id) {
    for (final t in app.topics) {
      if ('${t.id}' == id) return t;
    }
    return null;
  }

  w.Praman? wPraman(String id) {
    for (final p in app.pramans) {
      if ('${p.id}' == id) return p;
    }
    return null;
  }

  /// wnm "active" flag with the optimistic override.
  bool activeGranth(u.Granth g) =>
      app.activeOf('granth', int.tryParse(g.id) ?? -1, _isActive(g.raw));
  bool activeTopic(u.Topic t) =>
      app.activeOf('topic', int.tryParse(t.id) ?? -1, _isActive(t.raw));
  bool activePraman(u.Praman p) =>
      app.activeOf('praman', int.tryParse(p.id) ?? -1, _isActive(p.raw));
  static bool _isActive(Map<String, dynamic> raw) {
    final v = raw['isActive'];
    if (v == null) return true;
    final s = '$v'.toLowerCase();
    return s == '1' || s == 'true';
  }

  /// Everything: wnm lists + control server. Failures of one side never blank the other.
  Future<void> refresh({bool quiet = false}) async {
    if (loading) return;
    loading = !quiet;
    error = null;
    if (!quiet) notifyListeners();
    try {
      await Future.wait([_loadWnm(), _loadControl()]);
    } finally {
      loading = false;
      _apply();
    }
  }

  Future<void> _loadWnm() async {
    if (!app.loggedIn) return;
    try {
      final r = await Future.wait([
        app.api.topics(),
        app.api.granths(),
        app.api.pramans(),
      ]);
      app.topics = r[0] as List<w.Topic>;
      app.granths = r[1] as List<w.Granth>;
      app.pramans = r[2] as List<w.Praman>;
    } catch (e) {
      error = '$e';
    }
  }

  Future<void> _loadControl() async {
    if (!controlReady) return;
    try {
      final api = app.panel.api;
      final r = await Future.wait<Object?>([
        api.granths(),
        api.structure(),
        api.settings(),
      ]);
      list = r[0] as PanelGranthList;
      structureData = r[1] as PanelStructure;
      settings = r[2] as PanelSettings;
      controlError = false;
      unawaited(app.panel.refreshMe());
    } catch (e) {
      controlError = true;
      error ??= '$e';
    }
  }

  /// Reloads only the control server's side (after a hide / folder edit).
  Future<void> refreshControl() async {
    await _loadControl();
    _apply();
  }

  void _apply() {
    granths = [for (final g in app.granths) u.Granth(g.raw)];
    topics = [for (final t in app.topics) u.Topic(t.raw)];
    pramans = [for (final p in app.pramans) u.Praman(p.raw)];
    _wGranths = {for (final g in app.granths) '${g.id}': g};
    _byId
      ..clear()
      ..addEntries([
        for (final g in list?.items ?? const <PanelGranth>[]) MapEntry(g.id, g),
      ]);
    hiddenIds = {
      for (final g in _byId.values)
        if (g.hidden) g.id,
    };
    structure = structureData == null
        ? Structure.empty
        : Structure.fromMap(structureData!.structure);
    _index = null;
    Shelves.adoptAdmin(structure, () => index);
    version++;
    CatalogStore.I.adoptAdminCatalog(
      u.Catalog(topics: topics, granths: granths, pramans: pramans),
      warm: _warm,
    );
    notifyListeners();
  }

  /// Clears everything on logout.
  void reset() {
    list = null;
    structureData = null;
    settings = null;
    granths = const [];
    topics = const [];
    pramans = const [];
    _byId.clear();
    hiddenIds = const {};
    structure = Structure.empty;
    _index = null;
    version++;
    notifyListeners();
  }

  // ------------------------------------------------------------------ writes (control server)

  /// Hide / show granths (draft until published). Returns false when the write failed.
  Future<void> setHidden(Iterable<String> ids, bool hidden) async {
    final api = app.panel.api;
    final l = ids.toList();
    if (l.length == 1) {
      await api.setGranth(l.first, hidden: hidden);
    } else if (l.isNotEmpty) {
      await api.bulkGranths(l, hidden: hidden);
    }
    await refreshControl();
    app.panel.bump();
  }

  /// Saves a manual order for the granths of ONE folder ([folderIds] in the wanted order).
  ///
  /// The reader app orders a folder by the API `position`, and the wnm site's
  /// `update_granth_order` renumbers the whole catalogue from the array it gets, so the
  /// catalogue is sent with the folder's granths re-ordered inside the slots they already
  /// hold ([catalogueForFolderOrder]). Live immediately (not a draft). Throws on failure.
  Future<void> saveGranthOrder(List<int> folderIds) async {
    final all = [...app.granths];
    final idx = {for (var i = 0; i < all.length; i++) all[i].id: i};
    all.sort((a, b) {
      final c = a.position.compareTo(b.position);
      return c != 0 ? c : idx[a.id]!.compareTo(idx[b.id]!);
    });
    await app.api.saveGranthOrder(catalogueForFolderOrder(all, folderIds));
    app.bump();
  }

  Future<void> setLeaf(String id, String leaf) async {
    await app.panel.api.setGranth(id, leaf: leaf);
    await refreshControl();
    app.panel.bump();
  }

  Future<void> clearLeaf(String id) async {
    await app.panel.api.setGranth(id, clearLeaf: true);
    await refreshControl();
    app.panel.bump();
  }

  Future<void> saveStructure(Map<String, dynamic> tree) async {
    await app.panel.api.putStructure(tree);
    await refreshControl();
    app.panel.bump();
  }

  Future<void> saveSettings({
    bool? aiEnabled,
    Map<String, Object?>? announcement,
    int? uiGrid,
    bool clearUiGrid = false,
    Map<String, int?>? uiGridPages,
  }) async {
    await app.panel.api.putSettings(
      uiGridPages: uiGridPages,
      aiEnabled: aiEnabled,
      announcement: announcement,
      uiGrid: uiGrid,
      clearUiGrid: clearUiGrid,
    );
    await refreshControl();
    app.panel.bump();
  }
}
