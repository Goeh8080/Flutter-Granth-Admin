import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../admin/core/app_state.dart';
import '../admin/screens/panel/panel_widgets.dart' show showPublishSheet;
import '../admin_ui/admin_data.dart';
import '../highlighter/highlighter_launcher.dart';
import '../services/catalog_store.dart';
import '../services/native_bridge.dart';
import '../state/places.dart';
import '../state/router.dart';
import '../state/toast.dart';
import '../state/ui_prefs.dart';
import '../theme/colors.dart';
import '../widgets/bounded_scroll.dart';
import '../widgets/common.dart';
import '../widgets/pdf_sheets.dart' show openExit;
import 'admin_panel_screen.dart';
import 'ai_screen.dart';
import 'dashboard_screen.dart';
import 'pramans_screen.dart';
import 'shelves_screen.dart';
import 'topics_screen.dart';

/// The admin root: mast with the three counts, hamburger menu (7 entries), a draft strip when
/// the control server holds unpublished edits, then the active tab as ONE scroller of slivers.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  late final AnimationController _panelIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  final ValueNotifier<bool> _showTop = ValueNotifier(false);
  String _routeKey = '';
  bool _exitOpen = false;

  AppNav get nav => AppNav.I;

  @override
  void initState() {
    super.initState();
    _routeKey = nav.route.key;
    nav.addListener(_onNav);
    nav.beforeLeave = _savePlace;
    nav.onExitRequest = _askExit;
    _scroll.addListener(
      () => _showTop.value = _scroll.hasClients && _scroll.offset > 480,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePlace();
    });
  }

  @override
  void dispose() {
    nav.removeListener(_onNav);
    _scroll.dispose();
    _panelIn.dispose();
    super.dispose();
  }

  // ---------- scroll places (`xh`) ----------
  void _savePlace() {
    final k = Places.keyFor(nav.route);
    if (k == null || !_scroll.hasClients) return;
    Places.save(k, _scroll.offset);
  }

  int _restoreRun = 0;

  /// Puts the list back where it was left. The list is rebuilt from the top, so it is only
  /// as tall as what has been laid out so far: keep setting the position every frame until
  /// it holds (content settled), the person touches the list, or ~2 s have passed.
  void _restorePlace() {
    final k = Places.keyFor(nav.route);
    final y = k == null ? 0.0 : Places.y(k);
    final run = ++_restoreRun;
    var frames = 0;
    var held = 0;
    void step() {
      if (!mounted || run != _restoreRun || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.userScrollDirection != ScrollDirection.idle)
        return; // the person took over
      final to = math.min(y, p.maxScrollExtent);
      if ((p.pixels - to).abs() > 0.5) {
        _scroll.jumpTo(to);
        held = 0;
      } else if ((y - to).abs() <= 0.5) {
        held++; // exactly there; wait a few frames for late layout changes
      }
      frames++;
      if (y <= 0 || held >= 4 || frames >= 120) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => step());
      WidgetsBinding.instance.scheduleFrame();
    }

    step();
  }

  void _onNav() {
    final k = nav.route.key;
    if (k != _routeKey) {
      _routeKey = k;
      _panelIn.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _restorePlace());
    }
    setState(() {});
  }

  Future<void> _askExit() async {
    if (_exitOpen) return;
    _exitOpen = true;
    final yes = await openExit(context);
    _exitOpen = false;
    if (yes) await NativeBridge.exitApp();
  }

  // ---------- back (`__granthBack`) ----------
  void _onBack() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f.context != null && f.context!.widget is EditableText) {
      f.unfocus();
      return;
    }
    if (f != null &&
        f.hasPrimaryFocus &&
        f.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      f.unfocus();
      return;
    }
    if (nav.menuOpen) {
      nav.toggleMenu();
      return;
    }
    nav.back();
  }

  Widget _panel(GRoute r) => switch (r.panel) {
    Panel.dashboard => const DashboardPanel(),
    Panel.topics => const TopicsPanel(),
    Panel.granths => ShelvesPanel(route: r),
    Panel.pramans => PramansPanel(route: r),
    Panel.ai => const AiPanel(),
    Panel.adminPanel => const AdminPanelScreen(),
    // Not part of the admin app (kept in the enum for the user app's router): show the dashboard.
    Panel.gallery || Panel.legal => const DashboardPanel(),
  };

  @override
  Widget build(BuildContext context) {
    final r = nav.route;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: GColors.maroon,
        ),
        child: Scaffold(
          backgroundColor: GColors.cream,
          // The AI chat's text box sits under the page (not over it), so the list is only as tall
          // as what is left above the keyboard and the last message is never hidden.
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: RepaintBoundary(child: _RootBackground()),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        CatalogStore.I,
                        UiPrefs.I,
                        AdminData.I,
                      ]),
                      builder: (context, _) {
                        final d = AdminData.I;
                        final total =
                            d.topics.length +
                            d.granths.length +
                            d.pramans.length;
                        return CustomScrollView(
                          controller: _scroll,
                          physics: const BoundedScrollPhysics(),
                          slivers: [
                            const SliverToBoxAdapter(child: _Mast()),
                            SliverToBoxAdapter(
                              child: _Hamburger(open: nav.menuOpen),
                            ),
                            SliverToBoxAdapter(
                              child: _NavMenu(open: nav.menuOpen),
                            ),
                            const SliverToBoxAdapter(child: DraftStrip()),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                72,
                              ),
                              sliver: SliverMainAxisGroup(
                                slivers: [
                                  if (d.loading && total == 0)
                                    const SliverToBoxAdapter(
                                      child: EmptyState(
                                        title: 'डेटा लोड हो रहा है…',
                                        spinner: true,
                                      ),
                                    ),
                                  if (!d.loading &&
                                      d.error != null &&
                                      total == 0)
                                    SliverToBoxAdapter(
                                      child: EmptyState(
                                        title: 'अभी खाली है',
                                        body: d.error,
                                        actionLabel: 'फिर कोशिश करें',
                                        onAction: () => AdminData.I.refresh(),
                                      ),
                                    ),
                                  SliverFadeTransition(
                                    key: const ValueKey('panel'),
                                    opacity: CurvedAnimation(
                                      parent: _panelIn,
                                      curve: Curves.easeOutCubic,
                                    ),
                                    sliver: KeyedSubtree(
                                      key: ValueKey(r.key),
                                      child: _panel(r),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    _ScrollRail(controller: _scroll),
                    Positioned(
                      right: 48,
                      bottom: 36,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _showTop,
                        builder: (context, show, _) => AnimatedSlide(
                          offset: show ? Offset.zero : const Offset(0, 0.6),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: show ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: !show,
                              child: Pressable(
                                onTap: () => _scroll.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: GColors.maroon,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Top',
                                    style: GText.sans(
                                      size: 16,
                                      weight: FontWeight.w700,
                                      color: GColors.paper,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const _ToastLayer(),
                  ],
                ),
              ),
              // The AI tab's question box (the admin can always chat; the on/off switch is on that tab).
              if (r.panel == Panel.ai) const AiComposer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The control server's shared draft has unpublished edits: say so and offer to publish.
class DraftStrip extends StatelessWidget {
  const DraftStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final panel = AppScope.of(context).panel;
    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        final me = panel.me;
        if (me == null || !me.hasDraft) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('draft-strip'),
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GColors.gold),
          ),
          child: Row(
            children: [
              const GIcon('alert-triangle', size: 18, color: GColors.brown),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'बदलाव अभी ड्राफ्ट में हैं — पाठकों को दिखने के लिए प्रकाशित करें',
                  style: GText.sans(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: GColors.brown,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Pressable(
                key: const ValueKey('draft-publish'),
                onTap: () async {
                  await showPublishSheet(context);
                  await AdminData.I.refreshControl();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: GColors.maroon,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'प्रकाशित',
                    style: GText.sans(
                      size: 13.5,
                      weight: FontWeight.w700,
                      color: GColors.paper,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RootBackground extends StatelessWidget {
  const _RootBackground();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: GColors.cream),
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.8, -0.84),
              radius: 0.92,
              colors: [Color(0x1FE8821A), Color(0x00E8821A)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.84, 0.8),
              radius: 0.84,
              colors: [Color(0x147B1F2E), Color(0x007B1F2E)],
            ),
          ),
        ),
      ],
    ),
  );
}

/// `.mast`
class _Mast extends StatelessWidget {
  const _Mast();

  // The mast is a const widget, so the shell's rebuilds never reach it: it listens to the data
  // itself. (After a session expiry the shell is created with an empty AdminData; the catalog
  // arrives later and the header counts must follow it.)
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      CatalogStore.I,
      if (AdminData.isSet) AdminData.I,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    // The admin data first; the shared catalog (what the Dashboard cards show) is the fallback,
    // so the header never shows "—" while the cards below show numbers.
    final a = AdminData.isSet ? AdminData.I : null;
    final c = CatalogStore.I;
    int pick(int fromAdmin, int fromCatalog) =>
        fromAdmin > 0 ? fromAdmin : fromCatalog;
    final nTopics = pick(a?.topics.length ?? 0, c.topics.length);
    final nGranths = pick(a?.granths.length ?? 0, c.granths.length);
    final nPramans = pick(a?.pramans.length ?? 0, c.pramans.length);
    final nav = AppNav.I;
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GColors.maroon, GColors.brown, GColors.maroonLight],
          stops: [0, 0.52, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: GColors.shadow(0.35),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  GColors.saffronDark,
                  GColors.saffron,
                  GColors.gold,
                  GColors.saffron,
                  GColors.saffronDark,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        onTap: () => nav.go('#/dashboard'),
                        behavior: HitTestBehavior.deferToChild,
                        child: Row(
                          children: [
                            const Hero(tag: 'granth-logo', child: LogoIcon()),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'ग्रंथ प्रबंधन',
                                style: GText.display(
                                  size: 26,
                                  color: GColors.goldLight,
                                  height: 1.15,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: GColors.saffron,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ADMIN',
                                style: GText.sans(
                                  size: 11,
                                  weight: FontWeight.w800,
                                  color: GColors.brown,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MastBtn(
                      key: const ValueKey('mast-refresh'),
                      icon: 'refresh-cw',
                      onTap: () {
                        Toast.show('ताज़ा किया जा रहा है…');
                        AdminData.I.refresh();
                      },
                    ),
                    const SizedBox(width: 6),
                    _MastBtn(
                      key: const ValueKey('mast-admin'),
                      icon: 'settings',
                      onTap: () => nav.go('#/admin'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(
                      n: nTopics,
                      label: 'विषय / प्रश्नोत्तरी',
                      active: nav.isActive(Panel.topics),
                      onTap: () => nav.go('#/topics'),
                    ),
                    const SizedBox(width: 10),
                    _Stat(
                      n: nGranths,
                      label: 'पवित्र ग्रन्थ',
                      active: nav.isActive(Panel.granths),
                      onTap: () => nav.go('#/granths'),
                    ),
                    const SizedBox(width: 10),
                    _Stat(
                      n: nPramans,
                      label: 'नए प्रमाण',
                      active: nav.isActive(Panel.pramans),
                      onTap: () => nav.go('#/pramans'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MastBtn extends StatelessWidget {
  const _MastBtn({super.key, required this.icon, required this.onTap});
  final String icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    scale: 0.9,
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GColors.gold.withValues(alpha: 0.45)),
      ),
      child: GIcon(icon, size: 20, color: GColors.goldLight),
    ),
  );
}

/// `.stat-item` — glows when its panel is active.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.n,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final int n;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Pressable(
      onTap: onTap,
      scale: 0.95,
      // `.stat-item.active` glow, exactly as the original CSS:
      //   box-shadow: 0 0 0 2px var(--color-gold),
      //               0 0 18px color-mix(in srgb, var(--color-gold-light) 80%, transparent);
      // A CSS box-shadow is only painted OUTSIDE the box, so the translucent tile stays
      // clear; Flutter's BoxShadow would also paint under it, so a painter draws the ring
      // and the glow outside the rounded rect only. It fades in/out (the original snaps).
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: active ? 1 : 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) =>
            CustomPaint(painter: StatGlowPainter(t), child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            // .stat-item: rgba(255,255,255,.06) / gold 35% border; active: gold 28% / gold-light border.
            color: active
                ? GColors.gold.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? GColors.goldLight
                  : GColors.gold.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              CountUp(
                value: n,
                memo: 'mast:$label',
                style: GText.display(
                  size: 22,
                  color: GColors.goldLight,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GText.sans(size: 12, color: GColors.paper, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Outside-only ring + glow of the active header stat (see [_Stat]). [t] is 0…1.
class StatGlowPainter extends CustomPainter {
  StatGlowPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.001) return;
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.save();
    // Clip away the box itself: CSS never paints a box-shadow under the element.
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(60))
        ..addRRect(box),
    );
    // 0 0 18px gold-light 80% → Gaussian sigma = 18 / 2.
    canvas.drawRRect(
      box,
      Paint()
        ..color = GColors.goldLight.withValues(alpha: 0.8 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // 0 0 0 2px gold → a solid 2 px ring hugging the border (radius 8 + 2).
    canvas.drawRRect(
      box.inflate(2),
      Paint()..color = GColors.gold.withValues(alpha: t),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(StatGlowPainter old) => old.t != t;
}

/// `.hamburger` — menu ⇄ x morph.
class _Hamburger extends StatelessWidget {
  const _Hamburger({required this.open});
  final bool open;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Semantics(
        button: true,
        label: open ? 'मेनू बंद करें' : 'मेनू खोलें',
        child: Pressable(
          onTap: AppNav.I.toggleMenu,
          child: Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GColors.paper,
              border: Border.all(color: GColors.creamDark),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: c),
              ),
              child: GIcon(
                open ? 'x' : 'menu',
                key: ValueKey(open),
                size: 22,
                color: GColors.maroon,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `nav` (phone layout) — slides open under the hamburger.
class _NavMenu extends StatelessWidget {
  const _NavMenu({required this.open});
  final bool open;
  static const _items = [
    ('landmark', 'Dashboard', '#/dashboard', Panel.dashboard),
    ('library', 'Granth', '#/granths', Panel.granths),
    ('clipboard-list', 'Topic', '#/topics', Panel.topics),
    ('image', 'प्रमाण', '#/pramans', Panel.pramans),
    ('sparkles', 'तत्त्व AI', '#/ai', Panel.ai),
    // Opens the Photo Highlighter (its own full-screen page, lib/highlighter/): the user app's files.
    ('highlighter', 'Photo Highlighter', '', null),
    ('settings', 'Admin Panel', '#/admin', Panel.adminPanel),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !open
          ? const SizedBox(width: double.infinity)
          : Container(
              decoration: const BoxDecoration(
                color: GColors.brown,
                border: Border(
                  bottom: BorderSide(color: GColors.gold, width: 2),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    Entry(index: i, dx: -16, child: _navBtn(items[i])),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _navBtn((String, String, String, Panel?) it) {
    final active = it.$4 != null && AppNav.I.route.panel == it.$4;
    final color = active
        ? GColors.goldLight
        : GColors.cream.withValues(alpha: 0.68);
    return Builder(
      builder: (context) => Pressable(
        key: ValueKey('nav-${it.$1}'),
        onTap: () {
          if (it.$4 != null) {
            AppNav.I.go(it.$3);
            return;
          }
          if (AppNav.I.menuOpen) AppNav.I.toggleMenu();
          HighlighterLauncher.open(context);
        },
        scale: 0.98,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  GIcon(it.$1, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    it.$2.toUpperCase(),
                    style: GText.sans(
                      size: 14,
                      weight: FontWeight.w600,
                      color: color,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Positioned(
                left: 12,
                right: 12,
                bottom: -2,
                height: 2,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [GColors.saffron, GColors.gold],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.toast` — slides up from the bottom.
class _ToastLayer extends StatelessWidget {
  const _ToastLayer();
  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 24 + MediaQuery.paddingOf(context).bottom,
    child: IgnorePointer(
      child: ValueListenableBuilder<String?>(
        valueListenable: Toast.message,
        builder: (context, msg, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.6),
                end: Offset.zero,
              ).animate(a),
              child: c,
            ),
          ),
          child: msg == null
              ? const SizedBox.shrink()
              : Center(
                  key: ValueKey('${Toast.serial}'),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        MediaQuery.sizeOf(context).width * 0.92,
                        420,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: GColors.brown,
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(
                        left: BorderSide(color: GColors.saffron, width: 3),
                      ),
                    ),
                    child: Text(
                      msg,
                      style: GText.sans(
                        size: 16,
                        weight: FontWeight.w600,
                        color: GColors.goldLight,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}

/// `qn` — the custom scroll rail (arrows + draggable thumb, hides after 700 ms).
class _ScrollRail extends StatefulWidget {
  const _ScrollRail({required this.controller});
  final ScrollController controller;
  @override
  State<_ScrollRail> createState() => _ScrollRailState();
}

class _ScrollRailState extends State<_ScrollRail> {
  bool _show = false;
  bool _drag = false;
  Timer? _hide;

  ScrollController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onScroll);
  }

  @override
  void dispose() {
    c.removeListener(_onScroll);
    _hide?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() => _show = true);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !_drag) setState(() => _show = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!c.hasClients || !c.position.hasContentDimensions)
      return const SizedBox.shrink();
    final p = c.position;
    final max = p.maxScrollExtent;
    if (max <= 8) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context);
    final view = p.viewportDimension;
    // Rail starts below the mast/nav/sync strip while they are on screen (~ 260 px of header).
    final top = math.max(8.0 + pad.top, 300 - p.pixels + pad.top);
    final railH = view - top - 8 - 56;
    if (railH < 48) return const SizedBox.shrink();
    final total = max + view;
    final thumbH = math.max(64.0, math.min(railH, view / total * railH));
    final thumbTop = (p.pixels / max).clamp(0.0, 1.0) * (railH - thumbH);
    void page(int dir) => c.animateTo(
      (p.pixels + dir * view * 0.82).clamp(0, max),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
    Widget arrow(bool up) => GestureDetector(
      onTap: () => page(up ? -1 : 1),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GColors.maroon,
          border: up
              ? const Border(bottom: BorderSide(color: Color(0xFFA66A3F)))
              : const Border(top: BorderSide(color: Color(0xFFA66A3F))),
        ),
        child: Icon(
          up
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: GColors.goldLight,
        ),
      ),
    );
    return Positioned(
      right: 4,
      top: top,
      bottom: 8,
      width: 18,
      child: IgnorePointer(
        ignoring: !_show,
        child: AnimatedOpacity(
          opacity: _show ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                arrow(true),
                Expanded(
                  child: GestureDetector(
                    onVerticalDragStart: (_) => _drag = true,
                    onVerticalDragEnd: (_) {
                      _drag = false;
                      _onScroll();
                    },
                    onVerticalDragUpdate: (d) => c.jumpTo(
                      (p.pixels +
                              d.delta.dy / math.max(1, railH - thumbH) * max)
                          .clamp(0, max),
                    ),
                    onTapDown: (d) => c.jumpTo(
                      ((d.localPosition.dy - thumbH / 2) /
                                  math.max(1, railH - thumbH))
                              .clamp(0.0, 1.0) *
                          max,
                    ),
                    child: Container(
                      color: GColors.paper,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 2,
                            right: 2,
                            top: thumbTop,
                            height: thumbH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: GColors.maroon.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Container(
                                      width: 12,
                                      height: 1.5,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 1.25,
                                      ),
                                      color: GColors.goldLight,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                arrow(false),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
