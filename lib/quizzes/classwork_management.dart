import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'quiz_editor.dart';
import 'quiz_repository.dart';

Future<void> manageClasswork(BuildContext context, String classId, String id,
    Map<String, dynamic> data, String action) async {
  final repository = QuizRepository(classId);
  final published = data['publishedAt'] != null;
  if (action == 'edit' && !published) {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => QuizEditor(
      repository: repository, id: id, existing: data))); return;
  }
  if (action == 'edit') {
    final controller = TextEditingController(text: data['title'] as String);
    final form = GlobalKey<FormState>();
    final title = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit title'), content: Form(key: form, child: TextFormField(
        controller: controller, maxLength: 120, decoration: const InputDecoration(labelText: 'Title'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, controller.text.trim()); },
          child: const Text('Save'))]));
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (title == null) return;
    final batch = FirebaseFirestore.instance.batch();
    batch.update(repository.collection.doc(id), {'title': title});
    batch.update(FirebaseFirestore.instance.collection('classes').doc(classId).collection('assessments').doc(id), {'title': title});
    await batch.commit(); return;
  }
  final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: Text(published ? 'Remove from classwork?' : 'Delete draft?'),
    content: Text(published ? 'Students will no longer see this assessment. Existing results are kept.' : 'This draft will be permanently removed.'),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
  if (confirmed != true) return;
  if (published) {
    await FirebaseFirestore.instance.collection('classes').doc(classId).collection('assessments').doc(id).update({'hidden': true});
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from classwork. Results are kept in Removed.')));
  } else { await repository.collection.doc(id).delete(); }
}
