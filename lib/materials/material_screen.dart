import 'package:flutter/material.dart';

import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';

import 'material_detail_screen.dart';
import 'material_composer.dart';
import 'material_repository.dart';
import 'material_sync.dart';
import 'student_classes.dart';
import 'material_management.dart';
import 'link_preview.dart';
import 'material_cache.dart';
import 'download_index.dart';
import 'due_date.dart';
import 'classwork_feed.dart';
import '../quizzes/quiz_screen.dart';

class MaterialScreen extends StatefulWidget {
  const MaterialScreen({super.key, required this.classId, required this.className,
    required this.uid, this.canPost = false, this.sync, this.allowLeave = false,
    this.instructorView = false, this.onClassDetails});
  final VoidCallback? onClassDetails;
  final bool instructorView;
  final String classId, className, uid;
  final bool canPost;
  final bool allowLeave;
  final MaterialSync? sync;
  @override
  State<MaterialScreen> createState() => _MaterialScreenState();
}

class _MaterialScreenState extends State<MaterialScreen> {
  bool _leaving = false;
  bool _classworkVisited = false;
  bool _filesVisited = false;
  int _materialLimit = 60, _streamLimit = 30, _filesLimit = 30;
  final _streamScroll = ScrollController(), _filesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    DownloadIndex.instance.revision.addListener(_downloadsChanged);
  }
  void _downloadsChanged() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    DownloadIndex.instance.revision.removeListener(_downloadsChanged);
    _streamScroll.dispose(); _filesScroll.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || !widget.allowLeave) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: const Text('Leave class?'),
        content: const Text('Saved files will be removed from Filo. You can rejoin with the class code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay here')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave class')),
        ]));
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    try {
      await StudentClasses(widget.uid).leave(widget.classId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left class')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not leave class. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  int _section = 0;
  String _fileFilter = 'All';
  static const _fileTypes = ['All', 'Images', 'PDFs', 'Documents',
    'Presentations', 'Spreadsheets', 'Other'];
  String _fileType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic' || 'heif' || 'tif' || 'tiff' => 'Images',
      'pdf' => 'PDFs',
      'doc' || 'docx' || 'odt' || 'rtf' || 'txt' || 'md' => 'Documents',
      'ppt' || 'pptx' || 'odp' || 'key' => 'Presentations',
      'xls' || 'xlsx' || 'ods' || 'csv' || 'numbers' => 'Spreadsheets',
      _ => 'Other',
    };
  }
  static const _labels = ['Stream', 'Files', 'Classwork'];


  late Stream<List<ClassMaterial>> _stream = MaterialRepository().watch(widget.classId, limit: _materialLimit);
  void _loadOlderMaterials() => setState(() {
    _materialLimit += 60;
    _stream = MaterialRepository().watch(widget.classId, limit: _materialLimit);
  });
  final Set<String> _opening = {};

  Future<void> _open(ClassMaterial item) async {
    if (_opening.contains(item.id)) return;
    setState(() => _opening.add(item.id));
    try {
      await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) =>
        MaterialDetailScreen(material: item, className: widget.className,
          uid: widget.uid, sync: widget.sync)));
    } finally { if (mounted) setState(() => _opening.remove(item.id)); }
  }

  @override
  Widget build(BuildContext context) => widget.sync != null
    ? ListenableBuilder(listenable: widget.sync!, builder: (_, _) =>
        _room(widget.sync!.materials[widget.classId],
          error: widget.sync!.errors.contains(widget.classId) || !widget.sync!.hasClass(widget.classId)))
    : StreamBuilder<List<ClassMaterial>>(stream: _stream,
        builder: (_, snapshot) => _room(snapshot.data, error: snapshot.hasError));

  Widget _room(List<ClassMaterial>? items, {required bool error}) => Scaffold(
    appBar: AppBar(title: Text(widget.className), actions: [
      if (widget.instructorView && widget.onClassDetails != null) PopupMenuButton<String>(
        tooltip: 'Class options', onSelected: (_) => widget.onClassDetails!(),
        itemBuilder: (_) => const [PopupMenuItem(value: 'details',
          child: Text('Class details & students'))]),
      if (widget.allowLeave) PopupMenuButton<String>(
        tooltip: 'Class options', enabled: !_leaving,
        onSelected: (_) => _leave(),
        itemBuilder: (_) => const [PopupMenuItem(value: 'leave',
          child: Text('Leave class'))]),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Text(_labels[_section], style: Theme.of(context).textTheme.headlineLarge)),
        Expanded(child: IndexedStack(index: _section == 2 ? 1 : 0, children: [
          widget.sync != null && !widget.sync!.hasClass(widget.classId)
            ? const Center(child: Text('This class is no longer available.'))
            : _list(items, error: error),
          if (_classworkVisited) ClassworkFeed(classId: widget.classId, className: widget.className,
            uid: widget.uid, instructorView: widget.instructorView, sync: widget.sync,
            materials: items, error: error,
            hasOlderMaterials: widget.sync == null && (items?.length ?? 0) >= _materialLimit,
            onLoadOlderMaterials: _loadOlderMaterials)
          else const SizedBox.shrink(),
        ])),
        if (widget.canPost) Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PrimaryButton(label: _section == 2 ? 'Manage classwork' : 'Create post',
              icon: _section == 2 ? Icons.quiz_outlined : Icons.add_rounded,
              onPressed: _section == 2 ? () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => QuizScreen(classId: widget.classId, className: widget.className))) : _post),
          )),
        ),
      ]),
    ))),
    bottomNavigationBar: NavigationBar(
      backgroundColor: cream, indicatorColor: mint,
      selectedIndex: _section,
      onDestinationSelected: (index) => setState(() {
        _section = index;
        if (index == 1) _filesVisited = true;
        if (index == 2) _classworkVisited = true;
      }),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum_rounded, color: teal), label: 'Stream'),
        NavigationDestination(icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded, color: teal), label: 'Files'),
        NavigationDestination(icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment_rounded, color: teal), label: 'Classwork'),
      ],
    ),
  );

  Future<void> _post() async {
    final kind = await Navigator.push<String>(context, MaterialPageRoute<String>(
      builder: (_) => MaterialComposer(classId: widget.classId)));
    if (mounted && kind != null) {
      setState(() => _section = kind == 'file' ? 1 : 0);
    }
  }

  Widget _list(List<ClassMaterial>? items, {required bool error}) {
    if (error) return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const ErrorNotice('Could not load materials.'),
      TextButton(onPressed: () {
        if (widget.sync != null) { widget.sync!.retry(); }
        else { setState(() => _stream = MaterialRepository().watch(widget.classId, limit: _materialLimit)); }
      }, child: const Text('Retry')),
    ]);
    if (items == null) return const FiloSkeleton();
    return IndexedStack(index: _section == 1 ? 1 : 0, children: [
      _category(items, 'stream'),
      if (_filesVisited) _category(items, 'file') else const SizedBox.shrink(),
    ]);
  }

  Widget _category(List<ClassMaterial> items, String kind) {
    final category = items.where((item) => kind == 'stream'
      ? item.parentId.isEmpty : kind == 'file' ? item.hasFile || LinkPreview.parse(item.url)?.label == 'Google Drive' : item.kind == kind).toList();
    final matching = kind == 'file' && _fileFilter != 'All'
      ? category.where((item) => _fileType(item.fileName) == _fileFilter).toList() : category;
    final displayLimit = kind == 'file' ? _filesLimit : _streamLimit;
    final visible = matching.take(displayLimit).toList();
    final moreLocal = matching.length > displayLimit;
    final moreRemote = widget.sync == null && items.length >= _materialLimit;
    final attachmentCounts = <String, int>{};
    for (final item in items) {
      if (item.parentId.isNotEmpty) attachmentCounts.update(item.parentId, (count) => count + 1, ifAbsent: () => 1);
    }
    final emptyLabel = switch (kind) {
      'file' => 'No files yet.',
      'stream' => 'No posts yet.',
      _ => 'No announcements yet.',
    };
    return ListView.builder(key: PageStorageKey('materials-${widget.classId}-$kind'),
      controller: kind == 'file' ? _filesScroll : _streamScroll,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      itemCount: 1 + (visible.isEmpty ? 1 : visible.length) + (moreLocal || moreRemote ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) return kind == 'file' ? Padding(padding: const EdgeInsets.only(bottom: 20),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final type in _fileTypes) Padding(padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(type), selected: _fileFilter == type,
                onSelected: (_) => setState(() { _fileFilter = type; _filesLimit = 30; }))),
          ]))) : const SizedBox.shrink();
        if (index == 1 && visible.isEmpty) return Container(padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(24)),
          child: Column(children: [
            const SizedBox(width: 112, height: 112, child: LearningArt(
              compact: true, expression: MascotExpression.curious)),
            const SizedBox(height: 12), Text(kind == 'file' && _fileFilter != 'All'
              ? 'No ${_fileFilter.toLowerCase()}${moreRemote ? ' in loaded posts.' : ' yet.'}'
              : moreRemote ? 'No matching items in loaded posts.' : emptyLabel),
          ]));
        if (index <= visible.length) {
          final item = visible[index - 1];
          return _card(item, attachmentCount: moreRemote && item.attachmentIds.isNotEmpty
            ? item.attachmentIds.length : attachmentCounts[item.id] ?? 0);
        }
        return TextButton(onPressed: () {
          if (moreLocal) setState(() { if (kind == 'file') { _filesLimit += 30; } else { _streamLimit += 30; } });
          else _loadOlderMaterials();
        }, child: const Text('Load more'));
      });
  }

  Widget _card(ClassMaterial item, {int attachmentCount = 0}) {
    final state = widget.sync?.states[item.cacheKey];
    final preview = item.kind == 'link' ? LinkPreview.parse(item.url) : null;
    return Card(margin: const EdgeInsets.only(bottom: 16), child: InkWell(
      onTap: _opening.contains(item.id) ? null : () => _open(item),
      borderRadius: BorderRadius.circular(24),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(switch (item.kind) {
              'file' => Icons.description_outlined,
              'link' => Icons.link_rounded,
              _ => Icons.campaign_outlined,
            }, color: teal),
            const SizedBox(width: 12),
            Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(width: 8),
            if (widget.instructorView) PopupMenuButton<String>(tooltip: 'Post options',
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete'))],
              onSelected: (action) async {
                try { await manageMaterial(context, item, action); }
                catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not update this post. Please retry.'))); }
              })
            else const Icon(Icons.chevron_right_rounded, color: teal),
          ]),
          if (item.createdAt != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(MaterialLocalizations.of(context).formatMediumDate(item.createdAt!.toLocal()),
              style: Theme.of(context).textTheme.bodySmall)),
          if (item.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (item.requiresSubmission) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('Submission required · ${item.maxPoints} points', style: Theme.of(context).textTheme.bodySmall)),
          if (item.requiresSubmission && item.dueAt != null) Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('Due ${formatDueDate(context, item.dueAt!)}', style: Theme.of(context).textTheme.bodySmall)),
          if (attachmentCount > 0) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text('$attachmentCount attachment${attachmentCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall)),
          if (item.hasFile) ...[
            const SizedBox(height: 12),
            Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
            if (state == FileSyncState.ready) const Padding(
              padding: EdgeInsets.only(top: 4), child: Text('Available offline')),
            if (state == FileSyncState.downloading) const Padding(
              padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          ],
          if (item.kind == 'link') Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(preview != null
              ? '${preview.label} · ${preview.action}' : Uri.tryParse(item.url)?.host ?? item.url,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall)),
          if (item.kind == 'link' && preview?.label == 'Google Drive')
            FutureBuilder<bool>(future: MaterialCache(widget.uid).containsLink(item),
              builder: (_, snapshot) => snapshot.data == true
                ? const Padding(padding: EdgeInsets.only(top: 8), child: Row(children: [
                    Icon(Icons.offline_pin_rounded, size: 18, color: teal),
                    SizedBox(width: 6), Text('Downloaded'),
                  ])) : const SizedBox.shrink()),
        ]),
      ),
    ));
  }
}
