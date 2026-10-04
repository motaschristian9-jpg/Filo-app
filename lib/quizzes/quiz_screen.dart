import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'quiz_repository.dart';
import 'quiz_editor.dart';
import 'assessment_review_screen.dart';
import 'classwork_management.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.classId, required this.className,
    this.archived = false});
  final String classId, className;
  final bool archived;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  String get classId => widget.classId;
  String get className => widget.className;
  bool get archived => widget.archived;
  late final repository = QuizRepository(classId);
  late final _drafts = repository.watch();
  late final _published = FirebaseFirestore.instance.collection('classes').doc(classId)
    .collection('assessments').snapshots();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 3, child: Scaffold(appBar: AppBar(title: Text(className)),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: StreamBuilder(stream: _drafts, builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Could not load assessments. Reopen this page.'));
          if (!snapshot.hasData) return const FiloSkeleton();
          return StreamBuilder(stream: _published, builder: (context, publicSnapshot) {
            if (publicSnapshot.hasError) return const ErrorNotice('Could not load assessment status. Reopen this page.');
            if (!publicSnapshot.hasData) return const FiloSkeleton();
            final removed = publicSnapshot.data!.docs.where((doc) => doc.data()['hidden'] == true).map((doc) => doc.id).toSet();
            bool matches(dynamic doc, int tab) => tab == 0 ? doc.data()['publishedAt'] == null
              : doc.data()['publishedAt'] != null && removed.contains(doc.id) == (tab == 2);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.all(24),
              child: Text('Quizzes & exams', style: Theme.of(context).textTheme.headlineMedium)),
            const FiloTabs(labels: ['Drafts', 'Published', 'Removed'], scrollable: false),
            Expanded(child: TabBarView(children: [for (final tab in [0, 1, 2])
              ListView(padding: const EdgeInsets.all(24), children: [
            if (!snapshot.data!.docs.any((doc) => matches(doc, tab)))
              Text(tab == 0 ? 'No drafts yet.' : tab == 1 ? 'No published assessments yet.' : 'No removed assessments.'),
            for (final doc in snapshot.data!.docs.where((doc) =>
              matches(doc, tab))) Card(child: ListTile(
              leading: Icon(tab != 0 ? Icons.check_circle_rounded : Icons.edit_note_rounded,
                color: tab != 0 ? teal : muted),
              title: Text(doc.data()['title'] as String? ?? 'Assessment'),
              subtitle: Text('${doc.data()['kind'] == 'exam' ? 'Exam' : 'Quiz'} · '
                '${doc.data()['minutes']} min · ${(doc.data()['questions'] as List).length} questions · ${doc.data()['publishedAt'] == null ? 'Draft' : 'View results'}'),
              trailing: tab == 2 ? const Icon(Icons.chevron_right_rounded) : PopupMenuButton<String>(tooltip: 'Assessment options',
                itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(tab != 0 ? 'Edit title' : 'Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete'))],
                onSelected: (action) async {
                  try { await manageClasswork(context, classId, doc.id, doc.data(), action); }
                  catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not update assessment. Please retry.'))); }
                }),
              onTap: doc.data()['publishedAt'] != null ? () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => AssessmentReviewScreen(classId: classId, id: doc.id, title: doc.data()['title'] as String)))
                : archived ? null : () => Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => QuizEditor(repository: repository, id: doc.id, existing: doc.data()))),
            )),
              ]),
            ])),
          ]);
          });
        }),
      ))),
      bottomNavigationBar: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(24),
        child: Center(heightFactor: 1, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: PrimaryButton(label: 'Create assessment', icon: Icons.add_rounded,
            onPressed: archived ? null : () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => QuizEditor(repository: repository)))),
        )))),
    ));
  }
}
