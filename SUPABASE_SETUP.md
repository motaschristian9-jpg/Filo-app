# Supabase setup for Filo

Project: `pvcereixbqctjrxsalhd` (https://pvcereixbqctjrxsalhd.supabase.co).
Keep the organization on Free and Firebase on Spark. No billing change is needed
for this file integration. The user supplied a secret key in chat: revoke it in
Supabase Settings > API Keys. Its value was not used or stored in project files.

## Current state

- Public URL/publishable key are configured in
  `lib/materials/supabase_file_storage.dart`; these are client credentials only.
- Uploads, native offline downloads, and web opening now use Supabase signed URLs.
- Firebase still handles Google login and class/profile/material metadata.
- `supabase/functions/material-files/index.ts` verifies Firebase RS256 ID tokens
  (issuer/audience/expiry), then uses the caller's token with Firestore REST so
  existing Firestore membership rules still apply. Downloads accept class/material
  IDs, not arbitrary file paths. Uploads additionally require the class owner and
  an active class. The Firebase token is sent only to this project and Google.
- The Edge Function uses Supabase's built-in `SUPABASE_SERVICE_ROLE_KEY` environment
  variable on the server. It does not require the secret pasted into chat, a
  Firebase service account, or Supabase third-party login configuration.
- Bucket `class-materials` must be private, with a 25 MB file limit and
  application/octet-stream uploads. No blanket public/authenticated policies.
- The bucket SQL, Edge Function, and updated Firestore rules are prepared locally,
  but have NOT been applied/deployed. Uploads will not work until activation.
- `flutter pub get` completed. No tests, static analysis, builds, browser automation,
  or device checks were run.

## Activation

1. Revoke the exposed secret key using the Supabase dashboard. Do not paste its
   replacement, a service-role key, or the database password into chat.
2. In the VS Code terminal, run `npx supabase login` and complete browser login.
   Reply "logged in" so the agent can continue using CLI authorization.
3. With authorized CLI access, inspect the target project and existing bucket/
   policies before applying `supabase/migrations/202609300001_materials_bucket.sql`.
   The SQL may also be run directly through this project's dashboard SQL Editor.
   It creates or configures only the `class-materials` bucket.
4. Deploy only this function from the workspace:
   `npx supabase functions deploy material-files --project-ref pvcereixbqctjrxsalhd`.
   `supabase/config.toml` sets `verify_jwt = false` because this handler verifies
   Firebase tokens itself; the gateway's Supabase JWT check would reject them.
5. Deploy the corresponding Firestore rules with
   `firebase deploy --only firestore:rules --project filo-app-1a2a5` after reviewing
   current remote rules. The local rules validate immutable posts, owner-only
   enrollment creation, and the new per-upload UUID storage paths.
6. The user can restart the app and manually post/download a file. Keep server
   errors/signed URLs/tokens out of logs. A missing function or bucket is surfaced
   in the app as incomplete storage setup.

## Materials Phase 1 activation

The notification sender now has a prepared Supabase replacement, and students
query their own enrollment records directly instead of a mirrored user index.
See [MATERIALS_PHASE1_SETUP.md](MATERIALS_PHASE1_SETUP.md) for the queue migration,
private Firebase service-account configuration, worker deployment, Cron setup,
enrollment-field backfill, and Firestore rules/index deployment.

The previous Firebase Functions remain as reference source only and were never
deployed. Background push is still NOT live until the new backend is activated.
Posting now reserves a durable delivery job before writing the post, so both
`material-files` and `material-dispatch` must be set up for full file posting.
No login, remote configuration, migration, or deployment was performed in this
change; the user explicitly requested code and setup steps while CLI login is pending.

## File behavior and limits

- Upload grants use a unique UUID path and forbid overwrite. An interrupted
  upload/publish may leave an orphan file; automatic cleanup is not yet implemented.
- Firebase transactions retain the reserved post ID on retry. No successful file
  posts in the old Firebase bucket existed when migration was prepared (the bucket
  listing was empty). External legacy files would need a separate migration.
- Download links expire after 120 seconds; upload grants use Supabase's default
  signed-upload lifetime. Revocation stops new grants, not already issued grants
  or previously downloaded offline files.
- Downloads are bounded to 25 MB and retain the existing UID/class cache isolation,
  temporary-file writes, size validation, and retry-on-resume behavior.
- Native caches persist offline. Web files open using short-lived links online.
- Supabase Free has finite storage/transfer/function quotas and inactivity pausing;
  no claim of unlimited free operation is made. No backend account plan was changed.

References:
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets
- https://firebase.google.com/docs/firestore/use-rest-api
- https://firebase.google.com/docs/auth/admin/verify-id-tokens
## Activation status — 2026-10-03

- Supabase CLI login confirmed for project pvcereixbqctjrxsalhd.
- Deployed material-files and material-dispatch; created the private 25 MB bucket
  and server-only material_dispatch_jobs table/functions from the prepared SQL.
- No previous buckets or storage object policies existed before activation.
- Retrieved current Firestore rules to
  firebase/firestore.rules.before-materials-activation, then deployed the prepared
  materials rules. Firebase performed its required deployment compilation.
- Requested the studentId collection-group index through a scoped API update,
  preserving existing collection indexes. Index construction is asynchronous.
- FCM API is already enabled. The notification service account does not exist.
- Automatic approval review rejected creating the persistent service account
  filo-material-delivery@filo-app-1a2a5.iam.gserviceaccount.com, granting
  roles/firebasecloudmessaging.admin and roles/datastore.user, creating its key,
  and storing credentials in Supabase/Vault without explicit user approval.
  That command did not execute. Do not retry it without that approval.
- Still pending: approved notification credentials, worker secret/Vault setup,
  Cron extensions/schedule, and enrollment studentId backfill. The current app
  requires material-dispatch preparation before posting, so uploads in the newest
  code remain blocked until worker credentials are configured. Do not claim full
  posting or push is live. The previous missing material-files endpoint is fixed.
- No billing changes, sample uploads, app tests, Flutter analysis/builds, browser
  automation, or device checks were performed. Existing enrollment data untouched.
## Delivery activation completed — 2026-10-03

The user explicitly approved the dedicated Firebase service account, messaging
and Firestore permissions, and private key storage in Supabase. This supersedes
the earlier credential-approval blocker.

- Created filo-material-delivery@filo-app-1a2a5.iam.gserviceaccount.com with
  roles/firebasecloudmessaging.admin and roles/datastore.user. Existing IAM
  bindings were preserved. The first role update hit account propagation delay;
  retry succeeded before any key was generated.
- Installed FIREBASE_SERVICE_ACCOUNT_JSON and MATERIAL_WORKER_SECRET in Supabase
  Edge Function secrets. Stored the matching worker secret in Supabase Vault.
  Generated credential values were not printed or committed; temporary local
  credential files were removed after installation.
- Enabled pg_cron and pg_net and activated the filo-material-delivery schedule.
  Deployment metadata confirms both required secret names and the active job.
- Enrollment discovery index is READY. The scoped enrollment-field migration
  completed via Firestore REST with update-time preconditions; zero records
  required updates. The SDK approach rejected CLI credentials without mutations.
- material-files, material-dispatch, the private bucket, queue SQL, and Firestore
  rules were already deployed in the preceding turn. Backend setup is now active.
- No sample uploads or notification sends, app tests, Flutter analysis/builds,
  browser automation, or device checks were run. End-to-end upload and notification
  behavior remains for the user's manual review. No billing settings changed.

Next manual step: retry the image upload in the app. Report the exact new message
if any; do not assume the old missing-function or missing-secret blocker remains.