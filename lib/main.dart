import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'onboarding/design.dart';
import 'onboarding/onboarding_repository.dart';
import 'onboarding/screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(FiloApp(repository: FirebaseOnboardingRepository()));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: filoTheme(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Filo could not start. Please check your connection and reopen the app.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FiloApp extends StatelessWidget {
  const FiloApp({super.key, required this.repository});
  final OnboardingRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Filo - A little more learning',
    debugShowCheckedModeBanner: false,
    theme: filoTheme(),
    home: OnboardingFlow(repository: repository),
  );
}

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.repository});
  final OnboardingRepository repository;
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final OnboardingController controller = OnboardingController(
    widget.repository,
  )..start();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final screen = switch (controller.stage) {
        OnboardingStage.loading => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Brand(),
                    const SizedBox(height: 24),
                    if (controller.error == null)
                      const FiloSkeleton(layout: SkeletonLayout.rows,
                        scrollable: false, padding: EdgeInsets.zero)
                    else ...[
                      ErrorNotice(controller.error!),
                      PrimaryButton(
                        label: 'Try again',
                        onPressed: controller.start,
                      ),
                      if (controller.user != null)
                        TextButton(
                          onPressed: controller.signOut,
                          child: const Text('Sign out'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        OnboardingStage.intro => IntroScreen(controller: controller),
        OnboardingStage.login => LoginScreen(controller: controller),
        OnboardingStage.role => RoleScreen(controller: controller),
        OnboardingStage.profile => ProfileScreen(controller: controller),
        OnboardingStage.welcome => WelcomeScreen(controller: controller),
        OnboardingStage.home => HomeScreen(controller: controller),
      };
      final flow = AnimatedSwitcher(
        transitionBuilder: (child, animation) {
          final stage = (child.key! as ValueKey<OnboardingStage>).value;
          final offset = switch (stage) {
            OnboardingStage.intro => const Offset(-.08, 0),
            OnboardingStage.login => const Offset(.12, 0),
            _ => Offset.zero,
          };
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: offset, end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [
            for (final child in previous)
              ExcludeSemantics(child: IgnorePointer(child: child)),
            if (current != null) current,
          ],
        ),
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context)
              ? 0
              : controller.stage == OnboardingStage.login || controller.stage == OnboardingStage.intro
                  ? 480
                  : 260,
        ),
        child: KeyedSubtree(key: ValueKey(controller.stage), child: screen),
      );
      return PopScope(
        canPop: !controller.isPreview,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && controller.isPreview) controller.exitPreview();
        },
        child: ColoredBox(color: cream, child: ClipRect(child: flow)),
      );
    },
  );
}
