# Filo

For project context, the onboarding diagram, and current user instructions, read
[HANDOFF.md](HANDOFF.md). The user currently handles testing manually; do not run
checks unless requested.

A Flutter mini LMS with an original, animated onboarding experience.

## Run

```sh
flutter pub get
flutter run -d chrome --web-port 54321
```

Use `localhost`, which is authorized for Google login in Firebase.
Firebase project: `filo-app-1a2a5`.

## Implemented

- Three swipeable introductions, Skip, and a persistent first-launch preference.
- Google-only authentication: Firebase popup on web and Google Sign-In on Android/iOS/macOS.
- Student/instructor selection, Google-prefilled profile, editable avatar, optional school and bio.
- Profile validation, saving/error feedback, returning-user routing, and sign-out.
- Locally saved role drafts resume on the same device. Completed profiles are stored in `users/{uid}` in Firestore and resume across devices.
- Existing user documents are merged, not replaced. Existing server-side role locks are respected.
- Original Flutter-drawn illustrations, bundled Nunito font, responsive layouts, and reduced-motion support.

The role-specific landing screens are onboarding destinations. Class creation,
class joining, resources, assessments, and AI study features are not implemented yet.

## Firebase and native setup

Google authentication and `localhost` were confirmed enabled in the existing project.
Existing Firestore security rules were inspected and preserved; no rules were deployed.
New users can change their draft role before completing their profile. Saved roles
are immutable under the project's existing rules.

This machine's Android debug SHA-1 is registered. Register your own development or
release signing fingerprints before testing with a different key, then refresh
`android/app/google-services.json`. Apple's client ID, URL callback, and macOS
network/keychain entitlements are configured. Apple builds require macOS/Xcode.
Windows native Google login is not implemented; use the web app on Windows.
Linux Firebase support is not configured.

## Verification

```sh
flutter analyze
flutter test
```

Tests cover both roles, completion/resume routing, cancelled sign-in, failed saves,
required-name validation, desktop, mobile, enlarged text, and reduced motion.
The OAuth provider is replaced with an in-memory repository in tests. A real
Google account login and native-device builds still need manual verification.

Reference: https://firebase.google.com/docs/auth/flutter/federated-auth
Apple setup: https://pub.dev/packages/google_sign_in_ios
