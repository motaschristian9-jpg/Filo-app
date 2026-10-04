import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../quizzes/published_assessments.dart';
import 'material_repository.dart';
import 'material_sync.dart';
import 'material_detail_screen.dart';
import 'due_date.dart';

class ClassworkFeed extends StatefulWidget {
  const ClassworkFeed({super.key, required this.classId, required this.className,
    required this.uid, required this.instructorView, required this.materials,
    this.error = false, this.sync, this.hasOlderMaterials = false, this.onLoadOlderMaterials});
  final String classId, className, uid;
  final bool instructorView;
  final MaterialSync? sync;
  final List<ClassMaterial>? materials;
  final bool error;
  final bool hasOlderMaterials;
  final VoidCallback? onLoadOlderMaterials;
  @override
  State<ClassworkFeed> createState() => _ClassworkFeedState();
}

class _ClassworkFeedState extends State<ClassworkFeed> {
  int _limit = 30;
  @override
  Widget build(BuildContext context) {
    final items = widget.materials;
    if (widget.error) return const ErrorNotice('Could not load classwork. Reopen this class.');
    if (items == null) return const FiloSkeleton();
    final posts = items.where((p) => p.requiresSubmission && p.parentId.isEmpty).toList();
    return PublishedAssessments(classId: widget.classId, instructorView: widget.instructorView,
      hasOlderMaterials: widget.hasOlderMaterials || posts.length > _limit,
      onLoadOlderMaterials: posts.length > _limit ? () => setState(() => _limit += 30) : widget.onLoadOlderMaterials,
      materialCards: [for (final post in posts.take(_limit))
        Card(child: ListTile(leading: const Icon(Icons.assignment_outlined, color: teal),
          title: Text(post.title), subtitle: Text('Submission required · ${post.maxPoints} points'
            '${post.dueAt == null ? '' : '\nDue ${formatDueDate(context, post.dueAt!)}'}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) =>
            MaterialDetailScreen(material: post, className: widget.className, uid: widget.uid, sync: widget.sync))),
        ))]);
  }
}
