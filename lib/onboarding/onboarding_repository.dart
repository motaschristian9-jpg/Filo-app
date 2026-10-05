import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FiloUser {
  const FiloUser({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
  });
  final String uid, email, name;
  final String? photoUrl;
}

class LearnerProfile {
  const LearnerProfile({
    required this.role,
    required this.name,
    this.school = '',
    this.bio = '',
    this.avatar = -1,
    this.complete = false,
    this.roleLocked = false,
    String? photoUrl,
  }) : _photoUrl = photoUrl;
  final String? _photoUrl;
  String? get photoUrl => _photoUrl;
  final String role, name, school, bio;
  final int avatar;
  final bool complete, roleLocked;
  Map<String, dynamic> toMap() => {
    'role': role,
    'name': name,
    'school': school,
    'bio': bio,
    'avatar': avatar,
    'complete': complete,
    if (photoUrl != null) 'photoUrl': photoUrl,
  };
  factory LearnerProfile.fromMap(Map<String, dynamic> data) => LearnerProfile(
    role: data['role'] as String,
    name: data['name'] as String? ?? data['displayName'] as String? ?? '',
    school: data['school'] as String? ?? '',
    bio: data['bio'] as String? ?? '',
    avatar: data['avatar'] as int? ?? -1,
    complete: data['complete'] == true,
    photoUrl: data['photoUrl'] as String?,
  );
}

abstract class OnboardingRepository {
  Future<bool> hasSeenIntro();
  Future<void> markIntroSeen();
  Future<FiloUser?> currentUser();
  Future<FiloUser?> signIn();
  Future<void> signOut();
  Future<LearnerProfile?> loadProfile(String uid);
  Future<void> saveProfile(String uid, LearnerProfile profile);
}

class FirebaseOnboardingRepository implements OnboardingRepository {
  final _preferences = SharedPreferencesAsync();
  Future<void>? _googleInitialization;
  @override
  Future<bool> hasSeenIntro() async =>
      await _preferences.getBool('filo.intro.v1') ?? false;
  @override
  Future<void> markIntroSeen() => _preferences.setBool('filo.intro.v1', true);
  FiloUser? _map(User? user) => user == null
      ? null
      : FiloUser(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
          photoUrl: user.photoURL,
        );
  @override
  Future<FiloUser?> currentUser() async =>
      _map(await FirebaseAuth.instance.authStateChanges().first);
  @override
  Future<FiloUser?> signIn() async {
    if (kIsWeb) {
      return _map(
        (await FirebaseAuth.instance.signInWithPopup(
          GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        )).user,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      throw const OnboardingException(
        'Please use Filo in your browser to sign in on this device.',
      );
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize();
    await _googleInitialization;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      return _map(
        (await FirebaseAuth.instance.signInWithCredential(credential)).user,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    if (_googleInitialization != null) {
      // Firebase is already signed out; provider cleanup must not keep the UI
      // on the previous account if the Google plugin fails.
      try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    }
  }

  @override
  Future<LearnerProfile?> loadProfile(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (snapshot.exists) {
      final data = snapshot.data()!;
      if (data['role'] == 'student' || data['role'] == 'instructor') {
        // Other users cannot read this account's Firebase Auth photo directly.
        // Backfill the shared profile for accounts saved before photoUrl existed.
        final account = FirebaseAuth.instance.currentUser;
        final photoUrl = account?.photoURL;
        if (account?.uid == uid && photoUrl != null && photoUrl.isNotEmpty &&
            data['photoUrl'] == null) {
          try {
            await snapshot.reference.set({'photoUrl': photoUrl}, SetOptions(merge: true));
          } catch (_) {
            // A photo sync failure must not prevent opening an existing account.
          }
        }
        final profile = LearnerProfile.fromMap(data);
        return LearnerProfile(
          role: profile.role,
          name: profile.name,
          school: profile.school,
          bio: profile.bio,
          avatar: profile.avatar,
          complete: profile.complete,
          roleLocked: true,
          photoUrl: profile.photoUrl ?? photoUrl,
        );
      }
    }
    final draft = await _preferences.getString('filo.profileDraft.$uid');
    return draft == null
        ? null
        : LearnerProfile.fromMap(jsonDecode(draft) as Map<String, dynamic>);
  }

  @override
  Future<void> saveProfile(String uid, LearnerProfile profile) async {
    if (!profile.complete) {
      await _preferences.setString(
        'filo.profileDraft.$uid',
        jsonEncode(profile.toMap()),
      );
      return;
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      ...profile.toMap(),
      if (FirebaseAuth.instance.currentUser?.uid == uid &&
          FirebaseAuth.instance.currentUser?.photoURL != null && profile.photoUrl == null)
        'photoUrl': FirebaseAuth.instance.currentUser!.photoURL,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _preferences.remove('filo.profileDraft.$uid');
  }
}

class OnboardingException implements Exception {
  const OnboardingException(this.message);
  final String message;
}

enum OnboardingStage { loading, intro, login, role, profile, welcome, home }

class OnboardingController extends ChangeNotifier {
  OnboardingController(this.repository);
  final OnboardingRepository repository;
  OnboardingStage stage = OnboardingStage.loading;
  FiloUser? user;
  LearnerProfile? profile;
  bool busy = false;
  bool isPreview = false;
  LearnerProfile? _savedProfile;
  String? error;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (exception) {
      error = switch (exception) {
        OnboardingException e => e.message,
        FirebaseAuthException e
            when [
              'popup-closed-by-user',
              'cancelled-popup-request',
            ].contains(e.code) =>
          null,
        FirebaseAuthException e when e.code == 'network-request-failed' =>
          'Could not connect. Check your connection and try again.',
        FirebaseAuthException e
            when [
              'operation-not-allowed',
              'unauthorized-domain',
              'configuration-not-found',
            ].contains(e.code) =>
          'Google sign-in is not available yet. Please try again later.',
        FirebaseException e when e.code == 'permission-denied' => 'We could not access your profile. Please try again or sign in again.',
        _ => 'Something interrupted that step. Please try again. Your saved progress is safe.',
      };
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> start() => _perform(() async {
    user = await repository.currentUser();
    if (user != null) {
      await _routeUser();
    } else {
      stage = await repository.hasSeenIntro()
          ? OnboardingStage.login
          : OnboardingStage.intro;
    }
  });
  Future<void> finishIntro() => _perform(() async {
    if (!isPreview) await repository.markIntroSeen();
    stage = OnboardingStage.login;
  });
  Future<void> signIn() => _perform(() async {
    if (isPreview) {
      stage = OnboardingStage.role;
      return;
    }
    user = await repository.signIn();
    if (user != null) {
      await _routeUser();
    }
  });
  Future<void> _routeUser() async {
    profile = await repository.loadProfile(user!.uid);
    stage = profile == null
        ? OnboardingStage.role
        : profile!.complete
        ? OnboardingStage.home
        : OnboardingStage.profile;
  }

  Future<void> chooseRole(String role) => _perform(() async {
    final next = LearnerProfile(
      role: role,
      name: profile?.name ?? user!.name,
      school: profile?.school ?? '',
      bio: profile?.bio ?? '',
      avatar: profile?.avatar ?? -1,
      photoUrl: profile?.photoUrl,
    );
    if (!isPreview) await repository.saveProfile(user!.uid, next);
    profile = next;
    stage = OnboardingStage.profile;
  });
  Future<void> completeProfile(LearnerProfile next) => _perform(() async {
    if (!isPreview) await repository.saveProfile(user!.uid, next);
    profile = next;
    stage = OnboardingStage.welcome;
  });
  Future<void> updateProfile({required String name, required String school,
    required String bio, required int avatar, String? photoUrl}) => _perform(() async {
    if (stage != OnboardingStage.home || user == null || profile == null || isPreview) return;
    final next = LearnerProfile(
      role: profile!.role,
      name: name.trim(),
      school: school.trim(),
      bio: bio.trim(),
      avatar: avatar,
      photoUrl: photoUrl ?? profile!.photoUrl ?? user!.photoUrl,
      complete: true,
      roleLocked: profile!.roleLocked,
    );
    if (next.name.isEmpty) throw const OnboardingException('Add your name.');
    await repository.saveProfile(user!.uid, next);
    profile = next;
  });
  void editRole() {
    if (busy) return;
    error = null;
    stage = OnboardingStage.role;
    notifyListeners();
  }

  void goHome() {
    if (isPreview) {
      exitPreview();
      return;
    }
    stage = OnboardingStage.home;
    notifyListeners();
  }

  // Temporary UI review mode: never writes to Firebase or local preferences.
  void previewOnboarding() {
    if (busy || stage != OnboardingStage.home || isPreview) return;
    _savedProfile = profile;
    profile = null;
    isPreview = true;
    error = null;
    stage = OnboardingStage.intro;
    notifyListeners();
  }

  void exitPreview() {
    if (!isPreview) return;
    profile = _savedProfile;
    _savedProfile = null;
    isPreview = false;
    error = null;
    stage = OnboardingStage.home;
    notifyListeners();
  }

  void replayIntro() {
    error = null;
    stage = OnboardingStage.intro;
    notifyListeners();
  }

  Future<void> signOut() => _perform(() async {
    if (isPreview) {
      exitPreview();
      return;
    }
    await repository.signOut();
    user = null;
    profile = null;
    stage = OnboardingStage.login;
  });
}
