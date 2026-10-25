import 'package:flutter/cupertino.dart';

import '../services/granth_api.dart';
import '../theme/app_theme.dart';
import 'toast.dart';

/// Layout for add/edit forms shown inside a glass sheet.
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.busy = false,
    this.loading = false,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool busy;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Row(
              children: [
                CupertinoButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('रद्द करें')),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
                  ),
                ),
                CupertinoButton(
                  onPressed: busy || loading ? null : onSave,
                  child: busy
                      ? const CupertinoActivityIndicator()
                      : const Text('सहेजें', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Flexible(
            child: loading
                ? const Padding(padding: EdgeInsets.all(48), child: CupertinoActivityIndicator(radius: 14))
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Runs a write with a toast on success/failure. Returns true on success.
Future<bool> runWrite(Future<void> Function() f, {required String success}) async {
  try {
    await f();
    showToast(success);
    return true;
  } on ApiException catch (e) {
    showError(e);
    return false;
  } catch (e) {
    showError(e);
    return false;
  }
}
