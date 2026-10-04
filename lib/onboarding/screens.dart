import 'package:flutter/material.dart';
import '../classes/instructor_dashboard.dart';
import '../materials/student_dashboard.dart';

import 'design.dart';
import 'illustrations.dart';
import 'onboarding_repository.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  int _page = 0;
  bool _changingPage = false;
  static const _titles = [
    'Learning, together.',
    'Small steps. Big wins.',
    'Stay curious.',
  ];
  static const _descriptions = [
    'Your classes and resources, all in one place.',
    'Share activities. See your progress.',
    'Ask AI. Explore your notes. Find answers.',
  ];
  void _changePage(int value) {
    if (_changingPage || value == _page || value < 0 || value > 2) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _page = value;
      _changingPage = !reduce;
    });
    if (!reduce) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _changingPage = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return FiloFrame(
      action: TextButton(
        onPressed: widget.controller.busy
            ? null
            : widget.controller.finishIntro,
        child: const Text(
          'Skip intro',
          style: TextStyle(color: muted, fontWeight: FontWeight.w700),
        ),
      ),
      art: LearningArt(scene: _page),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            if (widget.controller.error != null)
              ErrorNotice(widget.controller.error!),
            PrimaryButton(
              label: _page == 2 ? 'Get started' : 'Next',
              busy: widget.controller.busy,
              onPressed: () {
                if (_changingPage) return;
                if (_page == 2) {
                  widget.controller.finishIntro();
                } else {
                  _changePage(_page + 1);
                }
              },
            ),
        ],
      ),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0).abs() > 100) {
            _changePage(_page + (details.primaryVelocity! < 0 ? 1 : -1));
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!wide)
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .29).clamp(
                  170.0,
                  280.0,
                ),
                child: LearningArt(scene: _page),
              ),
            Row(
              children: List.generate(
                3,
                (index) => Semantics(
                  label: 'Introduction ${index + 1} of 3',
                  selected: index == _page,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _changePage(index),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: reduce ? 0 : 220),
                          height: 7,
                          width: index == _page ? 30 : 8,
                          decoration: BoxDecoration(
                            color: index == _page ? teal : line,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            LayoutBuilder(builder: (context, constraints) {
              final titleStyle = wide
                  ? Theme.of(context).textTheme.headlineLarge!
                  : Theme.of(context).textTheme.headlineMedium!;
              final bodyStyle = Theme.of(context).textTheme.bodyLarge!;
              double textHeight(String text, TextStyle style) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.localeOf(context),
                )..layout(maxWidth: constraints.maxWidth);
                final height = painter.height;
                painter.dispose();
                return height;
              }
              // Reserve the largest slide at the current width and font scale.
              double height = 0;
              for (var index = 0; index < _titles.length; index++) {
                final candidate = textHeight(_titles[index], titleStyle) + 16
                    + textHeight(_descriptions[index], bodyStyle);
                if (candidate > height) height = candidate;
              }
              return SizedBox(
                width: double.infinity,
                height: height.ceilToDouble() + 2,
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: reduce ? 0 : 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      for (final child in previous)
                        ExcludeSemantics(child: IgnorePointer(child: child)),
                      if (current != null) current,
                    ],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_page),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_titles[_page], style: titleStyle),
                      const SizedBox(height: 16),
                      Text(_descriptions[_page], style: bodyStyle),
                    ],
                  ),
                ),
              );
            }),

          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  Widget build(BuildContext context) => FiloFrame(
    action: TextButton(
      onPressed: controller.busy ? null : controller.replayIntro,
      child: const Text('About Filo'),
    ),
    art: const LearningArt(expression: MascotExpression.wink),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width < 850) const LearningArt(expression: MascotExpression.wink),
        Text(
          'Hello, curious mind.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text('Your next chapter starts here.'),
        const SizedBox(height: 32),
        if (controller.error != null) ErrorNotice(controller.error!),
        PrimaryButton(
          label: 'Continue with Google',
          google: true,
          busy: controller.busy,
          onPressed: controller.signIn,
        ),
      ],
    ),
  );
}

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  String? _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.controller.profile?.role;
  }

  @override
  Widget build(BuildContext context) => FiloFrame(
    action: widget.controller.isPreview ? null : TextButton(
      onPressed: widget.controller.busy ? null : widget.controller.signOut,
      child: const Text('Sign out'),
    ),
    art: LearningArt(scene: _selected == 'instructor' ? 1 : 0),
    footer: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.controller.error != null)
          ErrorNotice(widget.controller.error!),
        PrimaryButton(
          label: 'Continue',
          busy: widget.controller.busy,
          onPressed: _selected == null
              ? null
              : () => widget.controller.chooseRole(_selected!),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupProgress(1),
        const SizedBox(height: 32),
        Text(
          'I am here to...',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 28),
        _roleCard(
          'student',
          'Learn',
          'I am a student',
          Icons.school_rounded,
          const Color(0xFFDCD8F3),
        ),
        const SizedBox(height: 16),
        _roleCard(
          'instructor',
          'Teach',
          'I am an instructor',
          Icons.auto_stories_rounded,
          const Color(0xFFF5D4B9),
        ),

      ],
    ),
  );
  Widget _roleCard(
    String role,
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    final selected = _selected == role;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduce ? 0 : 200),
        decoration: BoxDecoration(
          color: selected ? mint : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? teal : line, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.controller.busy
              ? null
              : () => setState(() => _selected = role),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: selected && !reduce ? -.025 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Container(
                    width: 57,
                    height: 64,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(icon, color: ink, size: 30),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 9),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? teal : line,
                  size: 23,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
    context: context,
    showDragHandle: true,
    backgroundColor: cream,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pick your look',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final choice in [
                  if (widget.controller.user!.photoUrl != null) -1,
                  0,
                  1,
                  2,
                  3,
                ])
                  Semantics(
                    button: true,
                    selected: choice == _avatar,
                    label: choice == -1
                        ? 'Google photo'
                        : 'Avatar ${choice + 1}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () {
                        setState(() => _avatar = choice);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: choice == _avatar
                                ? teal
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ProfileAvatar(
                          avatar: choice,
                          photoUrl: widget.controller.user!.photoUrl,
                          size: 58,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FiloFrame(
    back: widget.controller.busy || widget.controller.profile!.roleLocked
        ? null
        : widget.controller.editRole,
    action: widget.controller.isPreview ? null : TextButton(
      onPressed: widget.controller.busy ? null : widget.controller.signOut,
      child: const Text('Sign out'),
    ),
    art: const LearningArt(scene: 2),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupProgress(2),
          const SizedBox(height: 28),
          Text(
            'Let\'s make it yours.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ProfileAvatar(
                avatar: _avatar,
                photoUrl: widget.controller.user!.photoUrl,
                size: 74,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: widget.controller.busy ? null : _chooseAvatar,
                      child: const Text('Change avatar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _label('Display name'),
          TextFormField(
            key: const Key('profile-name'),
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Your name',
              counterText: '',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Please enter your display name.'
                : null,
          ),
          const SizedBox(height: 18),
          _label('Google email'),
          TextFormField(
            initialValue: widget.controller.user!.email,
            readOnly: true,
            decoration: const InputDecoration(
              suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
            ),
            style: const TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 18),
          _label('School', optional: true),
          TextFormField(
            controller: _school,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'School name',
              counterText: '',
            ),
          ),
          const SizedBox(height: 18),
          _label('Bio', optional: true),
          TextFormField(
            controller: _bio,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'A little about you'),
          ),
          const SizedBox(height: 20),
          if (widget.controller.error != null)
            ErrorNotice(widget.controller.error!),
          PrimaryButton(
            label: 'All set!',
            busy: widget.controller.busy,
            icon: Icons.check_rounded,
            onPressed: () {
              if (_form.currentState!.validate()) {
                FocusScope.of(context).unfocus();
                widget.controller.completeProfile(
                  LearnerProfile(
                    role: widget.controller.profile!.role,
                    name: _name.text.trim(),
                    school: _school.text.trim(),
                    bio: _bio.text.trim(),
                    avatar: _avatar,
                    complete: true,
                  ),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
  Widget _label(String title, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        if (optional)
          const Text(
            '  (optional)',
            style: TextStyle(fontSize: 12, color: muted),
          ),
      ],
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  Widget build(BuildContext context) => FiloFrame(
    art: const LearningArt(expression: MascotExpression.proud),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width < 850) const LearningArt(expression: MascotExpression.proud),
        Text(
          'You are in, ${controller.profile!.name.split(' ').first}!',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text('Let the learning begin.'),
        const SizedBox(height: 32),
        PrimaryButton(label: 'Let\'s go', onPressed: controller.goHome),
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final OnboardingController controller;
  @override
  Widget build(BuildContext context) => controller.profile!.role == 'instructor'
      ? InstructorDashboard(controller: controller)
      : StudentDashboard(controller: controller);
}