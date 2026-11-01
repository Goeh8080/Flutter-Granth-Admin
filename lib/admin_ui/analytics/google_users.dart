import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../widgets/common.dart';
import '../admin_kit.dart';
import 'analytics_kit.dart';

/// Every Firebase Auth (Google) user — GET /admin/api/google-users (Identity Toolkit accounts:batchGet).
class GoogleUsersScreen extends StatefulWidget {
  const GoogleUsersScreen({super.key});
  @override
  State<GoogleUsersScreen> createState() => _GoogleUsersScreenState();
}

class _GoogleUsersScreenState extends State<GoogleUsersScreen> {
  Map<String, dynamic>? _d;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await anGet('/google-users');
    if (mounted) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final users = d == null ? const <Map<String, dynamic>>[] : anL(d['users']);
    final q = _q.toLowerCase();
    final shown = users
        .where(
          (u) =>
              q.isEmpty ||
              anS(u['name']).toLowerCase().contains(q) ||
              anS(u['email']).toLowerCase().contains(q),
        )
        .toList();
    return AdminSubPage(
      title: 'Google यूज़र',
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d == null)
                const EmptyState(title: 'लोड हो रहा है…', spinner: true)
              else ...[
                if (d['_error'] != null || d['error'] != null)
                  anCard([
                    anNote(
                      'त्रुटि: ${anS(d['_error'] ?? d['error'])} ${anS(d['detail'])}',
                    ),
                  ]),
                anCard([
                  anStats([
                    AnStat(
                      'कुल Google यूज़र',
                      '${users.length}',
                      GColors.maroon,
                    ),
                    AnStat(
                      'अभी ऑनलाइन',
                      '${users.where((u) => u['online'] == true).length}',
                      GColors.online,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'नाम या Gmail खोजें',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ]),
                for (final u in shown)
                  anCard(key: ValueKey('gu-${anS(u['uid'])}'), [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: GColors.creamDark,
                              backgroundImage: anS(u['photo']).isEmpty
                                  ? null
                                  : NetworkImage(anS(u['photo'])),
                              child: anS(u['photo']).isEmpty
                                  ? Text(
                                      anS(u['name']).isEmpty
                                          ? '?'
                                          : anS(u['name']).substring(0, 1),
                                      style: GText.sans(
                                        weight: FontWeight.w800,
                                        color: GColors.maroon,
                                      ),
                                    )
                                  : null,
                            ),
                            if (u['online'] == true)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: GColors.online,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anS(u['name']).isEmpty
                                    ? '(नाम नहीं)'
                                    : anS(u['name']),
                                style: GText.sans(
                                  size: 15,
                                  weight: FontWeight.w800,
                                  color: GColors.maroon,
                                ),
                              ),
                              SelectableText(
                                anS(u['email']),
                                style: GText.sans(
                                  size: 13,
                                  color: GColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              anNote('बना: ${anIst(u['created_at'])}'),
                              anNote(
                                'आख़िरी लॉगिन: ${anIst(u['last_login_at'])}',
                              ),
                              if (u['disabled'] == true)
                                anNote('⚠ अक्षम (disabled)'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ]),
                if (shown.isEmpty) anNote('कोई यूज़र नहीं'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
