# Filo Android tester releases

Implemented: manual GitHub Actions workflow .github/workflows/android-testers.yml.
It builds a signed universal release APK and distributes it to Firebase tester
group filo-members. It runs only from main, via Run workflow, not every push.
Flutter 3.47.6 matches the installed SDK; Java 17 matches Android configuration.
The committed Rive asset is bundled as-is; Rive CLI is not needed in CI.

No workflow was executed and no Flutter builds, tests or analysis were run.
GitHub credentials, Firebase fingerprints and tester configuration remain setup
steps. This is the initial distribution pipeline, without automatic quality gates.

## One-time setup

1. Complete ANDROID_SIGNING.md: back up signing files, add both fingerprints to
   Firebase, and replace android/app/google-services.json with the refreshed file.
2. Firebase console → App Distribution → Android app com.example.filo → Get started.
   Create a tester group with alias filo-members and add members' email addresses.
3. In Google Cloud IAM for project filo-app-1a2a5, create a dedicated service account
   (for example filo-distribution). Grant Firebase App Distribution Admin, not
   Owner/Editor. Create a JSON key for that account and keep the downloaded file
   outside the repository. This authenticates distribution, not the Flutter app.
   Guide: https://firebase.google.com/docs/app-distribution/authenticate-service-account
4. GitHub repository motaschristian9-jpg/Filo-app → Settings → Secrets and variables
   → Actions → New repository secret. Add these three secrets:

   | Name | Value |
   | --- | --- |
   | FILO_KEYSTORE_BASE64 | Base64 of the existing android/signing/filo-testers.jks |
   | FILO_KEY_PROPERTIES | Entire existing android/key.properties contents |
   | FIREBASE_SERVICE_ACCOUNT_JSON | Entire downloaded distribution service account JSON |

   To copy signing values without printing them, run these individually from the
   project terminal, saving each matching GitHub secret before copying the next:

   ```powershell
   .\scripts\copy-signing-secret.ps1 -Secret Keystore
   .\scripts\copy-signing-secret.ps1 -Secret Properties
   ```

   Clear the clipboard afterward: `Set-Clipboard -Value ""`. Do not commit the
   service account JSON or signing files. Never paste their values into chat.
5. Commit and push the workflow/configuration/docs and refreshed Firebase config
   to main. Keep signing files excluded. Enable GitHub Actions if disabled.

## Publish a tester version

1. Push the changes you want members to test to main.
2. GitHub → Actions → Android tester release → Run workflow → branch main.
3. Enter short release notes describing changes and what to test, then run it.
4. The workflow assigns build number 1000 + its GitHub run number, resolves locked
   dependencies, builds an APK, saves a GitHub artifact for 14 days, then distributes
   it through the official Firebase CLI using Application Default Credentials.
5. Members accept the Firebase invitation, download/install the APK and report bugs
   with build number, device, reproduction steps and screenshots. Android may need
   permission to install apps from their browser/App Tester.

If distribution fails after the build, the APK artifact is still available in the
workflow run. Read the failed step; do not regenerate signing keys to retry. Reruns
keep the build number; start a new workflow run for a newer numbered build. Keep
this numbering scheme or migrate its offset upward if replacing the workflow.

Firebase App Distribution: https://firebase.google.com/docs/app-distribution/android/distribute-cli

## Scope and later improvements

- Uses the existing Firebase/Supabase backend. This is not a separate staging
  environment: members' normal activity writes to the current backend. Use test
  accounts/classes. Dashboard onboarding preview isolation remains unchanged.
- No database, Edge Function, Firebase rules or backend deployment in this workflow.
- No automated app checks yet, honoring current manual-testing preference. Add
  selected CI checks separately when requested, then gate releases on them.
- Later: staging backend, keyless Google authentication via Workload Identity
  Federation, pinned action commit hashes/tool versions, automatic release triggers,
  and iOS distribution if needed.
