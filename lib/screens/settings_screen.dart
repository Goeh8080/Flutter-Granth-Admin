import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/glass.dart';
import '../widgets/common.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/links.dart';
import '../widgets/motion.dart';
import 'feedback_screen.dart';
import 'home_shell.dart';
import 'pramans_screen.dart';
import 'topics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, listen: true);
    final p = Palette.of(context);
    void push(Widget w) => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => w));
    return GlassPage(
      title: 'अधिक / More',
      bottomInset: kTabBarHeight + 20,
      slivers: [
        PadSliver(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SliverToBoxAdapter(
            child: Glass(
              blur: 16,
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [AppColors.saffron, AppColors.maroon]),
                    ),
                    child: Text(
                      app.username.isEmpty ? 'A' : app.username[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.username,
                          style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text('Admin • granth.wnmsolutions.com', style: TextStyle(color: p.subtext, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const PadSliver(child: SliverToBoxAdapter(child: SectionTitle('रूप / Appearance'))),
        PadSliver(
          child: SliverToBoxAdapter(
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<ThemeMode>(
                groupValue: app.themeMode,
                backgroundColor: p.fieldFill,
                thumbColor: p.dark ? const Color(0xFF3A3340) : Colors.white,
                children: const {
                  ThemeMode.system: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('System')),
                  ThemeMode.light: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Light')),
                  ThemeMode.dark: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Dark')),
                },
                onValueChanged: (m) => app.setTheme(m ?? ThemeMode.system),
              ),
            ),
          ),
        ),
        const PadSliver(child: SliverToBoxAdapter(child: SectionTitle('पेज / Pages'))),
        PadSliver(
          child: SliverList.list(
            children: [
              _Row(
                CupertinoIcons.eye_slash,
                'निष्क्रिय विषय / Inactive topics',
                () => push(const TopicsScreen(inactiveOnly: true)),
              ),
              _Row(
                CupertinoIcons.play_rectangle,
                'YouTube प्रमाण',
                () => push(const PramansScreen(initialFilter: PramanFilter.youtube, standalone: true)),
              ),
              _Row(CupertinoIcons.chat_bubble_2, 'फीडबैक / Feedback', () => push(const FeedbackScreen())),
              _Row(
                CupertinoIcons.paintbrush,
                'Photo Merger & Highlighter (web)',
                () => openExternal('$kSiteBase/highlighter.html'),
              ),
              _Row(CupertinoIcons.globe, 'वेब पैनल खोलें / Open web panel', () => openExternal('$kSiteBase/')),
              _Row(
                CupertinoIcons.mail,
                'sadgranthpraman@gmail.com',
                () => openExternal('mailto:sadgranthpraman@gmail.com'),
              ),
            ],
          ),
        ),
        const PadSliver(child: SliverToBoxAdapter(child: SectionTitle('खाता / Account'))),
        PadSliver(
          child: SliverToBoxAdapter(
            child: _Row(CupertinoIcons.square_arrow_right, 'लॉग आउट / Logout', () async {
              if (await confirmDialog(context, title: 'लॉग आउट करें? / Log out?', confirm: 'Logout')) {
                await app.logout();
              }
            }, destructive: true),
          ),
        ),
        PadSliver(
          child: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                'ग्रंथ प्रबंधन Admin • v1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.subtext, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.onTap, {this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableGlass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        radius: 16,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: destructive ? AppColors.red : AppColors.saffron, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(color: destructive ? AppColors.red : p.text, fontSize: 15.5)),
            ),
            Icon(CupertinoIcons.chevron_right, size: 15, color: p.subtext),
          ],
        ),
      ),
    );
  }
}
