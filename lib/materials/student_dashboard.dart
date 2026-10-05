import 'dart:async';
import 'student_classes.dart';
import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import '../onboarding/onboarding_repository.dart';
import '../account/account_screen.dart';
import '../classes/join_class_screen.dart';
import '../classes/class_card.dart';
import 'author_cache.dart';
import 'material_notifications.dart';
import 'material_screen.dart';
import 'material_sync.dart';
import 'material_repository.dart';
import 'notification_read_state.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with WidgetsBindingObserver {
  late final String _uid = widget.controller.user!.uid;
  late final MaterialSync _sync = MaterialSync(_uid);
  late final NotificationReadState _readState = NotificationReadState(_uid);
  late final MaterialNotifications _notifications;
  StreamSubscription<({List<StudentClass> classes, bool offline})>? _subscription;
  List<StudentClass>? _classes;
  bool _error = false, _offline = false, _notificationError = false, _signingOut = false;
  String? _pendingClass;
  String? _pendingMaterial;
  String? _search;
  List<ClassMaterial> get _recentUpdates {
    final ids = (_classes ?? <StudentClass>[]).map((item) => item.id).toSet();
    final items = _sync.materials.values.expand((items) => items)
      .where((item) => ids.contains(item.classId) && item.parentId.isEmpty)
      .toList()..sort((a, b) => (b.createdAt ?? DateTime(1970))
        .compareTo(a.createdAt ?? DateTime(1970)));
    return items.take(30).toList();
  }
  Future<void> _markRead(String key) async {
    final saved = await _readState.markRead(key);
    if (!saved && mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save read status. Try again.')));
  }
  List<StudentClass> get _visibleClasses {
    final query = (_search ?? '').trim().toLowerCase();
    return (_classes ?? const <StudentClass>[]).where((item) =>
      '${item.name} ${item.subject} ${item.section}'.toLowerCase().contains(query)).toList();
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications = MaterialNotifications(_uid, (message, opened) {
      if (!mounted) return;
      _sync.retry();
      final id = message.data['classId'];
      if (opened) {
        _pendingClass = id;
        _pendingMaterial = message.data['materialId'];
        _openPending();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('New class material'),
          action: SnackBarAction(label: 'View', onPressed: () {
            _pendingClass = id;
            _pendingMaterial = message.data['materialId'];
            _openPending();
          })));
      }
    });
    _listen();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _enableNotifications(); });
  }
  void _listen() {
    _subscription?.cancel();
    _subscription = StudentClasses(_uid).watch().listen((snapshot) {
      if (!mounted) return;
      setState(() { _classes = snapshot.classes; _offline = snapshot.offline; _error = false; });
      if (!snapshot.offline || snapshot.classes.isNotEmpty) {
        _sync.setClasses(snapshot.classes.map((course) => course.id));
      }
      _openPending();
    }, onError: (Object _) { if (mounted) setState(() => _error = true); });
  }
  Future<void> _enableNotifications() async {
    try {
      await _notifications.start();
      if (mounted) setState(() => _notificationError = false);
    } catch (_) {
      if (mounted) setState(() => _notificationError = true);
    }
  }
  void _openPending() {
    final id = _pendingClass;
    if (id == null || _classes == null) return;
    for (final item in _classes!) {
      if (item.id == id) {
        _pendingClass = null;
        final materialId = _pendingMaterial;
        _pendingMaterial = null;
        if (materialId != null) unawaited(_markRead('$id/$materialId'));
        _open(item); return;
      }
    }
  }
  void _open(StudentClass item) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => MaterialScreen(classId: item.id,
      className: item.name, uid: _uid, sync: _sync, allowLeave: true)));
  Future<void> _join() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => JoinClassScreen(uid: _uid)));
    if (!mounted || id == null) return;
    _pendingClass = id;
    _openPending();
  }
  void _showNotifications() => showModalBottomSheet<void>(
    context: context, showDragHandle: true, isScrollControlled: true,
    backgroundColor: cream,
    builder: (sheetContext) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .65,
      child: ListenableBuilder(listenable: Listenable.merge([_sync, _readState]), builder: (context, _) {
        final classes = {for (final item in _classes ?? <StudentClass>[]) item.id: item};
        final updates = _recentUpdates;
        final loading = _classes == null || classes.keys.any((id) => !_sync.materials.containsKey(id));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4), const Text('Recent class updates'),
            ])),
          if (_notificationError) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(onPressed: _enableNotifications,
              icon: const Icon(Icons.notifications_outlined), label: const Text('Enable notifications'))),
          if (_readState.loadFailed) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(onPressed: _readState.load,
              child: const Text('Retry read status'))),
          Expanded(child: updates.isEmpty
            ? Center(child: _error || _sync.errors.isNotEmpty || loading
              ? Text(_error || _sync.errors.isNotEmpty ? 'Could not load updates.' : 'Loading updates…')
              : const Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 112, height: 112, child: LearningArt(
                    compact: true, expression: MascotExpression.friendly)),
                  SizedBox(height: 12), Text('No class updates yet.'),
                ]))
            : ListView.builder(itemCount: updates.length > 30 ? 30 : updates.length,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemBuilder: (context, index) {
                final item = updates[index];
                final unread = _readState.ready && !_readState.isRead(item.cacheKey);
                return Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Material(color: unread ? mint : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: unread ? teal.withValues(alpha: .3) : line)),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                  leading: Icon(!_readState.ready ? Icons.notifications_none_rounded
                    : unread ? Icons.notifications_active_rounded
                    : Icons.check_circle_outline_rounded, color: unread ? teal : muted),
                  title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
                  subtitle: Text(classes[item.classId]!.name),
                  trailing: unread ? Semantics(label: 'Unread', child: const Icon(
                    Icons.circle, color: Color(0xFFD84848), size: 9))
                    : Semantics(label: _readState.ready ? 'Read' : 'Loading read status',
                      child: const Icon(Icons.chevron_right_rounded)),
                  onTap: () {
                    unawaited(_markRead(item.cacheKey));
                    Navigator.pop(sheetContext);
                    if (mounted) _open(classes[item.classId]!);
                  })));
              })),
        ]);
      }),
    )));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { _listen(); _sync.retry(); }
  }
  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      try { await _notifications.unregister(); } catch (_) {
        // Notification cleanup is best effort; always proceed to sign out.
      }
      await widget.controller.signOut();
      if (mounted && widget.controller.stage == OnboardingStage.home) await _enableNotifications();
    } catch (_) {
      if (mounted) await _enableNotifications();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not sign out. Please try again.')));
    } finally { if (mounted) setState(() => _signingOut = false); }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel(); _notifications.dispose(); _sync.dispose(); _readState.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 16, 16, 4), child: Row(children: [
          const Brand(), const Spacer(),
          ListenableBuilder(listenable: Listenable.merge([_sync, _readState]),
            builder: (context, _) {
              final unread = _readState.ready && _recentUpdates.any((item) => !_readState.isRead(item.cacheKey));
              return IconButton(tooltip: unread ? 'Notifications, unread updates' : 'Notifications',
                icon: Stack(clipBehavior: Clip.none, children: [
                  Icon(unread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
                  if (unread) Positioned(top: -1, right: -1, child: Container(
                    width: 10, height: 10, decoration: BoxDecoration(
                      color: const Color(0xFFD84848), shape: BoxShape.circle,
                      border: Border.all(color: cream, width: 2)))),
                ]), onPressed: _signingOut ? null : _showNotifications);
            }),
          AccountButton(controller: widget.controller,
            enabled: !_signingOut, onSignOut: _signOut),
        ])),
      Expanded(child: ListenableBuilder(listenable: _sync, builder: (context, _) =>
        ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your classes', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text('Ready when you are, ${widget.controller.profile!.name.split(' ').first}.'),
            ])),
            const SizedBox(width: 12),
            SizedBox(width: 96, height: 96, child: LearningArt(compact: true,
              expression: (_search ?? '').trim().isNotEmpty ? MascotExpression.curious
                : (_classes ?? <StudentClass>[]).isNotEmpty ? MascotExpression.proud
                : MascotExpression.friendly)),
          ]),
          const SizedBox(height: 20),
          TextField(onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(hintText: 'Find a class',
              prefixIcon: Icon(Icons.search_rounded))),
          if (_offline) const Text('Showing saved materials'),
          if (_sync.states.containsValue(FileSyncState.downloading)) const LinearProgressIndicator(),
          if (_sync.states.containsValue(FileSyncState.failed) || _sync.errors.isNotEmpty)
            TextButton.icon(onPressed: _sync.retry, icon: const Icon(Icons.sync_rounded), label: const Text('Retry downloads')),
          if (_notificationError) TextButton.icon(onPressed: _enableNotifications,
            icon: const Icon(Icons.notifications_outlined), label: const Text('Enable notifications')),
          const SizedBox(height: 24),
          if (_error) ...[
            const ErrorNotice('Could not load your classes.'),
            TextButton(onPressed: _listen, child: const Text('Retry')),
          ] else if (_classes == null) const FiloSkeleton(
            layout: SkeletonLayout.rows, scrollable: false, padding: EdgeInsets.zero)
          else if (_classes!.isEmpty) const Column(children: [
            Icon(Icons.auto_stories_outlined, color: teal, size: 44),
            SizedBox(height: 12), Text('Your class materials will appear here.'),
          ]) else if (_visibleClasses.isEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(children: [
              const Icon(Icons.search_off_rounded, color: teal, size: 44),
              const SizedBox(height: 12),
              Text('No matching classes', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8), const Text('Try another name.'),
            ]))
          else LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 600 ? 2 : 1;
            final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final item in _visibleClasses) SizedBox(width: width,
                child: ClassCard(name: item.name, subject: item.subject,
                  section: item.section, color: item.color, archived: item.archived,
                  instructor: ValueListenableBuilder<AuthorProfileState>(
                    valueListenable: AuthorCache.instance.watch(_uid, item.instructorId),
                    builder: (context, profile, _) {
                      if (profile.loading) return const FiloSkeleton(
                        layout: SkeletonLayout.author, scrollable: false,
                        padding: EdgeInsets.zero);
                      final data = profile.data;
                      final name = data?['name'] as String? ??
                        data?['displayName'] as String? ?? 'Instructor';
                      return Row(children: [
                        ProfileAvatar(avatar: (data?['avatar'] as num?)?.toInt() ?? -1,
                          photoUrl: data?['photoUrl'] as String?, size: 36),
                        const SizedBox(width: 10),
                        Expanded(child: Text(name.trim().isEmpty ? 'Instructor' : name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall)),
                      ]);
                    }),
                  footer: '${_sync.materials[item.id]?.length ?? 0} materials',
                  onTap: () => _open(item))),
            ]);
          }),
          if (widget.controller.error != null) ErrorNotice(widget.controller.error!),
        ]))),
      ]),
    ))),
    bottomNavigationBar: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Center(heightFactor: 1, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: PrimaryButton(label: 'Join class', icon: Icons.add_rounded,
          onPressed: _signingOut ? null : _join))),
    )),
  );
}
