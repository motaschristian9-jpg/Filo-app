   # Android signing

Release APKs now use a dedicated local tester signing key. Debug builds retain
the normal debug key. No APK has been built or tested as part of this setup.

Local private files (excluded from Git by android/.gitignore):

- android/signing/filo-testers.jks: RSA signing key, alias filo-testers.
- android/key.properties: generated password and relative keystore path.

Back up BOTH files securely outside the repository. Never regenerate or replace
the key for updates to this tester app. Do not paste passwords or key files into
chat. GitHub Actions receives copies through secrets; see CI_CD.md.

## Register the certificate with Firebase

1. Open Firebase project filo-app-1a2a5.
2. Project settings → General → Your apps → Android app com.example.filo.
3. Add each fingerprint below separately, retaining existing debug fingerprints.
4. Download the refreshed google-services.json and replace
   android/app/google-services.json before the first tester release.

```text
SHA-1: B5:06:77:83:53:59:3C:58:57:5A:1D:C3:BD:D3:82:C5:08:EC:44:54
SHA-256: F7:60:24:3A:6E:F5:6A:82:2C:A4:4B:24:7B:E5:59:7E:FF:F6:57:98:30:85:A7:B1:AD:FD:B7:6F:59:DA:F2:43
```

These fingerprints are public certificate identifiers, not passwords.
Google sign-in setup: https://firebase.google.com/docs/auth/android/google-signin
Flutter signing guide: https://docs.flutter.dev/deployment/android

Phones with the old debug-signed app must uninstall that copy once before
installing the first tester-signed APK. This clears local app data. Future tester
updates can install over it when signed by this same key with a newer build number.

This is the APK tester signing identity. Future Google Play App Signing uses
its own distribution certificate, whose fingerprints must also be registered.
