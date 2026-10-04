import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../materials/material_repository.dart';
import '../onboarding/design.dart';
import 'question_types.dart';

class QuizSource {
  const QuizSource(this.materialIds, this.notes, this.counts);
  final List<String> materialIds;
  final String notes;
  final Map<String, int> counts;
  int get count => counts.values.fold(0, (a, b) => a + b);
}

class QuizSourceDialog extends StatefulWidget {
  const QuizSourceDialog({super.key, required this.classId, required this.remaining});
  final String classId;
  final int remaining;
  @override
  State<QuizSourceDialog> createState() => _QuizSourceDialogState();
}
class _QuizSourceDialogState extends State<QuizSourceDialog> {
  final _notes = TextEditingController();
  final _counts = {for (final type in questionTypes.keys) type:
    TextEditingController(text: type == 'multiple_choice' ? '5' : '0')};
  final _form = GlobalKey<FormState>();
  final _selected = <String>{};
  late final _materials = MaterialRepository().watch(widget.classId);
  String? _error;
  bool _supported(ClassMaterial item) => const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'md', 'csv']
    .contains(item.fileName.split('.').last.toLowerCase());
  @override
  void dispose() { _notes.dispose(); for (final c in _counts.values) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate with AI'),
    content: SizedBox(width: 500, child: SingleChildScrollView(child: Form(key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Choose lesson files from Materials. AI will read the selected files.'),
        const SizedBox(height: 12),
        const Text('Up to 3 files, 8 MB total. PDF, images, TXT, Markdown, or CSV.'),
        const SizedBox(height: 16),
        StreamBuilder<List<ClassMaterial>>(stream: _materials, builder: (context, snapshot) {
          if (snapshot.hasError) return const ErrorNotice('Could not load materials. Reopen this dialog.');
          if (!snapshot.hasData) return const FiloSkeleton(layout: SkeletonLayout.rows,
            scrollable: false, padding: EdgeInsets.zero);
          final files = snapshot.data!.where((m) => m.hasFile).toList();
          if (files.isEmpty) return const Text('Post a lesson file in Materials first.');
          return Column(children: [for (final file in files) CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(file.title), subtitle: Text(_supported(file) ? file.fileName : '${file.fileName} · Unsupported format'),
            value: _selected.contains(file.id),
            onChanged: !_supported(file) ? null : (selected) {
              setState(() {
                _error = null;
                if (selected != true) { _selected.remove(file.id); return; }
                final total = files.where((m) => _selected.contains(m.id)).fold<int>(0, (n, m) => n + m.size);
                if (_selected.length >= 3 || total + file.size > 8 * 1024 * 1024) {
                  _error = 'Choose up to 3 files totaling 8 MB or less.';
                } else { _selected.add(file.id); }
              });
            },
          )]);
        }),
        const SizedBox(height: 16),
        TextFormField(controller: _notes, minLines: 2, maxLines: 4, maxLength: 12000,
          decoration: const InputDecoration(labelText: 'Additional lesson notes (optional)')),
        for (final type in questionTypes.keys) TextFormField(controller: _counts[type], keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: '${questionTypes[type]} count'),
          validator: (value) { final n = int.tryParse(value ?? '');
            return n == null || n < 0 || n > 20 ? 'Choose 0–20.' : null; }),
        if (_error != null) ErrorNotice(_error!),
        const SizedBox(height: 12),
        const Text('Selected files are sent to Gemini. Review questions before saving.'),
      ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        if (!_form.currentState!.validate()) return;
        if (_selected.isEmpty) { setState(() => _error = 'Select at least one lesson file.'); return; }
        final counts = {for (final entry in _counts.entries) entry.key: int.parse(entry.value.text)};
        final total = counts.values.fold(0, (a, b) => a + b);
        if (total < 1 || total > 20 || total > widget.remaining) {
          setState(() => _error = 'Choose 1–20 questions total (maximum 50 per assessment).'); return;
        }
        Navigator.pop(context, QuizSource(_selected.toList(), _notes.text.trim(), counts));
      }, child: const Text('Generate'))],
  );
}
