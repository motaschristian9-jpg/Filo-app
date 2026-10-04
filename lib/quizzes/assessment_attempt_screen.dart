import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../materials/supabase_file_storage.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import 'question_types.dart';

class AssessmentAttemptScreen extends StatefulWidget {
  const AssessmentAttemptScreen({super.key, required this.classId,
    required this.id, required this.title});
  final String classId, id, title;
  @override
  State<AssessmentAttemptScreen> createState() => _AssessmentAttemptScreenState();
}
class _AssessmentAttemptScreenState extends State<AssessmentAttemptScreen> {
  static const _privacy = MethodChannel('filo/assessment_privacy');
  final _clock = Stopwatch();
  Timer? _timer;
  List<dynamic>? _questions;
  List<dynamic> _answers = [];
  Timer? _textSave;
  bool _needsReview = false;
  num _totalPoints = 0;
  String _feedback = '';
  bool _secure = false, _busy = false, _submitted = false;
  bool _submitting = false;
  bool _checkingAttempt = true;
  bool _statusKnown = false;
  int _answerVersion = 0;
  int _remaining = 0, _initialRemaining = 0;
  num? _score;
  String? _error;
  late final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  @override
  void initState() { super.initState(); _protect(); }
  Future<void> _protect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() { _error = 'Take this assessment in the Android app.'; _checkingAttempt = false; }); return;
    }
    try {
      await _privacy.invokeMethod<void>('secure', true);
      if (mounted) {
        setState(() => _secure = true);
        await _request('status');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Screen protection could not start. Restart the app.');
    }
  }
  Future<void> _request(String action) async {
    if (_busy || !_secure) return;
    final version = _answerVersion;
    final sentAnswers = jsonDecode(jsonEncode(_answers)) as List;
    var succeeded = false;
    setState(() { _busy = true; _submitting = action == 'submit'; _error = null; });
    final client = http.Client();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != _uid) throw StateError('Account changed');
      final token = await user.getIdToken();
      final response = await client.post(Uri.parse('$supabaseUrl/functions/v1/assessment-attempt'),
        headers: {'apikey': supabasePublishableKey, 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'},
        body: jsonEncode({'classId': widget.classId, 'assessmentId': widget.id,
          'action': action, 'answers': sentAnswers}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) throw StateError('Request failed');
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != _uid) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _statusKnown = true;
      if (data['status'] == 'not_started') return;
      setState(() {
        _questions = data['questions'] as List;
        if (version == _answerVersion || data['status'] == 'submitted') {
          _answers = data['answers'] as List;
        }
        _submitted = data['status'] == 'submitted'; _score = data['score'] as num?;
        _needsReview = data['needsReview'] == true;
        _totalPoints = data['totalPoints'] as num;
        _feedback = data['feedback'] as String? ?? '';
        _initialRemaining = DateTime.parse(data['deadline'] as String)
          .difference(DateTime.parse(data['serverNow'] as String)).inSeconds.clamp(0, 10800).toInt();
        _remaining = _initialRemaining;
        _clock..reset()..start();
      });
      succeeded = true;
      _timer?.cancel();
      if (!_submitted) _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining = (_initialRemaining - _clock.elapsed.inSeconds).clamp(0, 10800).toInt());
        if (_remaining == 0 && !_busy) { _timer?.cancel(); _request('submit'); }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save or submit. Reconnect and retry; the timer continues.');
    } finally {
      client.close();
      if (mounted) {
        setState(() { _busy = false; _submitting = false;
          if (action == 'status') _checkingAttempt = false; });
        if (succeeded && !_submitted && _remaining == 0) {
          unawaited(_request('submit'));
        } else if (succeeded && !_submitted && version != _answerVersion) {
          unawaited(_request('save'));
        }
      }
    }
  }
  Future<void> _submit() async {
    final unanswered = _answers.where((a) => a == -1 || a is String && a.trim().isEmpty ||
      a is Map && (a['entries'] as List).every((v) => (v as String).trim().isEmpty)).length;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Submit assessment?'),
      content: Text(unanswered == 0 ? 'Your answers will be final.' : '$unanswered unanswered. Submit anyway?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep answering')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit'))],
    ));
    if (confirmed == true && mounted) await _request('submit');
  }
  @override
  void dispose() {
    _timer?.cancel(); _clock.stop();
    _textSave?.cancel();
    if (_secure) unawaited(_privacy.invokeMethod<void>('secure', false).catchError((Object _) {}));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (_questions == null || _submitted),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submit your assessment before leaving.')));
    },
    child: Scaffold(
    appBar: AppBar(title: Text(widget.title),
      automaticallyImplyLeading: !_busy && (_questions == null || _submitted)),
    body: SafeArea(child: !_secure ? Center(child: Text(_error ?? 'Preparing screen protection…'))
      : _checkingAttempt ? const FiloSkeleton(layout: SkeletonLayout.details)
      : _questions == null ? Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('One attempt. Finish and submit before leaving. The timer continues if the app closes.'),
          if (_error != null) ErrorNotice(_error!),
          const SizedBox(height: 24), PrimaryButton(label: _statusKnown ? 'Start assessment' : 'Retry status check', busy: _busy,
            onPressed: _busy ? null : () {
              if (!_statusKnown) setState(() => _checkingAttempt = true);
              _request(_statusKnown ? 'start' : 'status');
            }),
        ])))
      : _submitted ? _completion()
      : ListView(padding: const EdgeInsets.all(24), children: [
        Text('${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')} remaining',
          style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 32, child: Text(_busy ? _submitting ? 'Submitting…' : 'Saving answers…'
          : _error == null ? 'Answers saved' : 'Answers not confirmed',
          style: const TextStyle(color: muted))),
        if (_error != null) ErrorNotice(_error!),
        if (_error != null) TextButton(onPressed: _busy ? null : () => _request(_remaining == 0 ? 'submit' : 'save'),
          child: const Text('Retry')),
        for (var i = 0; i < _questions!.length; i++) Card(child: Padding(
          padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}. ${_questions![i]['prompt']}', style: Theme.of(context).textTheme.titleLarge),
            Text('${questionTypes[_questions![i]['type'] ?? 'multiple_choice']} · ${_questions![i]['points'] ?? 1} points'),
            if (['multiple_choice', 'true_false'].contains(_questions![i]['type'] ?? 'multiple_choice'))
            for (var option = 0; option < (_questions![i]['options'] as List).length; option++) ListTile(
              leading: Icon(_answers[i] == option ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: teal),
              title: Text(_questions![i]['options'][option] as String),
              onTap: _submitting || _remaining == 0 ? null : () {
                setState(() { _answers[i] = option; _answerVersion++; }); _request('save');
              },
            ),
            if (_questions![i]['type'] == 'identification' || _questions![i]['type'] == 'essay')
              _textAnswer(i),
            if (_questions![i]['type'] == 'essay') ...[
              const SizedBox(height: 12), Text('Rubric: ${_questions![i]['rubric']}'),
            ],
            if (_questions![i]['type'] == 'enumeration')
              for (var entry = 0; entry < _questions![i]['entryCount']; entry++) _textAnswer(i, entry: entry),
          ]))),
        PrimaryButton(label: 'Submit answers', busy: _submitting,
          onPressed: _busy ? null : _submit),
      ])),
  ));
  Widget _completion() => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 560),
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      const SizedBox(width: 180, height: 180,
        child: LearningArt(compact: true, expression: MascotExpression.proud)),
      const SizedBox(height: 24),
      Text(_needsReview ? 'Awaiting review' : 'Assessment complete', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12), const Text('Your answers have been submitted.'),
      const SizedBox(height: 24),
      Container(width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(24)),
        child: Column(children: [Text(_needsReview ? 'Objective points earned' : 'Your score'), const SizedBox(height: 8),
          Text(_needsReview ? '$_score points' : '$_score / $_totalPoints', style: Theme.of(context).textTheme.headlineLarge),
          if (_needsReview) const Text('Your instructor will grade the essay responses.'),
        ])),
      if (_feedback.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_feedback)),
      const SizedBox(height: 28),
      PrimaryButton(label: 'Back to class', onPressed: () => Navigator.pop(context)),
    ])),
  ));
  Widget _textAnswer(int index, {int? entry}) {
    final essay = _questions![index]['type'] == 'essay';
    final value = entry == null ? _answers[index] as String : _answers[index]['entries'][entry] as String;
    return Padding(padding: const EdgeInsets.only(top: 12), child: TextFormField(
      key: ValueKey('answer-$index-$entry'), initialValue: value,
      enabled: !_submitting && _remaining > 0, enableInteractiveSelection: false,
      autocorrect: false, enableSuggestions: false,
      maxLength: essay ? 10000 : 500, minLines: essay ? 5 : 1, maxLines: essay ? 12 : 2,
      decoration: InputDecoration(labelText: entry == null ? 'Your answer' : 'Item ${entry + 1}'),
      onChanged: (value) {
        setState(() {
          if (entry == null) { _answers[index] = value; }
          else { _answers[index]['entries'][entry] = value; }
          _answerVersion++;
        });
        _textSave?.cancel();
        _textSave = Timer(const Duration(milliseconds: 600), () => _request('save'));
      },
    ));
  }
}
