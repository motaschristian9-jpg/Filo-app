import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import '../onboarding/onboarding_repository.dart';
import '../account/account_screen.dart';
import 'class_detail_screen.dart';
import 'class_editor.dart';
import 'class_card.dart';
import 'class_repository.dart';
import '../materials/material_screen.dart';

class InstructorDashboard extends StatefulWidget {
  const InstructorDashboard({super.key, required this.controller,
    this.archivedOnly = false});
  final OnboardingController controller;
  final bool archivedOnly;
  @override
  State<InstructorDashboard> createState() => _InstructorDashboardState();
}
class _InstructorDashboardState extends State<InstructorDashboard> {
  late final ClassRepository _repository;
  late Stream<List<FiloClass>> _classes;
  bool get _archived => widget.archivedOnly;
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
    _open(id);
  }
  void _open(String id) => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => StreamBuilder<FiloClass?>(stream: _repository.watchClass(id),
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (snapshot.hasError) return Scaffold(appBar: AppBar(),
          body: Center(child: TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Could not load class. Go back and retry.'))));
        if (!snapshot.hasData) return Scaffold(appBar: AppBar(),
          body: snapshot.connectionState == ConnectionState.waiting
            ? const FiloSkeleton(layout: SkeletonLayout.details)
            : const Center(child: Text('This class is no longer available.')));
        return MaterialScreen(classId: item!.id, className: item.name,
          uid: _repository.instructorId, canPost: !item.archived, instructorView: true,
          onClassDetails: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => ClassDetailScreen(repository: _repository, classId: id))));
      })));
  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile!;
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 16, 16, 4), child: Row(children: [
            if (_archived) BackButton(onPressed: () => Navigator.pop(context)),
            const Brand(), const Spacer(),
            if (!_archived) IconButton(
              tooltip: 'Archived classes', icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => InstructorDashboard(controller: widget.controller,
                  archivedOnly: true)))),
            AccountButton(controller: widget.controller,
              onSignOut: widget.controller.signOut),
          ])),
          Expanded(child: StreamBuilder<List<FiloClass>>(stream: _classes, builder: (context, snapshot) {
            final all = snapshot.data ?? const <FiloClass>[];
            final query = _search.trim().toLowerCase();
            final visible = all.where((item) => item.archived == _archived &&
              '${item.name} ${item.subject} ${item.section}'.toLowerCase().contains(query)).toList();
            return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_archived ? 'Archived classes' : 'Your classes',
                      style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text(_archived ? 'Your past classes, kept together.'
                      : 'Ready when you are, ${profile.name.split(' ').first}.'),
                  ])),
                  const SizedBox(width: 12),
                  SizedBox(width: 96, height: 96, child: LearningArt(compact: true, useRive: true,
                    expression: query.isNotEmpty ? MascotExpression.curious
                      : !_archived && all.any((item) => !item.archived) ? MascotExpression.proud
                      : MascotExpression.friendly)),
                ]),
                const SizedBox(height: 20),
                TextField(onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(hintText: 'Find a class', prefixIcon: Icon(Icons.search_rounded))),
                const SizedBox(height: 24),
                if (snapshot.hasError) ...[
                  const ErrorNotice('Could not load your classes.'),
                  TextButton.icon(onPressed: () => setState(() => _classes = _repository.watchClasses()),
                    icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                ] else if (!snapshot.hasData) const FiloSkeleton(
                  scrollable: false, padding: EdgeInsets.zero)
                else if (visible.isEmpty) _empty(query.isNotEmpty)
                else LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 600 ? 2 : 1;
                  final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
                  return Wrap(spacing: 16, runSpacing: 16, children: [for (final item in visible)
                    SizedBox(width: width, child: ClassCard(name: item.name,
                      subject: item.subject, section: item.section, color: item.color,
                      archived: item.archived,
                      bannerSubtitle: item.subject.trim().isEmpty ? null : item.subject,
                      details: _ClassInfo(item: item),
                      footerContent: _StudentCount(key: ValueKey(item.id),
                        repository: _repository, classId: item.id),
                      onTap: () => _open(item.id))),
                  ]);
                }),
                if (widget.controller.error != null) ...[const SizedBox(height: 20), ErrorNotice(widget.controller.error!)],
              ],
            ));
          })),
          if (!_archived) Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PrimaryButton(label: 'Create class', icon: Icons.add_rounded,
              onPressed: widget.controller.busy ? null : _create),
          )),
        ]),
      ))),
    );
  }
  Widget _empty(bool searching) => SizedBox(width: double.infinity, child: Column(children: [
    Padding(padding: const EdgeInsets.all(30), child: Icon(searching
      ? Icons.search_off_rounded : _archived ? Icons.inventory_2_outlined
      : Icons.auto_stories_rounded, size: 44, color: teal)),
    const SizedBox(height: 12),
    Text(searching ? 'No matching classes' : _archived ? 'No archived classes' : 'Room for your first class',
      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(searching ? 'Try another name.' : _archived ? 'Archived classes will appear here.' : 'A new class. A fresh start.', textAlign: TextAlign.center),
  ]));
}

class _ClassInfo extends StatelessWidget {
  const _ClassInfo({required this.item});
  final FiloClass item;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.description.trim().isEmpty ? 'No description yet.' : item.description,
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted)),
    ]);
}

class _StudentCount extends StatefulWidget {
  const _StudentCount({super.key, required this.repository, required this.classId});
  final ClassRepository repository;
  final String classId;
  @override
  State<_StudentCount> createState() => _StudentCountState();
}

class _StudentCountState extends State<_StudentCount> {
  late final _count = widget.repository.watchStudentCount(widget.classId);
  @override
  Widget build(BuildContext context) => StreamBuilder<int>(stream: _count,
    builder: (context, snapshot) => Row(children: [
      const Icon(Icons.people_outline_rounded, size: 20, color: teal),
      const SizedBox(width: 8),
      Expanded(child: Text(snapshot.hasError ? 'Count unavailable' : !snapshot.hasData
        ? 'Loading students…' : '${snapshot.data} ${snapshot.data == 1 ? 'student' : 'students'}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: ink, fontWeight: FontWeight.w700))),
    ]));
}

