import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'granths_screen.dart';
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

  static const _tabs = [
    (CupertinoIcons.square_grid_2x2, CupertinoIcons.square_grid_2x2_fill, 'डैशबोर्ड'),
    (CupertinoIcons.list_bullet, CupertinoIcons.list_bullet, 'विषय'),
    (CupertinoIcons.book, CupertinoIcons.book_fill, 'ग्रंथ'),
    (CupertinoIcons.photo_on_rectangle, CupertinoIcons.photo_fill_on_rectangle_fill, 'प्रमाण'),
    (CupertinoIcons.ellipsis_circle, CupertinoIcons.ellipsis_circle_fill, 'अधिक'),
  ];

  Widget _page(int i) => switch (i) {
    0 => const DashboardScreen(),
    1 => const TopicsScreen(),
    2 => const GranthsScreen(),
    3 => const PramansScreen(),
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

/// Keeps a tab alive; cross-fades + slight scale when switching; disables heroes/tickers offstage.
class _TabLayer extends StatelessWidget {
  const _TabLayer({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: TickerMode(
          enabled: active,
          child: HeroMode(
            enabled: active,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: active ? 1 : 0.985,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.index, required this.tabs, required this.onTap});
  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: kTabBarHeight,
            decoration: BoxDecoration(
              color: p.barFill,
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
