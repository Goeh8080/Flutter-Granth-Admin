import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/form_sheet.dart';
import '../widgets/motion.dart';
import '../widgets/toast.dart';

/// Add (topic == null) or edit a topic. Returns true when saved.
Future<bool> showTopicForm(BuildContext context, {Topic? topic}) async =>
    await showGlassSheet<bool>(context, (_) => _TopicForm(topic: topic)) ?? false;

class _TopicForm extends StatefulWidget {
  const _TopicForm({this.topic});
  final Topic? topic;
  @override
  State<_TopicForm> createState() => _TopicFormState();
}

class _TopicFormState extends State<_TopicForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _active = true;
  bool _busy = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final t = widget.topic;
    if (t != null) {
      _fill(t);
      _loading = true;
      // like editTopic(): fetch fresh values with get_topic
      AppScope.of(context).api
          .topic(t.id)
          .then((f) {
            if (mounted) setState(() => _fill(f));
          })
          .catchError((_) {})
          .whenComplete(() {
            if (mounted) setState(() => _loading = false);
          });
    }
  }

  void _fill(Topic t) {
    _title.text = t.title;
    _desc.text = t.description;
    _active = t.isActive;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast('कृपया विषय का शीर्षक डालें / Please enter a topic title', error: true);
      return;
    }
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final ok = await runWrite(
      () => app.api.saveTopic(id: widget.topic?.id, title: title, description: _desc.text, isActive: _active),
      success: widget.topic == null ? 'विषय बनाया गया / Topic created' : 'विषय सहेजा गया / Topic saved',
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
      title: widget.topic == null ? 'नया विषय / New Topic' : 'विषय संपादित / Edit Topic',
      busy: _busy,
      loading: _loading,
      onSave: _save,
      children: [
        GlassField(label: 'विषय शीर्षक / Topic Title', controller: _title, maxLines: 4, required: true),
        GlassField(label: 'विवरण / Description', controller: _desc, maxLines: 6),
        ActiveSwitch(value: _active, onChanged: (v) => setState(() => _active = v)),
      ],
    );
  }
}
