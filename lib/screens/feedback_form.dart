import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/toast.dart';

/// saveFeedback() → create_feedback
Future<bool> showFeedbackForm(BuildContext context) async =>
    await showGlassSheet<bool>(context, (_) => const _FeedbackForm()) ?? false;

class _FeedbackForm extends StatefulWidget {
  const _FeedbackForm();
  @override
  State<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<_FeedbackForm> {
  final _name = TextEditingController();
  final _mob = TextEditingController();
  final _desc = TextEditingController();
  int? _topicId, _granthId, _pramanId;
  String? _topicL, _granthL, _pramanL;
  XFile? _image;
  bool _busy = false, _loading = true;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    Future.wait([app.ensureLookups(), if (app.pramans.isEmpty) app.loadPramans()])
        .catchError((e) {
          showError(e);
          return <dynamic>[];
        })
        .whenComplete(() {
          if (mounted) setState(() => _loading = false);
        });
  }

  Future<void> _save() async {
    void err(String m) => showToast(m, error: true);
    if (_name.text.trim().isEmpty) return err('कृपया अपना नाम डालें / Please enter your name');
    if (_desc.text.trim().isEmpty) return err('कृपया विवरण डालें / Please enter a feedback description');
    if (_mob.text.trim().isEmpty) return err('कृपया मोबाइल नंबर डालें / Please enter a mobile number');
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await runWrite(
      () => app.api.createFeedback(
        name: _name.text.trim(),
        mob: _mob.text.trim(),
        description: _desc.text,
        topicId: _topicId,
        granthId: _granthId,
        pramanId: _pramanId,
        imagePath: _image?.path,
      ),
      success: 'फीडबैक सहेजा गया / Feedback saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      app.bump();
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSelector<(Object, Object, Object)>(
      selector: (a) => (a.topics, a.granths, a.pramans),
      builder: (context, app, _) => _form(context, app),
    );
  }

  Widget _form(BuildContext context, AppState app) {
    return FormSheet(
      title: 'नया फीडबैक / Create Feedback',
      busy: _busy,
      loading: _loading,
      onSave: _save,
      children: [
        GlassField(label: 'नाम / Name', controller: _name, required: true),
        GlassField(
          label: 'मोबाइल नंबर / Mobile Number',
          controller: _mob,
          keyboardType: TextInputType.phone,
          required: true,
        ),
        GlassField(label: 'विवरण / Description', controller: _desc, maxLines: 5, required: true),
        PickerRow(
          label: 'विषय / Topic',
          value: _topicL,
          onClear: () => setState(() => _topicId = _topicL = null),
          onTap: () async {
            final t = await pickFromList(
              context,
              title: 'विषय चुनें / Select Topic',
              items: app.topics,
              labelOf: (t) => '${t.position}. ${t.title}',
            );
            if (t != null) {
              setState(() {
                _topicId = t.id;
                _topicL = '${t.position}. ${oneLine(t.title)}';
              });
            }
          },
        ),
        PickerRow(
          label: 'ग्रंथ / Granth',
          value: _granthL,
          onClear: () => setState(() => _granthId = _granthL = null),
          onTap: () async {
            final g = await pickFromList(
              context,
              title: 'ग्रंथ चुनें / Select Granth',
              items: app.granths,
              labelOf: (g) => '${g.position}. ${g.title}',
            );
            if (g != null) {
              setState(() {
                _granthId = g.id;
                _granthL = '${g.position}. ${oneLine(g.title)}';
              });
            }
          },
        ),
        PickerRow(
          label: 'प्रमाण / Praman',
          value: _pramanL,
          onClear: () => setState(() => _pramanId = _pramanL = null),
          onTap: () async {
            final p = await pickFromList(
              context,
              title: 'प्रमाण चुनें / Select Praman',
              items: app.pramans,
              labelOf: (p) => '${p.id}. ${p.title}',
            );
            if (p != null) {
              setState(() {
                _pramanId = p.id;
                _pramanL = '${p.id}. ${oneLine(p.title)}';
              });
            }
          },
        ),
        ImagePickField(label: 'चित्र / Image', file: _image, onPicked: (f) => setState(() => _image = f)),
      ],
    );
  }
}
