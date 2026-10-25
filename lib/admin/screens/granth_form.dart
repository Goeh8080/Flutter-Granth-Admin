import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/toast.dart';

Future<bool> showGranthForm(BuildContext context, {Granth? granth}) async =>
    await showGlassSheet<bool>(context, (_) => _GranthForm(granth: granth)) ??
    false;

class _GranthForm extends StatefulWidget {
  const _GranthForm({this.granth});
  final Granth? granth;
  @override
  State<_GranthForm> createState() => _GranthFormState();
}

class _GranthFormState extends State<_GranthForm> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _desc = TextEditingController();
  final _pdf = TextEditingController();
  bool _active = true;
  XFile? _image, _editor;
  Granth? _current;
  bool _busy = false, _loading = false;

  @override
  void initState() {
    super.initState();
    final g = widget.granth;
    if (g != null) {
      _fill(g);
      _loading = true;
      AppScope.of(context).api
          .granth(g.id)
          .then((f) {
            if (mounted) setState(() => _fill(f));
          })
          .catchError((_) {})
          .whenComplete(() {
            if (mounted) setState(() => _loading = false);
          });
    }
  }

  void _fill(Granth g) {
    _current = g;
    _title.text = g.title;
    _author.text = g.author;
    _desc.text = g.description;
    _pdf.text = g.pdfUrl;
    _active = g.isActive;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(
        'कृपया ग्रंथ का नाम डालें / Please enter Granth title',
        error: true,
      );
      return;
    }
    if (_author.text.trim().isEmpty) {
      showToast('कृपया लेखक डालें / Please enter Granth author', error: true);
      return;
    }
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await runWrite(
      () => app.api.saveGranth(
        id: widget.granth?.id,
        title: title,
        author: _author.text,
        description: _desc.text,
        pdfUrl: _pdf.text,
        isActive: _active,
        imagePath: _image?.path,
        editorImagePath: _editor?.path,
      ),
      success: 'ग्रंथ सहेजा गया / Granth saved',
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
    return FormSheet(
      title: widget.granth == null
          ? 'नया ग्रंथ / New Granth'
          : 'ग्रंथ संपादित / Edit Granth',
      busy: _busy,
      loading: _loading,
      onSave: _save,
      children: [
        GlassField(
          label: 'ग्रंथ शीर्षक / Granth Title',
          controller: _title,
          maxLines: 3,
          required: true,
        ),
        GlassField(
          label: 'लेखक / Author / Rishi',
          controller: _author,
          required: true,
        ),
        GlassField(
          label: 'विवरण / Description',
          controller: _desc,
          maxLines: 5,
        ),
        ActiveSwitch(
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        GlassField(
          label: 'ग्रंथ PDF URL',
          controller: _pdf,
          placeholder: 'https://…/granth.pdf',
          keyboardType: TextInputType.url,
        ),
        ImagePickField(
          label: 'ग्रंथ चित्र / Granth Image',
          file: _image,
          existingUrl: _current?.imageUrl,
          onPicked: (f) => setState(() => _image = f),
        ),
        ImagePickField(
          label: 'विवरण चित्र / Vivran (Editor) Image',
          file: _editor,
          existingUrl: _current?.editorImageUrl,
          onPicked: (f) => setState(() => _editor = f),
        ),
      ],
    );
  }
}
