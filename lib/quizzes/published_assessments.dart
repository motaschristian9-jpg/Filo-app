import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'assessment_attempt_screen.dart';
import 'assessment_review_screen.dart';
import 'classwork_management.dart';

class PublishedAssessments extends StatefulWidget {
  const PublishedAssessments({super.key, required this.classId, this.materialCards = const [],
    this.instructorView = false, this.hasOlderMaterials = false, this.onLoadOlderMaterials});
  final bool hasOlderMaterials;
  final VoidCallback? onLoadOlderMaterials;
  final bool instructorView;
  final String classId;
  final List<Widget> materialCards;
  @override
  State<PublishedAssessments> createState() => _PublishedAssessmentsState();
}

class _PublishedAssessmentsState extends State<PublishedAssessments> {
  int _limit = 30;
  late final _query = FirebaseFirestore.instance.collection('classes').doc(widget.classId)
    .collection('assessments').orderBy('publishedAt', descending: true);
  late var _stream = _query.limit(_limit).snapshots();
  String get classId => widget.classId;
  bool get instructorView => widget.instructorView;
  List<Widget> get materialCards => widget.materialCards;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _stream,
    builder: (context, snapshot) => ListView(primary: false,
      key: PageStorageKey('classwork-$classId'), padding: const EdgeInsets.all(24), children: [
      ...materialCards,
      if (widget.hasOlderMaterials) TextButton(onPressed: widget.onLoadOlderMaterials,
        child: const Text('Load older posts')),
      if (snapshot.hasError) const ErrorNotice('Could not load assessments. Reopen this class.')
      else if (!snapshot.hasData) const FiloSkeleton(scrollable: false, padding: EdgeInsets.zero)
      else if (!snapshot.data!.docs.any((doc) => doc.data()['hidden'] != true) && materialCards.isEmpty &&
          !widget.hasOlderMaterials && snapshot.data!.docs.length < _limit)
        Container(padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(24)),
          child: const Column(children: [
            Icon(Icons.assignment_outlined, size: 40, color: teal),
            SizedBox(height: 12), Text('No classwork yet.'),
          ]))
      else for (final doc in snapshot.data!.docs.where((doc) => doc.data()['hidden'] != true)) Card(child: ListTile(
        leading: const Icon(Icons.quiz_outlined, color: teal),
        title: Text(doc.data()['title'] as String),
        subtitle: Text('${doc.data()['kind'] == 'exam' ? 'Exam' : 'Quiz'} · ${doc.data()['minutes']} min'
          '${instructorView ? ' · View results' : ''}'),
        trailing: instructorView ? PopupMenuButton<String>(tooltip: 'Assessment options',
          itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit title')),
            PopupMenuItem(value: 'delete', child: Text('Delete'))],
          onSelected: (action) async {
            try { await manageClasswork(context, classId, doc.id, doc.data(), action); }
            catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error is FirebaseException
                ? 'Could not update assessment (${error.code}).' : 'Could not update assessment. Please retry.'))); }
          }) : const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => instructorView
          ? AssessmentReviewScreen(classId: classId, id: doc.id, title: doc.data()['title'] as String)
          : AssessmentAttemptScreen(classId: classId, id: doc.id, title: doc.data()['title'] as String))),
      )),
      if (snapshot.hasData && snapshot.data!.docs.length >= _limit)
        TextButton(onPressed: () => setState(() {
          _limit += 30;
          _stream = _query.limit(_limit).snapshots();
        }), child: const Text('Load older assessments')),
    ]),
  );
}
