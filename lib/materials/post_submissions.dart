import 'dart:typed_data';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import 'author_cache.dart';
import 'material_repository.dart';
import 'supabase_file_storage.dart';
import 'link_preview.dart';
import 'submission_action.dart';
import 'due_date.dart';

class PostSubmissions extends StatefulWidget {
  const PostSubmissions({super.key, required this.post, required this.uid, required this.actionController});
  final SubmissionActionController actionController;
  final ClassMaterial post;
  final String uid;
  @override
  State<PostSubmissions> createState() => _PostSubmissionsState();
}

class _PostSubmissionsState extends State<PostSubmissions> {
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>>? _drafts;
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _attachments(Map<String, dynamic> data) =>
    data['attachments'] is List
      ? (data['attachments'] as List).map((a) => Map<String, dynamic>.from(a as Map)).toList()
      : [{'kind': data['kind'] ?? 'file', 'url': data['url'] ?? '',
          'fileName': data['fileName'] ?? '', 'storagePath': data['storagePath'] ?? '', 'size': data['size'] ?? 0}];
  void _ensureDrafts() { _drafts ??= _current == null ? [] : _attachments(_current!); }
  void _bottom({bool loaded = true}) {
    final data = _current;
    final editable = loaded && !instructor && !_closed && (data == null || (_canRevise(data) && data['status'] == 'editing'));
    final action = editable ? SubmissionAction(_busy ? 'Please wait...' : data == null ? 'Submit work' : 'Resubmit work',
      _busy || (_drafts?.isEmpty ?? true) ? null : () => _submit()) : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.actionController.show(action);
    });
  }
  Timer? _timer;
  final _clock = ValueNotifier<int>(0);
  List<Map<String, dynamic>> _timedSubmissions = [];
  String _timeState() => '$_closed/${_timedSubmissions.map(_canRevise).join(',')}';
  String? _lastTimeState;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _clock.value++;
      final state = _timeState();
      if (_lastTimeState != null && state != _lastTimeState) setState(() {});
      _lastTimeState = state;
    });
  }
  @override
  void dispose() { _timer?.cancel(); _clock.dispose(); super.dispose(); }
  Widget _countdown(Map<String, dynamic> data, {bool student = false}) =>
    ValueListenableBuilder<int>(valueListenable: _clock, builder: (_, _, _) =>
      Text(student ? '${_remaining(data)} remaining to make changes'
        : 'Revision window · ${_remaining(data)} remaining'));
  DateTime? _deadline(Map<String, dynamic> data) {
    final first = data['firstSubmittedAt'] ?? data['submittedAt'];
    final revision = first is Timestamp ? first.toDate().add(Duration(minutes: widget.post.revisionMinutes)) : null;
    final due = widget.post.dueAt;
    return due != null && (revision == null || due.isBefore(revision)) ? due : revision;
  }
  bool get _closed => widget.post.dueAt != null && !widget.post.dueAt!.isAfter(DateTime.now());
  bool _canRevise(Map<String, dynamic> data) => data['score'] == null &&
    (_deadline(data)?.isAfter(DateTime.now()) ?? true);
  String _remaining(Map<String, dynamic> data) {
    final seconds = (_deadline(data)?.difference(DateTime.now()).inSeconds ?? 0).clamp(0, 3600);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
  bool get instructor => widget.post.data['authorId'] == widget.uid;
  bool get active => mounted && FirebaseAuth.instance.currentUser?.uid == widget.uid;
  late final _collection = MaterialRepository().collection(widget.post.classId)
    .doc(widget.post.id).collection('submissions');
  late final _mine = _collection.doc(widget.uid).snapshots();
  int _submissionLimit = 30;
  late var _all = _collection.orderBy('submittedAt', descending: true).limit(_submissionLimit).snapshots();

  Future<void> _pick() async {
    _ensureDrafts();
    if (_drafts!.length >= 10) return;
    setState(() { _busy = true; _error = null; });
    try {
      final file = await FilePicker.pickFile();
      if (file == null || !active) return;
      final size = await file.length();
      if (size == null || size <= 0 || size > maxMaterialBytes || file.name.length > 255) throw StateError('Choose a file up to 25 MB.');
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (!active) return;
        if (buffer.length + chunk.length > maxMaterialBytes) throw StateError('Choose a file up to 25 MB.');
        buffer.add(chunk);
      }
      if (_drafts!.fold<int>(0, (sum, a) => sum + (a['size'] as int)) + buffer.length > 50 * 1024 * 1024) {
        throw StateError('Up to 50 MB of files per submission.');
      }
      if (active) setState(() => _drafts!.add({'kind': 'file', 'fileName': file.name,
        'bytes': buffer.takeBytes(), 'size': size, 'url': '', 'storagePath': ''}));
    } catch (error) { if (active) setState(() => _error = error is StateError ? error.message.toString() : 'Could not read file.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _addLink() async {
    _ensureDrafts();
    if (_drafts!.length >= 10) return;
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final link = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add submission link'), content: Form(key: form, child: TextFormField(
        controller: controller, keyboardType: TextInputType.url, maxLength: 2048,
        decoration: const InputDecoration(hintText: 'https://', helperText: 'Give your instructor access to this link.', helperMaxLines: 2),
        validator: (v) { final uri = Uri.tryParse(v?.trim() ?? '');
          return uri?.scheme == 'https' && uri!.host.isNotEmpty ? null : 'This link looks incorrect. Check it and try again.'; })),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('Add'))]));
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (link != null && active && _drafts!.length < 10) setState(() => _drafts!.add(
      {'kind': 'link', 'url': link, 'fileName': '', 'size': 0, 'storagePath': ''}));
  }

  Future<void> _unsubmit() async {
    if (_busy || !active) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ref = _collection.doc(widget.uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final old = (await tx.get(ref)).data();
        if (old == null) return;
        tx.set(ref, {'studentId': widget.uid, 'status': 'editing', 'attachments': _attachments(old),
          'submittedAt': old['submittedAt'], 'firstSubmittedAt': old['firstSubmittedAt'] ?? old['submittedAt']});
      });
      _drafts = null;
    } catch (_) { if (active) setState(() => _error = 'The revision window has ended or work is locked. Reopen this post.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _submit() async {
    if (_busy || _closed || _drafts == null || _drafts!.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Submit your work?'), content: Text('You can revise for ${widget.post.revisionMinutes} minutes from your first submission, until the activity deadline. Resubmitting does not restart the timer.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit'))]));
    if (confirmed != true || !active) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ref = _collection.doc(widget.uid);
      final existing = (await ref.get(const GetOptions(source: Source.server))).data();
      if (existing != null && existing['status'] != 'editing') return;
      final attachments = <Map<String, dynamic>>[];
      for (final draft in _drafts!) {
        if (!active) return;
        if (draft['bytes'] is Uint8List && (draft['storagePath'] as String).isEmpty) {
          draft['storagePath'] = await SupabaseFileStorage().upload(widget.post.classId, widget.post.id,
            draft['bytes'] as Uint8List, submission: true);
        }
        attachments.add({for (final key in ['kind', 'url', 'fileName', 'storagePath', 'size']) key: draft[key]});
      }
      if (!active) return;
      final committed = await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final old = (await tx.get(ref)).data();
        if (old != null && old['status'] != 'editing') return false;
        tx.set(ref, {'studentId': widget.uid, 'attachments': attachments, 'status': 'pending',
          'submittedAt': old?['submittedAt'] ?? FieldValue.serverTimestamp(),
          'firstSubmittedAt': old?['firstSubmittedAt'] ?? old?['submittedAt'] ?? FieldValue.serverTimestamp()});
        return true;
      });
      if (active) {
        setState(() => _drafts = null);
        if (committed) showMascotSuccess(context, 'Work submitted');
      }
    } catch (error) { if (active) setState(() => _error = error is MaterialStorageException
      ? error.message : 'Could not confirm submission. Check your connection and retry.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _open(String studentId, Map<String, dynamic> data, int index) async {
    if (_busy || !active) return;
    setState(() { _busy = true; _error = null; });
    try {
      final preview = data['kind'] == 'link' ? LinkPreview.parse(data['url'] as String) : null;
      final url = data['kind'] == 'link' ? preview?.uri ?? Uri.parse(data['url'] as String)
        : await SupabaseFileStorage().submissionUrl(widget.post.classId, widget.post.id, studentId, attachmentIndex: index);
      if (!active) return;
      if (!await launchUrl(url, mode: preview == null ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView)) throw StateError('Could not open file');
    } catch (_) { if (active) setState(() => _error = data['kind'] == 'link'
      ? 'This link could not be opened. Check the link and your connection, then try again.'
      : 'Could not open submission. Please retry.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _grade(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final editing = doc.data()['score'] != null;
    final score = TextEditingController(text: doc.data()['score']?.toString() ?? '');
    final feedback = TextEditingController(text: doc.data()['feedback'] as String? ?? '');
    final form = GlobalKey<FormState>();
    final values = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => AlertDialog(
      title: Text(editing ? 'Edit grade' : 'Grade submission'), content: SingleChildScrollView(child: Form(key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: score, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Score out of ${widget.post.maxPoints}'),
            validator: (value) { final n = num.tryParse(value ?? '');
              return n != null && n.isFinite && n >= 0 && n <= widget.post.maxPoints ? null : 'Enter 0 to ${widget.post.maxPoints}.'; }),
          TextFormField(controller: feedback, maxLength: 2000, minLines: 2, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Feedback (optional)')),
        ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx,
            {'score': num.parse(score.text), 'feedback': feedback.text.trim(), 'gradedAt': FieldValue.serverTimestamp()}); },
            child: Text(editing ? 'Save changes' : 'Save grade'))]));
    Future<void>.delayed(const Duration(milliseconds: 400), () { score.dispose(); feedback.dispose(); });
    if (values == null || !active) return;
    setState(() { _busy = true; _error = null; });
    try {
      await doc.reference.update(values);
      if (active) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editing ? 'Grade updated.' : 'Grade saved.')));
    }
    catch (_) { if (active) setState(() => _error = 'Could not save grade. Please retry.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _editor() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final attachment in _drafts ?? <Map<String, dynamic>>[]) Card(child: ListTile(
      leading: Icon(attachment['kind'] == 'link' ? Icons.link_rounded : Icons.description_outlined, color: teal),
      title: Text(attachment['kind'] == 'link' ? attachment['url'] as String : attachment['fileName'] as String,
        maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(tooltip: 'Remove attachment', onPressed: _busy ? null
        : () => setState(() => _drafts!.remove(attachment)), icon: const Icon(Icons.close_rounded)))),
    Wrap(spacing: 12, children: [
      OutlinedButton.icon(onPressed: _busy || (_drafts?.length ?? 0) >= 10 ? null : _pick, icon: const Icon(Icons.attach_file_rounded), label: const Text('Attach file')),
      OutlinedButton.icon(onPressed: _busy || (_drafts?.length ?? 0) >= 10 ? null : _addLink, icon: const Icon(Icons.link_rounded), label: const Text('Add link')),
    ]),
    const SizedBox(height: 12),
    const Text('Up to 10 attachments · 25 MB per file'),
  ]);

  Widget _savedAttachments(String studentId, Map<String, dynamic> data) {
    final attachments = _attachments(data);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < attachments.length; i++) TextButton.icon(
        onPressed: _busy ? null : () => _open(studentId, attachments[i], i),
        icon: Icon(attachments[i]['kind'] == 'link' ? Icons.link_rounded : Icons.description_outlined),
        label: Text(attachments[i]['kind'] == 'link' ? attachments[i]['url'] as String : attachments[i]['fileName'] as String,
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(instructor ? 'Student submissions' : 'Your submission', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8), Text('${widget.post.maxPoints} points'),
    if (widget.post.dueAt != null) Padding(padding: const EdgeInsets.only(top: 8),
      child: Text('Due ${formatDueDate(context, widget.post.dueAt!)}')),
    const SizedBox(height: 12),
    if (instructor) StreamBuilder(stream: _all, builder: (context, snapshot) {
      if (snapshot.hasError) return const ErrorNotice('Could not load submissions.');
      if (!snapshot.hasData) return const FiloSkeleton(scrollable: false, layout: SkeletonLayout.rows);
      _timedSubmissions = snapshot.data!.docs.map((doc) => doc.data()).toList();
      _lastTimeState = _timeState();
      if (snapshot.data!.docs.isEmpty) return const Text('No submissions yet.');
      return Column(children: [for (final doc in snapshot.data!.docs) Card(child: Padding(
        padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ValueListenableBuilder<AuthorProfileState>(valueListenable: AuthorCache.instance.watch(widget.uid, doc.id),
            builder: (_, profile, _) => profile.loading
              ? const FiloSkeleton(layout: SkeletonLayout.author, scrollable: false, padding: EdgeInsets.zero)
              : Text(profile.data?['name'] as String? ?? 'Student', style: Theme.of(context).textTheme.titleMedium)),
          _savedAttachments(doc.id, doc.data()),
          _canRevise(doc.data()) ? _countdown(doc.data())
            : Text(doc.data()['score'] == null ? 'Awaiting grade' : '${doc.data()['score']} / ${widget.post.maxPoints}'),
          TextButton(onPressed: _busy || _canRevise(doc.data()) ? null : () => _grade(doc),
            child: Text(doc.data()['score'] == null ? 'Grade' : 'Edit grade')),
        ]))),
        if (snapshot.data!.docs.length >= _submissionLimit)
          TextButton(onPressed: () => setState(() {
            _submissionLimit += 30;
            _all = _collection.orderBy('submittedAt', descending: true).limit(_submissionLimit).snapshots();
          }), child: const Text('Load older submissions')),
      ]);
    }) else StreamBuilder(stream: _mine, builder: (context, snapshot) {
      if (snapshot.hasError) { _bottom(loaded: false); return const ErrorNotice('Could not load your submission.'); }
      if (!snapshot.hasData) { _bottom(loaded: false); return const FiloSkeleton(scrollable: false, layout: SkeletonLayout.rows); }
      final data = snapshot.data!.data();
      _current = data;
      _timedSubmissions = data == null ? [] : [data];
      _lastTimeState = _timeState();
      if (data == null || (_canRevise(data) && data['status'] == 'editing')) _ensureDrafts();
      _bottom();
      if (data != null) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_canRevise(data) ? data['status'] == 'editing' ? 'Editing your work' : 'Submitted · Revision window'
          : data['score'] == null ? 'Submitted · Awaiting grade' : 'Score: ${data['score']} / ${widget.post.maxPoints}',
          style: Theme.of(context).textTheme.titleMedium),
        if (_canRevise(data)) ...[
          _countdown(data, student: true),
          const Text('The last submitted version becomes final when the timer ends.'),
          const SizedBox(height: 12),
        ],
        if (_canRevise(data) && data['status'] == 'editing') _editor()
        else ...[
          _savedAttachments(widget.uid, data),
          if (_canRevise(data)) OutlinedButton(onPressed: _busy ? null : _unsubmit,
            child: const Text('Unsubmit & edit')),
        ],
        if ((data['feedback'] as String? ?? '').isNotEmpty) Text(data['feedback'] as String),
      ]);
      return _closed ? const Text('Deadline passed · No submission') : _editor();
    }),
    if (_error != null) ErrorNotice(_error!),
  ]);
}
