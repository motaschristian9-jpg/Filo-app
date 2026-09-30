import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../onboarding/design.dart';
import 'class_editor.dart';
import 'class_repository.dart';

class ClassDetailScreen extends StatefulWidget {
  const ClassDetailScreen({super.key, required this.repository, required this.classId});
  final ClassRepository repository;
  final String classId;
  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}
class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late Stream<FiloClass?> _classStream;
  late Stream<List<ClassMember>> _membersStream;
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); _subscribe(); }
  void _subscribe() {
    _classStream = widget.repository.watchClass(widget.classId);
    _membersStream = widget.repository.watchMembers(widget.classId);
  }
  Future<void> _edit(FiloClass item) async {
    await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) =>
      ClassEditor(repository: widget.repository, existing: item)));
  }
  Future<void> _archive(FiloClass item) async {
    if (_saving) return;
    final proceed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(item.archived ? 'Restore class?' : 'Archive class?'),
      content: Text(item.archived ? 'Move it back to your active classes.' : 'Keep the class and its students in Archived.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true),
          child: Text(item.archived ? 'Restore' : 'Archive')),
      ],
    ));
    if (proceed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try { await widget.repository.setArchived(item.id, !item.archived); }
    catch (error) { if (mounted) setState(() => _error = classError(error)); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  Future<void> _copy(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class code copied')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not copy. Select the code to copy it.')));
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<FiloClass?>(
    stream: _classStream,
    builder: (context, snapshot) {
      final item = snapshot.data;
      return Scaffold(
        appBar: AppBar(title: const Text('Your class'), actions: [
          if (item != null) PopupMenuButton<String>(
            enabled: !_saving, tooltip: 'Class options',
            onSelected: (action) { if (action == 'edit') { _edit(item); } else { _archive(item); } },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit class')),
              PopupMenuItem(value: 'archive', child: Text(item.archived ? 'Restore class' : 'Archive class')),
            ],
          ),
        ]),
        body: SafeArea(top: false, child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: snapshot.hasError
            ? _loadError()
            : snapshot.connectionState == ConnectionState.waiting && item == null
              ? const Center(child: CircularProgressIndicator())
              : item == null
                ? const Center(child: Text('This class is no longer available.'))
                : SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: double.infinity, padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(color: classColor(item.color), borderRadius: BorderRadius.circular(28)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(classIcon(item.color), size: 40, color: teal),
                          const SizedBox(height: 20),
                          Text(item.name, style: Theme.of(context).textTheme.headlineMedium),
                          if (item.section.isNotEmpty) ...[const SizedBox(height: 8), Text(item.section)],
                          if (item.archived) ...[const SizedBox(height: 16), const Chip(label: Text('Archived'), avatar: Icon(Icons.archive_outlined, size: 18))],
                        ])),
                      const SizedBox(height: 24),
                      if (_saving) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
                      if (_error != null) ErrorNotice(_error!),
                      if (item.subject.isNotEmpty) ...[
                        const Eyebrow('Subject'), const SizedBox(height: 8), Text(item.subject), const SizedBox(height: 24),
                      ],
                      if (item.description.isNotEmpty) ...[
                        const Eyebrow('About this class'), const SizedBox(height: 8), Text(item.description), const SizedBox(height: 24),
                      ],
                      Container(width: double.infinity, padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line), borderRadius: BorderRadius.circular(22)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Eyebrow('Class code'), const SizedBox(height: 10),
                          SelectableText(item.code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink, letterSpacing: .5)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(onPressed: item.archived ? null : () => _copy(item.code),
                            icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Copy code')),
                        ])),
                      const SizedBox(height: 30),
                      Text('Students', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14),
                      StreamBuilder<List<ClassMember>>(stream: _membersStream, builder: (context, members) {
                        if (members.hasError) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Could not load students.'), TextButton(onPressed: () => setState(() => _membersStream = widget.repository.watchMembers(widget.classId)), child: const Text('Retry')),
                        ]);
                        if (!members.hasData) return const LinearProgressIndicator();
                        if (members.data!.isEmpty) return Container(width: double.infinity,
                          padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(22)),
                          child: const Column(children: [Icon(Icons.people_outline_rounded, color: teal, size: 30), SizedBox(height: 10), Text('No students yet.')]),
                        );
                        return Column(children: [for (final member in members.data!) ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(backgroundColor: mint, child: Icon(Icons.person_outline_rounded, color: teal)),
                          title: Text(member.name),
                        )]);
                      }),
                    ],
                  )),
        ))),
      );
    },
  );
  Widget _loadError() => Padding(padding: const EdgeInsets.all(24), child: Column(
    mainAxisSize: MainAxisSize.min, children: [const Text('Could not load this class.'),
      TextButton(onPressed: () => setState(_subscribe), child: const Text('Retry'))],
  ));
}
