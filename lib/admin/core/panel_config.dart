/// Control server (Cloudflare Worker `granth-admin`) settings.
///
/// The base URL lives in exactly one place. To move to a custom domain either
///  * change [kPanelDefaultBase], or
///  * build with `--dart-define=PANEL_BASE=https://panel.example.com`, or
///  * type a new address on the panel login screen (stored on the device).
const String kPanelDefaultBase = String.fromEnvironment(
  'PANEL_BASE',
  defaultValue: 'https://granth-admin.vedpuran8090.workers.dev',
);

/// Admin user name on the control server (there is a single admin).
const String kPanelUsername = 'goutam';

/// Name shown in the server's session list for this app.
const String kPanelClientName = 'Granth Admin app';

/// Returns a clean https base URL (no trailing slash, no path) or null when [raw] is not acceptable.
/// Only https is accepted because the bearer token travels in every request.
String? normalizePanelBase(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      !u.host.contains('.'))
    return null;
  if (u.hasQuery || u.userInfo.isNotEmpty) return null;
  final path = u.path.replaceAll(RegExp(r'/+$'), '');
  return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}$path';
}
