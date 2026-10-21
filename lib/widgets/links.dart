import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import 'toast.dart';

/// Same URLs the web panel shares (shareLink in script.js).
Uri shareUri(String type, int id) {
  final q = switch (type) {
    'topic' => 'topic=$id',
    'granth' => 'granth=$id',
    _ => 'id=$id',
  };
  return Uri.parse('$kSiteBase/praman.php?$q');
}

Future<void> shareItem(String type, int id, String title) async {
  final title0 = switch (type) {
    'topic' => 'Topic Praman',
    'granth' => 'Granth',
    _ => 'Praman',
  };
  final url = shareUri(type, id);
  try {
    await SharePlus.instance.share(ShareParams(text: '${title.replaceAll('\n', ' ')}\n$url', subject: title0));
  } catch (_) {
    showToast('शेयर नहीं हो सका / Sharing failed', error: true);
  }
}

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) {
    showToast('अमान्य लिंक / Invalid link', error: true);
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) showToast('लिंक नहीं खुला / Could not open link', error: true);
}
