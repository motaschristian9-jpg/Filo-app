import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../onboarding/design.dart';
import 'quiz_repository.dart';
import 'quiz_source_dialog.dart';
import 'question_types.dart';

class QuizEditor extends StatefulWidget {
  const QuizEditor({super.key, required this.repository, this.id, this.existing});
  final QuizRepository repository;
  final String? id;
  final Map<String, dynamic>? existing;
  @override
  State<QuizEditor> createState() => _QuizEditorState();
}

class _QuizEditorState extends State<QuizEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _titleFocus = FocusNode();
  late final _id = widget.id ?? widget.repository.collection.doc().id;
  late final _title = TextEditingController(text: widget.existing?['title'] as String? ?? '');
  late final _minutes = TextEditingController(text: '${widget.existing?['minutes'] ?? 30}');
  late String _kind = widget.existing?['kind'] as String? ?? 'quiz';
  late final List<QuestionDraft> _questions = widget.existing == null ? [QuestionDraft()]
    : (widget.existing!['questions'] as List).map((q) => QuestionDraft(Map<String, dynamic>.from(q as Map))).toList();
  bool _busy = false;
  String? _error;
  Future<void> _generate() async {
    final input = await showDialog<QuizSource>(context: context,
      builder: (_) => QuizSourceDialog(classId: widget.repository.classId,
        remaining: 50 - _questions.length));
    if (input == null || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final generated = await widget.repository.generate(input.notes, input.count, input.materialIds, input.counts);
      if (!mounted) return;
      setState(() {
        if (_questions.length == 1 && _questions.first.prompt.text.isEmpty &&
            _questions.first.options.every((c) => c.text.isEmpty)) {
          _questions.removeAt(0).dispose();
        }
        _questions.addAll(generated.map(QuestionDraft.new));
      });
    } catch (error) {
      if (mounted) setState(() => _error = error is QuizGenerationException
        ? error.message : 'Could not generate. Check your connection and try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() {
    _scroll.dispose(); _titleFocus.dispose();
    _title.dispose(); _minutes.dispose();
    for (final q in _questions) { q.dispose(); }
    super.dispose();
  }
  String? _required(String? value) => (value ?? '').trim().isEmpty ? 'Required' : null;
  Future<void> _save({bool publish = false}) async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      _form.currentState!.validate();
      _titleFocus.requestFocus();
      if (_scroll.hasClients) {
        await _scroll.animateTo(0, duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
      return;
    }
    if (!_form.currentState!.validate()) return;
    for (final q in _questions) {
      if (q.type == 'multiple_choice') {
        final values = q.options.map((c) => c.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')).toSet();
        if (values.length != 4) {
          setState(() => _error = 'Each multiple-choice question needs four distinct options.');
          if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          return;
        }
      }
      if (q.type == 'identification' && (q.lines(q.accepted.text).length > 20 ||
          q.lines(q.accepted.text).any((s) => s.length > 500))) {
        setState(() => _error = 'Use up to 20 accepted answers, each 500 characters or fewer.');
        if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      await widget.repository.save(_id, {'title': _title.text.trim(), 'kind': _kind,
        'minutes': int.parse(_minutes.text), 'status': 'draft',
        'questions': _questions.map((q) => q.toMap()).toList()});
      if (publish) await widget.repository.publish(_id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Check your connection and class status.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(widget.id == null ? 'New assessment' : 'Edit assessment')),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
      child: Form(key: _form, child: ListView(controller: _scroll, padding: const EdgeInsets.all(24), children: [
        if (_error != null) ErrorNotice(_error!),
        TextFormField(controller: _title, focusNode: _titleFocus, enabled: !_busy, maxLength: 120,
          decoration: const InputDecoration(labelText: 'Title'), validator: _required),
        const SizedBox(height: 16),
        Wrap(spacing: 12, children: [for (final kind in ['quiz', 'exam']) ChoiceChip(
          label: Text(kind == 'quiz' ? 'Quiz' : 'Exam'), selected: _kind == kind,
          onSelected: _busy ? null : (_) => setState(() => _kind = kind))]),
        const SizedBox(height: 16),
        TextFormField(controller: _minutes, enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Time limit', suffixText: 'minutes'),
          validator: (value) { final n = int.tryParse(value ?? '');
            return n == null || n < 1 || n > 180 ? 'Choose 1–180 minutes.' : null; }),
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Generate with AI')),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        const SizedBox(height: 20),
        for (var i = 0; i < _questions.length; i++) _question(i),
        OutlinedButton.icon(onPressed: _busy || _questions.length >= 50 ? null
          : () => setState(() => _questions.add(QuestionDraft())),
          icon: const Icon(Icons.add_rounded), label: const Text('Add question')),
      ])),
    ))),
    bottomNavigationBar: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(24),
      child: Center(heightFactor: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PrimaryButton(label: 'Publish', busy: _busy,
            onPressed: _busy ? null : () => _save(publish: true)),
          TextButton(onPressed: _busy ? null : () => _save(), child: const Text('Save draft')),
        ]))))),
  ));
  Widget _question(int index) {
    final q = _questions[index];
    return Padding(key: ObjectKey(q), padding: const EdgeInsets.only(bottom: 24),
      child: Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line),
          borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('Question ${index + 1}',
            style: Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip: 'Remove question', onPressed: _busy || _questions.length == 1
              ? null : () => setState(() { _questions.removeAt(index); q.dispose(); }),
              icon: const Icon(Icons.delete_outline_rounded))]),
          TextFormField(controller: q.prompt, enabled: !_busy, maxLength: 1000,
            maxLines: null, decoration: const InputDecoration(labelText: 'Question'), validator: _required),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: q.type,
            decoration: const InputDecoration(labelText: 'Question type'),
            items: [for (final entry in questionTypes.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value))],
            onChanged: _busy ? null : (value) => setState(() { q.type = value!; q.answer = 0; })),
          const SizedBox(height: 12),
          TextFormField(controller: q.points, enabled: !_busy,
            keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Points'),
            validator: (v) { final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > 100 ? 'Choose 1–100 points.' : null; }),
          const SizedBox(height: 12),
          if (q.type == 'identification') TextFormField(controller: q.accepted, enabled: !_busy,
            maxLines: null, maxLength: 5000,
            decoration: const InputDecoration(labelText: 'Accepted answers', helperText: 'One answer or alternative per line'),
            validator: _required),
          if (q.type == 'enumeration') ...[
            TextFormField(controller: q.expected, enabled: !_busy, maxLines: null, maxLength: 5000,
              decoration: const InputDecoration(labelText: 'Expected answers', helperText: 'One item per line; up to 20'),
              validator: (v) { final lines = q.lines(v ?? '');
                final unique = lines.map((s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')).toSet();
                return lines.isEmpty || lines.length > 20 || unique.length != lines.length
                  ? 'Enter 1–20 distinct items.' : null; }),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Order matters'),
              value: q.ordered, onChanged: _busy ? null : (v) => setState(() => q.ordered = v)),
          ],
          if (q.type == 'essay') TextFormField(controller: q.rubric, enabled: !_busy,
            minLines: 3, maxLines: 8, maxLength: 5000,
            decoration: const InputDecoration(labelText: 'Grading rubric'), validator: _required),
          if (q.type == 'multiple_choice' || q.type == 'true_false') ...[
          const Text('Select the correct answer'),
          for (var option = 0; option < (q.type == 'true_false' ? 2 : 4); option++) Padding(
            padding: const EdgeInsets.only(top: 12), child: Row(children: [
              IconButton(tooltip: 'Correct answer ${option + 1}',
                onPressed: _busy ? null : () => setState(() => q.answer = option),
                icon: Icon(q.answer == option ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: q.answer == option ? teal : muted)),
              if (q.type == 'true_false') Expanded(child: Text(option == 0 ? 'True' : 'False'))
              else Expanded(child: TextFormField(controller: q.options[option], enabled: !_busy,
                maxLength: 500, decoration: InputDecoration(labelText: 'Option ${option + 1}'),
                validator: _required)),
            ])),
          ],
        ])));
  }
}
