import 'package:filo/main.dart';
import 'package:filo/onboarding/onboarding_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryRepository implements OnboardingRepository {
  bool seen = false, failSave = false, cancelSignIn = false;
  FiloUser? user;
  LearnerProfile? profile;
  @override
  Future<bool> hasSeenIntro() async => seen;
  @override
  Future<void> markIntroSeen() async {
    seen = true;
  }

  @override
  Future<FiloUser?> currentUser() async => user;
  @override
  Future<FiloUser?> signIn() async {
    if (cancelSignIn) return null;
    return user = const FiloUser(
      uid: 'test-user',
      email: 'learner@example.com',
      name: 'Alex',
    );
  }

  @override
  Future<void> signOut() async {
    user = null;
  }

  @override
  Future<LearnerProfile?> loadProfile(String uid) async => profile;
  @override
  Future<void> saveProfile(String uid, LearnerProfile next) async {
    if (failSave) throw Exception('Offline');
    profile = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
    await loader.load();
  });
  test(
    'new users resume the unfinished step and completed users bypass setup',
    () async {
      final repository = MemoryRepository();
      final controller = OnboardingController(repository);
      await controller.start();
      expect(controller.stage, OnboardingStage.intro);
      await controller.finishIntro();
      await controller.signIn();
      expect(controller.stage, OnboardingStage.role);
      await controller.chooseRole('student');
      final resumed = OnboardingController(repository);
      await resumed.start();
      expect(resumed.stage, OnboardingStage.profile);
      await resumed.completeProfile(
        const LearnerProfile(role: 'student', name: 'Alex', complete: true),
      );
      final returning = OnboardingController(repository);
      await returning.start();
      expect(returning.stage, OnboardingStage.home);
      await returning.signOut();
      await returning.start();
      expect(returning.stage, OnboardingStage.login);
      controller.dispose();
      resumed.dispose();
      returning.dispose();
    },
  );

  test(
    'failed saves retain the step and cancellation does not create an account',
    () async {
      final repository = MemoryRepository()
        ..seen = true
        ..cancelSignIn = true;
      final controller = OnboardingController(repository);
      await controller.start();
      await controller.signIn();
      expect(controller.stage, OnboardingStage.login);
      expect(controller.user, isNull);
      repository.cancelSignIn = false;
      await controller.signIn();
      repository.failSave = true;
      await controller.chooseRole('instructor');
      expect(controller.stage, OnboardingStage.role);
      expect(controller.error, isNotNull);
      expect(controller.profile, isNull);
      repository.failSave = false;
      await controller.chooseRole('instructor');
      repository.failSave = true;
      await controller.completeProfile(
        const LearnerProfile(role: 'instructor', name: 'Alex', complete: true),
      );
      expect(controller.stage, OnboardingStage.profile);
      expect(controller.profile!.complete, isFalse);
      controller.dispose();
    },
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void configure(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
  }

  testWidgets(
    'mobile onboarding completes with Google, role, and valid profile',
    (tester) async {
      configure(tester, const Size(390, 844));
      final repository = MemoryRepository();
      await tester.pumpWidget(FiloApp(repository: repository));
      await tester.pumpAndSettle();
      expect(find.text('Learning, together.'), findsOneWidget);
      await tapVisible(tester, find.text('Next'));
      await tapVisible(tester, find.text('Next'));
      await tapVisible(tester, find.text('Get started'));
      await tapVisible(tester, find.text('Continue with Google'));
      final continueButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(continueButton.onPressed, isNull);
      await tapVisible(tester, find.text('I am a student'));
      await tapVisible(tester, find.text('Continue'));
      await tester.enterText(find.byKey(const Key('profile-name')), '   ');
      await tapVisible(tester, find.text('All set!'));
      expect(find.text('Please enter your display name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Alex Rivera',
      );
      await tapVisible(tester, find.text('All set!'));
      expect(repository.profile!.complete, isTrue);
      await tapVisible(tester, find.text('Let\'s go'));
      expect(find.text('Hello, Alex.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact and enlarged text layouts remain scrollable without overflow',
    (tester) async {
      configure(tester, const Size(320, 640));
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = MemoryRepository();
      await tester.pumpWidget(FiloApp(repository: repository));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Skip intro'));
      await tapVisible(tester, find.text('Continue with Google'));
      await tapVisible(tester, find.text('I am an instructor'));
      await tapVisible(tester, find.text('Continue'));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'preview replays every step without changing the signed-in account',
    () async {
      final repository = MemoryRepository()..seen = true;
      await repository.signIn();
      const original = LearnerProfile(
        role: 'student',
        name: 'Alex',
        complete: true,
      );
      repository.profile = original;
      final controller = OnboardingController(repository);
      await controller.start();
      final account = repository.user;
      controller.previewOnboarding();
      expect(controller.stage, OnboardingStage.intro);
      await controller.finishIntro();
      expect(controller.stage, OnboardingStage.login);
      await controller.signIn();
      expect(controller.stage, OnboardingStage.role);
      await controller.chooseRole('instructor');
      expect(controller.stage, OnboardingStage.profile);
      await controller.completeProfile(
        const LearnerProfile(
          role: 'instructor',
          name: 'Preview',
          complete: true,
        ),
      );
      expect(controller.stage, OnboardingStage.welcome);
      controller.goHome();
      expect(controller.profile, same(original));
      expect(repository.profile, same(original));
      expect(repository.user, same(account));
      expect(controller.isPreview, isFalse);
      controller.previewOnboarding();
      await controller.signOut();
      expect(controller.stage, OnboardingStage.home);
      expect(repository.user, same(account));
      expect(repository.profile, same(original));
      controller.dispose();
    },
  );

  testWidgets('desktop intro and returning instructor dashboard render', (
    tester,
  ) async {
    configure(tester, const Size(1280, 900));
    final repository = MemoryRepository();
    await tester.pumpWidget(FiloApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Learning, together.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repository.user = const FiloUser(
      uid: 'test-user',
      email: 'teacher@example.com',
      name: 'Sam',
    );
    repository.profile = const LearnerProfile(
      role: 'instructor',
      name: 'Sam',
      complete: true,
    );
    await tester.pumpWidget(FiloApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('YOUR TEACHING SPACE'), findsOneWidget);
    expect(find.text('A place for your first class'), findsOneWidget);
    await tapVisible(tester, find.text('Preview onboarding'));
    expect(find.text('Learning, together.'), findsOneWidget);
    expect(find.textContaining('Nothing is saved'), findsNothing);
    expect(find.text('Exit'), findsNothing);
    expect(find.text('Exit preview'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Hello, Sam.'), findsOneWidget);
    expect(repository.profile!.role, 'instructor');
    expect(tester.takeException(), isNull);
  });
}
