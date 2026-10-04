import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'material_repository.dart';

Future<bool> manageMaterial(BuildContext context, ClassMaterial item, String action) async {
  if (action == 'delete') {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete post?'), content: const Text('This removes the post and its attachments from the class.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (confirmed != true) return false;
    await MaterialRepository().deletePost(item);
    return true;
  }
  final title = TextEditingController(text: item.title), body = TextEditingController(text: item.body),
    url = TextEditingController(text: item.url);
  final form = GlobalKey<FormState>();
  final values = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('Edit post'), content: SizedBox(width: 500, child: SingleChildScrollView(
      child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        TextFormField(controller: body, maxLength: 5000, minLines: 3, maxLines: 8,
          decoration: const InputDecoration(labelText: 'Message'),
          validator: (v) => item.kind == 'announcement' && item.attachmentIds.isEmpty && (v ?? '').trim().isEmpty ? 'Required' : null),
        if (item.kind == 'link') TextFormField(controller: url, maxLength: 2048,
          decoration: const InputDecoration(labelText: 'Link'), validator: (v) {
            final uri = Uri.tryParse(v ?? ''); return uri?.scheme == 'https' && uri!.host.isNotEmpty ? null : 'This link looks incorrect. Check it and try again.';
          }),
        if (item.hasFile) const Text('The attached file stays the same.'),
      ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx,
        {'title': title.text.trim(), 'body': body.text.trim(), if (item.kind == 'link') 'url': url.text.trim()}); },
        child: const Text('Save'))],
  ));
  Future<void>.delayed(const Duration(milliseconds: 400), () { title.dispose(); body.dispose(); url.dispose(); });
  if (values == null) return false;
  await MaterialRepository().collection(item.classId).doc(item.id).update(values);
  return true;
}
