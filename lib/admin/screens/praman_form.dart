import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/toast.dart';

/// Add/edit praman. [topicId]/[granthId] prefill on add (addPramanForTopic / addPramanForGranth).
Future<bool> showPramanForm(
  BuildContext context, {
  Praman? praman,
  int? topicId,
  int? granthId,
}) async =>
    await showGlassSheet<bool>(
      context,
      (_) => _PramanForm(praman: praman, topicId: topicId, granthId: granthId),
    ) ??
    false;

class _PramanForm extends StatefulWidget {
  const _PramanForm({this.praman, this.topicId, this.granthId});
  final Praman? praman;
  final int? topicId, granthId;
  @override
  State<_PramanForm> createState() => _PramanFormState();
}

class _PramanFormState extends State<_PramanForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _chapter = TextEditingController();
  final _page = TextEditingController();
  final _yt = TextEditingController();
  final _ytStart = TextEditingController(text: '0');
  final _ytDesc = TextEditingController();
  bool _active = true;
  int? _topicId, _granthId;
  XFile? _image;
  Praman? _current;
  bool _busy = false, _loading = false;

  @override
  void initState() {
    super.initState();
    final app = AppScope.of(context);
    _topicId = widget.topicId;
    _granthId = widget.granthId;
    final p = widget.praman;
    final futures = <Future>[app.ensureLookups()];
    if (p != null) {
      _fill(p);
      futures.add(
        app.api.praman(p.id).then((f) {
          if (mounted) _fill(f);
        }),
      );
    }
    _loading = true;
    Future.wait(futures)
        .catchError((e) {
          showError(e);
          return <dynamic>[];
        })
        .whenComplete(() {
          if (mounted) setState(() => _loading = false);
        });
  }

  void _fill(Praman p) {
    _current = p;
    _title.text = p.title;
    _desc.text = p.description;
    _chapter.text = '${p.chapterNumber}';
    _page.text = '${p.pageNumber}';
    _yt.text = p.youtubeUrl;
    _ytStart.text = '${p.youtubeStart}';
    _ytDesc.text = p.youtubeDesc;
    _active = p.isActive;
    _topicId = p.topicId == 0 ? null : p.topicId;
    _granthId = p.granthId == 0 ? null : p.granthId;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    void err(String m) => showToast(m, error: true);
    if (title.isEmpty)
      return err('कृपया प्रमाण शीर्षक डालें / Please enter a praman title');
    if (_topicId == null)
      return err('कृपया विषय चुनें / Please select praman topic');
    if (_granthId == null)
      return err('कृपया ग्रंथ चुनें / Please select praman granth');
    final page = int.tryParse(_page.text.trim());
    if (page == null)
      return err('कृपया सही पेज नंबर डालें / Please enter correct page number');
    if (page <= 0)
      return err('कृपया पेज नंबर डालें / Please enter page number');
    if (widget.praman == null && _image == null)
      return err('कृपया प्रमाण चित्र चुनें / Please select praman image');

    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await runWrite(
      () => app.api.savePraman(
        id: widget.praman?.id,
        title: title,
        isActive: _active,
        description: _desc.text,
        topicId: _topicId!,
        granthId: _granthId!,
        chapterNumber: _chapter.text.trim(),
        pageNumber: _page.text.trim(),
        // the web embeds youtube.com/embed/<value>, so store the bare video id
        youtubeUrl: extractYoutubeId(_yt.text),
        youtubeDesc: _ytDesc.text.trim(),
        youtubeStart: _ytStart.text.trim(),
        imagePath: _image?.path,
      ),
      success: 'प्रमाण सहेजा गया / Praman saved',
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
    // Only the lookup lists matter here (labels); other AppState notifications don't rebuild the form.
    return AppSelector<(Object, Object)>(
      selector: (a) => (a.topics, a.granths),
      builder: (context, app, _) => _form(context, app),
    );
  }

  Widget _form(BuildContext context, AppState app) {
    String? topicLabel, granthLabel;
    for (final t in app.topics) {
      if (t.id == _topicId) topicLabel = '${t.position}. ${oneLine(t.title)}';
    }
    for (final g in app.granths) {
      if (g.id == _granthId) granthLabel = '${g.position}. ${oneLine(g.title)}';
    }
    topicLabel ??= _topicId == null
        ? null
        : (_current?.topicTitle.isNotEmpty == true
              ? oneLine(_current!.topicTitle)
              : '#$_topicId');
    granthLabel ??= _granthId == null
        ? null
        : (_current?.granthTitle.isNotEmpty == true
              ? oneLine(_current!.granthTitle)
              : '#$_granthId');
    return FormSheet(
      title: widget.praman == null
          ? 'नया प्रमाण / New Praman'
          : 'प्रमाण संपादित / Edit Praman',
      busy: _busy,
      loading: _loading,
      onSave: _save,
      children: [
        GlassField(
          label: 'प्रमाण शीर्षक / Praman Title',
          controller: _title,
          maxLines: 4,
          required: true,
        ),
        GlassField(
          label: 'विवरण / Description',
          controller: _desc,
          maxLines: 6,
        ),
        ActiveSwitch(
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        PickerRow(
          label: 'विषय / Topic',
          required: true,
          value: topicLabel,
          onTap: () async {
            final t = await pickFromList(
              context,
              title: 'विषय चुनें / Select Topic',
              items: app.topics,
              labelOf: (t) => '${t.position}. ${t.title}',
            );
            if (t != null) setState(() => _topicId = t.id);
          },
        ),
        PickerRow(
          label: 'ग्रंथ / Granth',
          required: true,
          value: granthLabel,
          onTap: () async {
            final g = await pickFromList(
              context,
              title: 'ग्रंथ चुनें / Select Granth',
              items: app.granths,
              labelOf: (g) => '${g.position}. ${g.title}',
              subtitleOf: (g) => g.author,
            );
            if (g != null) setState(() => _granthId = g.id);
          },
        ),
        Row(
          children: [
            Expanded(
              child: GlassField(
                label: 'अध्याय / Chapter No.',
                controller: _chapter,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassField(
                label: 'पेज / Page No.',
                controller: _page,
                keyboardType: TextInputType.number,
                required: true,
              ),
            ),
          ],
        ),
        ImagePickField(
          label: 'प्रमाण चित्र / Praman Image',
          required: widget.praman == null,
          file: _image,
          existingUrl: _current?.imageUrl,
          onPicked: (f) => setState(() => _image = f),
        ),
        const SectionTitle('YouTube'),
        GlassField(
          label: 'YouTube वीडियो ID या URL',
          controller: _yt,
          placeholder: 'HLhZeRregP0 / https://youtu.be/…',
          keyboardType: TextInputType.url,
        ),
        GlassField(
          label: 'शुरू (सेकंड) / Start From (sec)',
          controller: _ytStart,
          keyboardType: TextInputType.number,
        ),
        GlassField(
          label: 'YouTube विवरण / Description',
          controller: _ytDesc,
          maxLines: 3,
        ),
      ],
    );
  }
}
