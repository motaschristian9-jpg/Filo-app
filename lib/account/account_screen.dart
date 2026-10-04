import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import '../onboarding/onboarding_repository.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.controller,
    required this.onSignOut, this.enabled = true});
  final OnboardingController controller;
  final Future<void> Function() onSignOut;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Account',
    onPressed: !enabled || controller.busy ? null : () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) =>
        AccountScreen(controller: controller, onSignOut: onSignOut))),
    icon: ProfileAvatar(avatar: controller.profile!.avatar,
      photoUrl: controller.user?.photoUrl, size: 42),
  );
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller, required this.onSignOut});
  final OnboardingController controller;
  final Future<void> Function() onSignOut;

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can come back with Google.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay here')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out')),
        ],
      ));
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    await onSignOut();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final profile = controller.profile;
      if (profile == null || controller.user == null) {
        return const Scaffold(body: SafeArea(child: FiloSkeleton(
          layout: SkeletonLayout.profile)));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Container(padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: mint,
                borderRadius: BorderRadius.circular(28)),
              child: Row(children: [
                ProfileAvatar(avatar: profile.avatar,
                  photoUrl: controller.user!.photoUrl, size: 76),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(controller.user!.email, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text(profile.role == 'instructor' ? 'Instructor' : 'Student',
                      style: const TextStyle(color: teal, fontWeight: FontWeight.w800)),
                  ])),
              ])),
            const SizedBox(height: 28),
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Material(color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: line)),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: controller.busy ? null : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) =>
                    AccountSettingsScreen(controller: controller))),
                child: const Padding(padding: EdgeInsets.all(18),
                  child: Row(children: [
                    Icon(Icons.manage_accounts_outlined, color: teal),
                    SizedBox(width: 16),
                    Expanded(child: Text('Edit profile',
                      style: TextStyle(fontWeight: FontWeight.w800, color: ink))),
                    Icon(Icons.chevron_right_rounded, color: teal),
                  ])),
              )),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: controller.busy ? null : () => _signOut(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ]),
        ))),
      );
    },
  );
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _school, _bio;
  late int _avatar;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile!;
    _name = TextEditingController(text: profile.name);
    _school = TextEditingController(text: profile.school);
    _bio = TextEditingController(text: profile.bio);
    _avatar = profile.avatar;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _chooseAvatar() => showModalBottomSheet<void>(
    context: context, showDragHandle: true, backgroundColor: cream,
    builder: (sheetContext) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Pick your look', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final choice in [
            if (widget.controller.user?.photoUrl != null) -1, 0, 1, 2, 3
          ]) Semantics(
            button: true, selected: choice == _avatar,
            label: choice == -1 ? 'Google photo' : 'Avatar ${choice + 1}',
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () {
                setState(() => _avatar = choice);
                Navigator.pop(sheetContext);
              },
              child: Container(padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: choice == _avatar ? teal : line, width: 2)),
                child: ProfileAvatar(avatar: choice,
                  photoUrl: widget.controller.user?.photoUrl, size: 58)),
            ),
          ),
        ]),
      ]),
    )),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate() || widget.controller.busy) return;
    FocusScope.of(context).unfocus();
    await widget.controller.updateProfile(
      name: _name.text, school: _school.text, bio: _bio.text, avatar: _avatar);
    if (mounted && widget.controller.error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !widget.controller.busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.all(24), children: [
              Center(child: Column(children: [
                ProfileAvatar(avatar: _avatar,
                  photoUrl: widget.controller.user?.photoUrl, size: 90),
                const SizedBox(height: 8),
                TextButton(onPressed: widget.controller.busy ? null : _chooseAvatar,
                  child: const Text('Change avatar')),
              ])),
              const SizedBox(height: 20),
              Form(key: _form, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(controller: _name, maxLength: 60,
                  enabled: !widget.controller.busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add your name.' : null),
                const SizedBox(height: 12),
                TextFormField(initialValue: widget.controller.user?.email ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Google email',
                    suffixIcon: Icon(Icons.lock_outline_rounded))),
                const SizedBox(height: 12),
                TextFormField(controller: _school, maxLength: 100,
                  enabled: !widget.controller.busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'School')),
                const SizedBox(height: 12),
                TextFormField(controller: _bio, maxLength: 200, maxLines: 3,
                  enabled: !widget.controller.busy,
                  decoration: const InputDecoration(labelText: 'Bio')),
              ])),
              if (widget.controller.error != null) ErrorNotice(widget.controller.error!),
            ])),
            Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: PrimaryButton(label: 'Save changes', icon: Icons.check_rounded,
                busy: widget.controller.busy,
                onPressed: widget.controller.busy ? null : _save)),
          ]),
        ))),
      ),
    ),
  );
}
