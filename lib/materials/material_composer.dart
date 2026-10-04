import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'material_repository.dart';
import 'supabase_file_storage.dart';
import 'due_date.dart';

class MaterialComposer extends StatefulWidget {
  const MaterialComposer({super.key, required this.classId});
  final String classId;
  @override
  State<MaterialComposer> createState() => _MaterialComposerState();
}

class _MaterialComposerState extends State<MaterialComposer> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _body = TextEditingController(),
      _url = TextEditingController();
  final _repository = MaterialRepository();
  late final String _id = _repository.collection(widget.classId).doc().id;
  final _attachments = <PostAttachment>[];
  bool _showLink = false;
  bool _requiresSubmission = false;
  DateTime? _dueAt;
  Future<void> _chooseDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context,
      initialDate: _dueAt != null && _dueAt!.isAfter(now) ? _dueAt! : now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 5, 12, 31));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context,
      initialTime: _dueAt == null ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay.fromDateTime(_dueAt!));
    if (time == null || !mounted) return;
    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (!value.isAfter(DateTime.now())) { _error = 'Choose a future deadline.'; }
      else { _dueAt = value; _error = null; }
    });
  }
  final _points = TextEditingController(text: '100');
  bool _busy = false, _picking = false, _attempted = false;
  String? _error;
  @override
  void dispose() { _title.dispose(); _body.dispose(); _url.dispose(); _points.dispose(); super.dispose(); }

  Future<void> _pick() async {
    setState(() { _picking = true; _error = null; });
    try {
      final file = await FilePicker.pickFile();
      if (file == null || !mounted) return;
      final length = await file.length();
      if (length == null || length == 0 || length > maxMaterialBytes || file.name.length > 255) {
        setState(() => _error = 'Choose a file up to 25 MB.');
        return;
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (buffer.length + chunk.length > maxMaterialBytes) {
          throw StateError('File exceeds 25 MB');
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      if (!mounted) return;
      if (_attachments.fold<int>(0, (n, a) => n + (a.bytes?.length ?? 0)) + bytes.length > 50 * 1024 * 1024) {
        setState(() => _error = 'Up to 50 MB of files per post.'); return;
      }
      setState(() {
        _attachments.add(PostAttachment(id: _repository.collection(widget.classId).doc().id,
          name: file.name, bytes: bytes));
        if (_title.text.isEmpty) _title.text = file.name;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read that file.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _post() async {
    if (_busy || _picking || !_form.currentState!.validate()) return;
    if (_requiresSubmission && !_attempted && (_dueAt == null || !_dueAt!.isAfter(DateTime.now()))) {
      setState(() => _error = 'Choose a future due date and time.');
      await _chooseDeadline(); return;
    }
    if (_showLink && _url.text.trim().isNotEmpty) {
      if (_attachments.length >= 10) { setState(() => _error = 'Up to 10 attachments per post.'); return; }
      _commitLink();
    }
    if (_body.text.trim().isEmpty && _attachments.isEmpty) {
      setState(() => _error = 'Write a message or add an attachment.'); return;
    }
    setState(() { _busy = true; _attempted = true; _error = null; });
    try {
      await _repository.postUnified(classId: widget.classId, id: _id,
        title: _title.text, body: _body.text, attachments: _attachments,
        requiresSubmission: _requiresSubmission,
        maxPoints: _requiresSubmission ? int.parse(_points.text) : 100, dueAt: _dueAt);
      if (mounted) Navigator.pop(context, 'announcement');
    } on MaterialStorageException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FirebaseException catch (error) {
      // Keep the service/code visible for diagnosis without logging file data,
      // tokens, download URLs, or the underlying server response.
      debugPrint('Material post failed: ${error.plugin}/${error.code}');
      final message = switch (error.code) {
        'bucket-not-found' || 'no-default-bucket' || 'project-not-found' =>
          'File storage is not configured. Contact your app administrator.',
        'unauthorized' => 'File upload access was denied. Check the storage permissions.',
        'permission-denied' => 'Posting access was denied. Check this class and its permissions.',
        'unauthenticated' => 'Your session expired. Sign in again.',
        'quota-exceeded' || 'resource-exhausted' => 'The service limit was reached. Try again later.',
        'retry-limit-exceeded' || 'unavailable' || 'deadline-exceeded' =>
          'The service could not be reached. Check your connection and retry.',
        'canceled' || 'cancelled' => 'Posting was interrupted. Retry to confirm your post.',
        _ => 'Could not confirm your post. Retry or share the error code below.',
      };
      if (mounted) setState(() => _error = '$message\n${error.plugin}/${error.code}');
    } catch (error) {
      debugPrint('Material post failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = 'Could not confirm your post. Retry or report this issue.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  void _commitLink() {
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || url.length > 2048 || _attachments.length >= 10) return;
    setState(() {
      _attachments.add(PostAttachment(id: _repository.collection(widget.classId).doc().id, url: url));
      _url.clear(); _showLink = false;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Create post')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(children: [
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
            child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: _title, enabled: !_busy && !_attempted,
                maxLength: 120, decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Add a title.' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _body, enabled: !_busy && !_attempted,
                minLines: 4, maxLines: 10, maxLength: 5000,
                decoration: const InputDecoration(labelText: 'Message (optional)')),
              const SizedBox(height: 16),
              Wrap(spacing: 12, children: [
                OutlinedButton.icon(onPressed: _busy || _attempted || _picking || _attachments.length >= 10 ? null : _pick,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(_picking ? 'Reading file...' : 'Attach file')),
                OutlinedButton.icon(onPressed: _busy || _attempted || _picking || _attachments.length >= 10 ? null
                  : () => setState(() => _showLink = true), icon: const Icon(Icons.link_rounded), label: const Text('Add link')),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Require submission'),
                value: _requiresSubmission, onChanged: _busy || _attempted || _picking ? null
                  : (value) => setState(() => _requiresSubmission = value)),
              if (_requiresSubmission) TextFormField(controller: _points, enabled: !_busy && !_attempted,
                keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum score'),
                validator: (value) { final points = int.tryParse(value ?? '');
                  return points != null && points >= 1 && points <= 1000 ? null : 'Use 1 to 1000 points.'; }),
              if (_requiresSubmission) const Padding(padding: EdgeInsets.only(top: 8, bottom: 12),
                child: Text('Students can revise for 5 minutes after submitting, until the deadline.')),
              if (_requiresSubmission) OutlinedButton.icon(
                onPressed: _busy || _attempted || _picking ? null : _chooseDeadline,
                icon: const Icon(Icons.event_outlined),
                label: Text(_dueAt == null ? 'Set due date & time' : 'Due ${formatDueDate(context, _dueAt!)}')),
              const Text('Up to 10 attachments · 25 MB per file'), const SizedBox(height: 16),
              for (final a in _attachments) Card(child: ListTile(
                leading: Icon(a.bytes == null ? Icons.link_rounded : Icons.description_outlined, color: teal),
                title: Text(a.bytes == null ? a.url : a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(tooltip: 'Remove attachment', onPressed: _busy || _attempted || _picking ? null
                  : () => setState(() => _attachments.remove(a)), icon: const Icon(Icons.close_rounded)))),
              if (_showLink) ...[
                TextFormField(controller: _url, enabled: !_busy && !_attempted,
                  keyboardType: TextInputType.url, maxLength: 2048,
                  decoration: const InputDecoration(labelText: 'Link', hintText: 'https://',
                    helperText: 'Add a resource or video link. Supported links open a preview.',
                    helperMaxLines: 2),
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    return value?.trim().isEmpty == true || uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
                        ? null : 'This link looks incorrect. Check it and try again.';
                  }), const SizedBox(height: 16),
                TextButton(onPressed: _busy || _attempted ? null : () {
                  final uri = Uri.tryParse(_url.text.trim());
                  if (uri?.scheme == 'https' && uri!.host.isNotEmpty) _commitLink();
                  else setState(() => _error = 'This link looks incorrect. Check it and try again.');
                }, child: const Text('Attach link')),
              ],
              if (_error != null) ErrorNotice(_error!),
              if (_busy) const LinearProgressIndicator(),
            ])))),
          Padding(padding: const EdgeInsets.all(24), child: PrimaryButton(
            label: _busy ? 'Posting...' : _attempted ? 'Retry post' : 'Post',
            icon: Icons.send_rounded, onPressed: _busy || _picking ? null : _post)),
        ]),
      ))),
    ),
  );
}
