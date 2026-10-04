import 'dart:async';
import 'student_classes.dart';
import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';
import '../onboarding/onboarding_repository.dart';
import '../account/account_screen.dart';
import '../classes/join_class_screen.dart';
import 'material_notifications.dart';
import 'material_screen.dart';
import 'material_sync.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with WidgetsBindingObserver {
  late final String _uid = widget.controller.user!.uid;
  late final MaterialSync _sync = MaterialSync(_uid);
  late final MaterialNotifications _notifications;
  StreamSubscription<({List<StudentClass> classes, bool offline})>? _subscription;
  List<StudentClass>? _classes;
  bool _error = false, _offline = false, _notificationError = false, _signingOut = false;
  String? _pendingClass;
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
        _openPending();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('New class material'),
          action: SnackBarAction(label: 'View', onPressed: () {
            _pendingClass = id; _openPending();
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
      if (item.id == id) { _pendingClass = null; _open(item); return; }
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
    _subscription?.cancel(); _notifications.dispose(); _sync.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Brand(), actions: [
      AccountButton(controller: widget.controller,
        enabled: !_signingOut, onSignOut: _signOut),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
      child: ListenableBuilder(listenable: _sync, builder: (context, _) =>
        ListView(padding: const EdgeInsets.all(24), children: [
          Text('Your classes', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          if (_offline) const Text('Showing saved materials'),
          if (_sync.states.containsValue(FileSyncState.downloading)) const LinearProgressIndicator(),
          if (_sync.states.containsValue(FileSyncState.failed) || _sync.errors.isNotEmpty)
            TextButton.icon(onPressed: _sync.retry, icon: const Icon(Icons.sync_rounded), label: const Text('Retry downloads')),
          if (_notificationError) TextButton.icon(onPressed: _enableNotifications,
            icon: const Icon(Icons.notifications_outlined), label: const Text('Enable notifications')),
          const SizedBox(height: 20),
          if (_error) ...[
            const ErrorNotice('Could not load your classes.'),
            TextButton(onPressed: _listen, child: const Text('Retry')),
          ] else if (_classes == null) const FiloSkeleton(
            layout: SkeletonLayout.rows, scrollable: false, padding: EdgeInsets.zero)
          else if (_classes!.isEmpty) const Column(children: [
            LearningArt(compact: true, expression: MascotExpression.curious),
            SizedBox(height: 12), Text('Your class materials will appear here.'),
          ]) else for (final item in _classes!) Card(child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.folder_outlined, color: teal, size: 32),
            title: Text(item.name),
            subtitle: Text(item.archived ? 'Archived' :
              '${_sync.materials[item.id]?.length ?? 0} materials'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _open(item))),
          if (widget.controller.error != null) ErrorNotice(widget.controller.error!),
        ])),
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
