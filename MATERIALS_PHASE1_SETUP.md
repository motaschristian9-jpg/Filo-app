# Phase 1 materials activation

Activation started on 2026-10-03; see current status below. No app tests were run. Keep Firebase
on Spark and Supabase on Free. Firebase handles login, class membership and post
metadata; Supabase handles private file storage and the notification worker.

## What the app does

- Instructors post a file (up to 25 MB), HTTPS link, or announcement within a class.
- Announcements can attach one optional file up to 25 MB. The original post appears
  in Stream and its attachment in Files, using the same storage object and preview.
- Students discover their classes from enrollment records. Files download across
  all enrolled classes when the native app opens, resumes, or receives new posts.
- Native Firestore caching retains announcement/link metadata. Downloaded files
  are stored separately per account and class. External links still need internet.
- Android notifications use FCM. A delivery job is reserved before the post is
  committed. Publishing wakes the worker immediately; Cron recovers interrupted
  requests. Delivery depends on notification permission, OS/network conditions,
  service availability and quotas; it is not a guaranteed instantaneous message.
- No AI classification. Each post retains the class chosen when it was created.
- Student class joining remains a separate feature. Existing students must have
  real enrollment documents; this work does not create sample enrollments.

## 1. Sign in and activate file storage

Run `npx supabase login` locally, then follow the bucket and `material-files`
instructions in [SUPABASE_SETUP.md](SUPABASE_SETUP.md). Do not paste secrets into
chat or commit them. The earlier exposed Supabase secret must be revoked.

## 2. Configure the notification worker privately

In Google Cloud for `filo-app-1a2a5`, enable the Firebase Cloud Messaging API.
Create a dedicated service account with Firebase Cloud Messaging API Admin
(`roles/firebasecloudmessaging.admin`) and Cloud Datastore User
(`roles/datastore.user`). The latter permits enrollment/device reads and removal
of expired device registrations. Do not grant project Owner or Editor.

Create its JSON credential and put the complete JSON in the Supabase Edge
Function secret `FIREBASE_SERVICE_ACCOUNT_JSON`. Do this privately in the
Supabase dashboard, not in Flutter source, a committed file, or chat.

Generate a random secret of at least 32 bytes and save it in both places:

- Edge Function secret: `MATERIAL_WORKER_SECRET`.
- Supabase Vault secret: `filo_material_worker_secret`.

Keep these values identical. The worker checks this secret for scheduled calls;
normal app calls must carry a verified Firebase ID token and class ownership.

## 3. Apply the queue migration and deploy

After reviewing the target project, run the SQL in
`supabase/migrations/202610030001_material_dispatch.sql` using its SQL Editor.
The queue has RLS enabled, no client policies, and only service-role access.

Deploy from the workspace:

```powershell
npx supabase functions deploy material-dispatch --project-ref pvcereixbqctjrxsalhd
```

`supabase/config.toml` disables gateway JWT verification for this function
because it verifies Firebase tokens itself. Do not remove the handler's checks.

Enable Supabase Cron (`pg_cron`) and `pg_net`, then run
`supabase/material_dispatch_schedule.sql`. It invokes the worker each minute
only while eligible unfinished jobs exist. The named Cron job can be replaced by
rerunning the script. No Firebase Functions deployment or Blaze upgrade is used.

## 4. Activate direct class discovery

Existing enrollment documents must have `studentId` equal to their document ID:
`classes/{classId}/enrollments/{studentUid}`. Future trusted enrollment writers
must include that field; the updated client rules enforce it for instructor writes.

With authorized Application Default Credentials, run the one-time migration:

```powershell
node firebase/functions/backfill-student-ids.js --project=filo-app-1a2a5
```

This uses the existing `firebase/functions` Node dependencies. It updates only
the `studentId` field on existing enrollment documents, preserving other fields
and never recreating a concurrently removed enrollment. It is safe to retry.
Do not run the obsolete user-index backfill for this implementation.

Review remote rules and indexes before deployment. Preserve unrelated existing
indexes if Firebase proposes removing them. Deploy the prepared rules and the
`enrollments.studentId` collection-group index:

```powershell
firebase deploy --only firestore --project filo-app-1a2a5
```

Wait until the index is ready. Students query only their own `studentId`; class
documents and materials still require live membership. No shared roster is
exposed by the new collection-group list rule.

## Manual review after activation

Restart the app with the native dependencies installed. With a real enrolled
student, post each of the three kinds from the instructor account. Confirm an
Android notification with the student app in the background; tapping it opens
the matching class. Open/resume the student app and let file downloads finish,
then open those files and announcements offline. Confirm classes remain separate.

Retrying a post reuses its ID and delivery job. If the instructor closes the app
after committing, Cron should recover notification delivery. Check membership
removal and account switching using your own accounts. No automatic checks were
run and no sample data was created by the agent.

## Limits and operations

- Native offline files and Android push are supported. Web files open online;
  Apple/web push setup is outside this implementation.
- Worker jobs use leases, paged recipient/device reads, and retry backoff. Generic
  lock-screen text avoids displaying material titles. Membership and device
  registration are reread immediately before sending.
- A process failure after FCM accepts a message but before the cursor is saved can
  repeat a push. Stable Android notification tags replace the visible notification.
- Jobs expire after 24 hours without another prepare request. Unpublished drafts
  cannot send notifications. Published posts remain available even if push expires.
- Jobs keep completion records to deduplicate retries. Operators should monitor
  unfinished jobs, expiry, function failures, storage usage, and free-plan quotas.
- Posting now requires the dispatch endpoint to accept its durable job first.
  Incomplete backend setup produces a retryable delivery error before posting.
- No storage eviction limit or orphan upload cleanup is implemented. Offline
  copies cannot be recalled until the device reconnects and learns of removal.

References: [FCM HTTP v1 authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[Supabase background tasks](https://supabase.com/docs/guides/functions/background-tasks),
[scheduled Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions).

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
