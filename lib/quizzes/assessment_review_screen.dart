import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../materials/supabase_file_storage.dart';
import '../onboarding/design.dart';

Future<Map<String, dynamic>> _reviewApi(Map<String, dynamic> body) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Signed out');
  final token = await user.getIdToken();
  final client = http.Client();
  try {
    final response = await client.post(Uri.parse('$supabaseUrl/functions/v1/assessment-review'),
      headers: {'apikey': supabasePublishableKey, 'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body)).timeout(const Duration(seconds: 45));
    if (response.statusCode != 200 || FirebaseAuth.instance.currentUser?.uid != user.uid) throw StateError('Review failed');
    return jsonDecode(response.body) as Map<String, dynamic>;
  } finally { client.close(); }
}

class AssessmentReviewScreen extends StatefulWidget {
  const AssessmentReviewScreen({super.key, required this.classId, required this.id, required this.title});
  final String classId, id, title;
  @override
  State<AssessmentReviewScreen> createState() => _AssessmentReviewScreenState();
}
class _AssessmentReviewScreenState extends State<AssessmentReviewScreen> {
  final List<dynamic> _attempts = [];
  List<dynamic> _questions = [];
  String? _cursor, _error;
  bool _busy = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _reviewApi({'action': 'list', 'classId': widget.classId,
        'assessmentId': widget.id, if (more) 'cursor': _cursor});
      if (!mounted) return;
      setState(() {
        if (!more) _attempts.clear();
        _attempts.addAll(result['attempts'] as List); _questions = result['questions'] as List;
        _cursor = result['cursor'] as String?;
      });
    } catch (_) { if (mounted) setState(() => _error = 'Could not load results. Try again.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.title)),
    body: _busy && _attempts.isEmpty ? const FiloSkeleton() : ListView(padding: const EdgeInsets.all(24), children: [
      Text('Student results', style: Theme.of(context).textTheme.headlineMedium),
      TextButton(onPressed: _busy ? null : () => _load(), child: const Text('Refresh')),
      if (_error != null) ErrorNotice(_error!),
      if (_attempts.isEmpty && !_busy && _error == null) const Text('No attempts yet.'),
      for (final a in _attempts) Card(child: ListTile(title: Text(a['name'] as String),
        subtitle: Text(a['status'] == 'active' ? 'In progress' : a['needsReview'] == true
          ? 'Awaiting review' : '${a['score']} / ${a['totalPoints'] ?? _questions.length}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: a['status'] != 'submitted' ? null : () async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _ReviewEditor(
            classId: widget.classId, id: widget.id, attempt: Map<String, dynamic>.from(a as Map), questions: _questions)));
          if (mounted) _load();
        })),
      if (_cursor != null) TextButton(onPressed: _busy ? null : () => _load(more: true), child: const Text('Load more')),
    ]));
}

class _ReviewEditor extends StatefulWidget {
  const _ReviewEditor({required this.classId, required this.id, required this.attempt, required this.questions});
  final String classId, id;
  final Map<String, dynamic> attempt;
  final List<dynamic> questions;
  @override
  State<_ReviewEditor> createState() => _ReviewEditorState();
}
class _ReviewEditorState extends State<_ReviewEditor> {
  final _form = GlobalKey<FormState>();
  late final _grades = {for (var i = 0; i < widget.questions.length; i++)
    if (widget.questions[i]['type'] == 'essay') i: TextEditingController(
      text: (widget.attempt['grades'] as List?)?[i]?.toString() ?? '')};
  late final _feedback = TextEditingController(text: widget.attempt['feedback'] as String? ?? '');
  bool _busy = false;
  String? _error;
  @override
  void dispose() { for (final c in _grades.values) { c.dispose(); } _feedback.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _reviewApi({'action': 'review', 'classId': widget.classId, 'assessmentId': widget.id,
        'studentUid': widget.attempt['uid'], 'feedback': _feedback.text.trim(),
        'essayGrades': {for (final e in _grades.entries) '${e.key}': num.parse(e.value.text)}});
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => _error = 'Could not save review. Please retry.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  String _answer(dynamic a, dynamic q) {
    if (a is int) return a < 0 ? 'Unanswered' : (q['options'] as List)[a] as String;
    if (a is Map) return (a['entries'] as List).join('\n');
    return (a as String).trim().isEmpty ? 'Unanswered' : a;
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(widget.attempt['name'] as String)),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(24), children: [
      if (_error != null) ErrorNotice(_error!),
      for (var i = 0; i < widget.questions.length; i++) Card(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i + 1}. ${widget.questions[i]['prompt']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12), Text('Response: ${_answer(widget.attempt['answers'][i], widget.questions[i])}'),
          if (_grades.containsKey(i)) ...[
            const SizedBox(height: 12), Text('Rubric: ${widget.questions[i]['rubric']}'),
            TextFormField(controller: _grades[i], enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Score out of ${widget.questions[i]['points']}'),
              validator: (v) { final n = num.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ||
                n > widget.questions[i]['points'] ? 'Enter a valid score.' : null; }),
          ] else Text('Points: ${(widget.attempt['grades'] as List?)?[i] ?? 'Automatically graded'}'),
        ]))),
      TextFormField(controller: _feedback, enabled: !_busy, maxLength: 2000, minLines: 3, maxLines: 8,
        decoration: const InputDecoration(labelText: 'Feedback')),
      PrimaryButton(label: 'Save review', busy: _busy, onPressed: _busy ? null : _save),
    ])),
  ));
}
