import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import 'dashboard_screen.dart';
import 'granths_screen.dart';
import 'login_screen.dart';
import 'panel/panel_home.dart';
import 'pramans_screen.dart';
import 'settings_screen.dart';
import 'topics_screen.dart';

/// Lets any tab switch tabs (dashboard cards → goTo('topic') etc.).
class HomeTabs extends InheritedWidget {
  const HomeTabs({super.key, required this.select, required super.child});
  final void Function(int) select;
  static void go(BuildContext context, int i) => context.getInheritedWidgetOfExactType<HomeTabs>()?.select(i);
  @override
  bool updateShouldNotify(HomeTabs old) => false;
}

const kTabBarHeight = 64.0;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _built = <int>{0};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Only the control server is logged in → open on its tab.
    final app = AppScope.of(context);
    if (!app.loggedIn && app.panel.loggedIn) {
      _index = _kPanelTab;
      _built.add(_kPanelTab);
    }
  }

  static const _kPanelTab = 4;

  static const _tabs = [
    (CupertinoIcons.square_grid_2x2, CupertinoIcons.square_grid_2x2_fill, 'डैशबोर्ड'),
    (CupertinoIcons.list_bullet, CupertinoIcons.list_bullet, 'विषय'),
    (CupertinoIcons.book, CupertinoIcons.book_fill, 'ग्रंथ'),
    (CupertinoIcons.photo_on_rectangle, CupertinoIcons.photo_fill_on_rectangle_fill, 'प्रमाण'),
    (CupertinoIcons.slider_horizontal_3, CupertinoIcons.slider_horizontal_3, 'कंट्रोल'),
    (CupertinoIcons.ellipsis_circle, CupertinoIcons.ellipsis_circle_fill, 'अधिक'),
  ];

  /// Tabs 0–3 need the website login; the control tab needs the control-server login.
  Widget _page(int i) => switch (i) {
    0 => _WnmGate(title: 'डैशबोर्ड', child: () => const DashboardScreen()),
    1 => _WnmGate(title: 'विषय', child: () => const TopicsScreen()),
    2 => _WnmGate(title: 'ग्रंथ', child: () => const GranthsScreen()),
    3 => _WnmGate(title: 'प्रमाण', child: () => const PramansScreen()),
    4 => const PanelHome(bottomInset: kTabBarHeight + 20),
    _ => const SettingsScreen(),
  };

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return HomeTabs(
      select: _select,
      child: PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(0);
        },
        child: Stack(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              if (_built.contains(i)) _TabLayer(active: i == _index, child: _page(i)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _GlassTabBar(index: _index, tabs: _tabs, onTap: _select),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the website-data tab only while that login is alive; otherwise a prompt to log in.
class _WnmGate extends StatelessWidget {
  const _WnmGate({required this.title, required this.child});
  final String title;
  final Widget Function() child;
  @override
  Widget build(BuildContext context) {
    return AppSelector<bool>(
      selector: (a) => a.loggedIn,
      builder: (context, app, loggedIn) => loggedIn ? child() : _prompt(context),
    );
  }

  Widget _prompt(BuildContext context) {
    return GlassPage(
      title: title,
      bottomInset: kTabBarHeight + 20,
      slivers: [
        PadSliver(
          child: SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const MessageView(
                  icon: CupertinoIcons.lock,
                  title: 'वेबसाइट में लॉगिन चाहिए',
                  subtitle: 'ग्रंथ/विषय/प्रमाण का डेटा granth.wnmsolutions.com के लॉगिन से चलता है। \'ऐप कंट्रोल\' टैब उससे अलग काम करता है।',
                ),
                PrimaryButton(
                  label: 'वेबसाइट लॉगिन / Login',
                  icon: CupertinoIcons.person_crop_circle,
                  onPressed: () =>
                      Navigator.of(context)
                          .push(CupertinoPageRoute<void>(builder: (_) => const LoginScreen(popOnSuccess: true))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps a tab alive; cross-fades + slight scale when switching; disables heroes/tickers offstage.
/// Once the fade-out has finished the tab is taken [Offstage] (no layout/paint at all) and put
/// back before it fades in, so six tab pages never cost frames while one is showing.
class _TabLayer extends StatefulWidget {
  const _TabLayer({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_TabLayer> createState() => _TabLayerState();
}

class _TabLayerState extends State<_TabLayer> {
  late bool _shown = widget.active;
  Timer? _hide;

  @override
  void didUpdateWidget(covariant _TabLayer old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    _hide?.cancel();
    if (widget.active) {
      _shown = true;
    } else {
      _hide = Timer(const Duration(milliseconds: 340), () {
        if (mounted && !widget.active) setState(() => _shown = false);
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Positioned.fill(
      child: Offstage(
        offstage: !_shown,
        child: IgnorePointer(
          ignoring: !active,
          child: TickerMode(
            enabled: active,
            child: HeroMode(
              enabled: active,
              child: RepaintBoundary(
                child: FadeTransitionLike(active: active, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opacity + scale cross-fade driven by two implicit animations (kept from the previous version).
class FadeTransitionLike extends StatelessWidget {
  const FadeTransitionLike({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: active ? 1 : 0,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOut,
    child: AnimatedScale(
      scale: active ? 1 : 0.985,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: child,
    ),
  );
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.index, required this.tabs, required this.onTap});
  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 10),
      // No BackdropFilter: a live blur under the always-visible bar re-rendered the page behind it
      // on every scrolled frame. A near-opaque fill + RepaintBoundary keeps the glass look cheap.
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: const BoxDecoration(),
          child: Container(
            height: kTabBarHeight,
            decoration: BoxDecoration(
              color: p.barFill.withValues(alpha: p.dark ? 0.95 : 0.93),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: p.glassBorder, width: 0.8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: p.dark ? 0.08 : 0.5),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / tabs.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 520),
                      curve: const _Spring(),
                      left: w * index + 5,
                      top: 6,
                      bottom: 6,
                      width: w - 10,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          color: AppColors.saffron.withValues(alpha: p.dark ? 0.24 : 0.16),
                          border: Border.all(color: AppColors.saffron.withValues(alpha: 0.25), width: 0.7),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(i),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedScale(
                                    scale: i == index ? 1.12 : 1,
                                    duration: const Duration(milliseconds: 380),
                                    curve: const _Spring(),
                                    child: Icon(
                                      i == index ? tabs[i].$2 : tabs[i].$1,
                                      size: 22,
                                      color: i == index ? AppColors.saffron : p.subtext,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 250),
                                    style: TextStyle(
                                      fontFamily: kFont,
                                      fontSize: 11,
                                      height: 1.2,
                                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                      color: i == index ? AppColors.saffron : p.subtext,
                                    ),
                                    child: Text(tabs[i].$3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Spring extends Curve {
  const _Spring();
  @override
  double transformInternal(double t) => Curves.easeOutBack.transform(t);
}
