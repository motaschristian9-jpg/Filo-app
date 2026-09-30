import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import '../onboarding/onboarding_repository.dart';
import 'class_detail_screen.dart';
import 'class_editor.dart';
import 'class_repository.dart';

class InstructorDashboard extends StatefulWidget {
  const InstructorDashboard({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<InstructorDashboard> createState() => _InstructorDashboardState();
}
class _InstructorDashboardState extends State<InstructorDashboard> {
  late final ClassRepository _repository;
  late Stream<List<FiloClass>> _classes;
  bool _archived = false;
  String _search = '';
  @override
  void initState() {
    super.initState();
    _repository = ClassRepository(instructorId: widget.controller.user!.uid);
    _classes = _repository.watchClasses();
  }
  Future<void> _create() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => ClassEditor(repository: _repository)));
    if (!mounted || id == null) return;
    setState(() => _archived = false);
    _open(id);
  }
  void _open(String id) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ClassDetailScreen(repository: _repository, classId: id)));
  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile!;
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 16, 16, 4), child: Row(children: [
            const Brand(), const Spacer(),
            ProfileAvatar(avatar: profile.avatar, photoUrl: widget.controller.user!.photoUrl, size: 44),
            PopupMenuButton<String>(tooltip: 'Account', enabled: !widget.controller.busy,
              onSelected: (_) => widget.controller.signOut(),
              itemBuilder: (_) => [const PopupMenuItem(value: 'signout', child: Text('Sign out'))]),
          ])),
          Expanded(child: StreamBuilder<List<FiloClass>>(stream: _classes, builder: (context, snapshot) {
            final all = snapshot.data ?? const <FiloClass>[];
            final query = _search.trim().toLowerCase();
            final visible = all.where((item) => item.archived == _archived &&
              '${item.name} ${item.subject} ${item.section}'.toLowerCase().contains(query)).toList();
            return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your classes', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8), Text('Ready when you are, ${profile.name.split(' ').first}.'),
                const SizedBox(height: 20),
                TextField(onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(hintText: 'Find a class', prefixIcon: Icon(Icons.search_rounded))),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  ChoiceChip(label: Text('Active (${all.where((item) => !item.archived).length})'),
                    selected: !_archived, onSelected: (_) => setState(() => _archived = false)),
                  ChoiceChip(label: Text('Archived (${all.where((item) => item.archived).length})'),
                    selected: _archived, onSelected: (_) => setState(() => _archived = true)),
                ]),
                const SizedBox(height: 24),
                if (snapshot.hasError) ...[
                  const ErrorNotice('Could not load your classes.'),
                  TextButton.icon(onPressed: () => setState(() => _classes = _repository.watchClasses()),
                    icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                ] else if (!snapshot.hasData) const Center(child: Padding(
                  padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
                else if (visible.isEmpty) _empty(query.isNotEmpty)
                else LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 600 ? 2 : 1;
                  final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
                  return Wrap(spacing: 16, runSpacing: 16, children: [for (final item in visible)
                    SizedBox(width: width, child: _ClassCard(item: item, onTap: () => _open(item.id))),
                  ]);
                }),
                if (widget.controller.error != null) ...[const SizedBox(height: 20), ErrorNotice(widget.controller.error!)],
                const SizedBox(height: 24),
                TextButton.icon(onPressed: widget.controller.busy ? null : widget.controller.previewOnboarding,
                  icon: const Icon(Icons.replay_rounded, size: 18), label: const Text('Preview onboarding')),
              ],
            ));
          })),
          Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PrimaryButton(label: 'Create class', icon: Icons.add_rounded,
              onPressed: widget.controller.busy ? null : _create),
          )),
        ]),
      ))),
    );
  }
  Widget _empty(bool searching) => SizedBox(width: double.infinity, child: Column(children: [
    if (!searching && !_archived) const LearningArt(compact: true, expression: MascotExpression.friendly)
    else Padding(padding: const EdgeInsets.all(30), child: Icon(searching ? Icons.search_off_rounded : Icons.inventory_2_outlined, size: 44, color: teal)),
    const SizedBox(height: 12),
    Text(searching ? 'No matching classes' : _archived ? 'No archived classes' : 'Room for your first class',
      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(searching ? 'Try another name.' : _archived ? 'Archived classes will appear here.' : 'A new class. A fresh start.', textAlign: TextAlign.center),
  ]));
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.item, required this.onTap});
  final FiloClass item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: line)),
    child: InkWell(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(height: 96, width: double.infinity, color: classColor(item.color),
        alignment: Alignment.centerLeft, padding: const EdgeInsets.all(24),
        child: Icon(classIcon(item.color), color: teal, size: 36)),
      Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, style: const TextStyle(fontSize: 21, height: 1.2, color: ink, fontWeight: FontWeight.w900)),
        if (item.subject.isNotEmpty || item.section.isNotEmpty) ...[
          const SizedBox(height: 8), Text([item.subject, item.section].where((part) => part.isNotEmpty).join(' / ')),
        ],
        const SizedBox(height: 16), const Align(alignment: Alignment.centerRight,
          child: Icon(Icons.arrow_forward_rounded, color: teal, size: 20)),
      ])),
    ])),
  );
}
