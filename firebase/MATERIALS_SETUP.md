# Materials: setup and manual review

The Flutter UI, offline queue, Storage rules, Firestore rules, and notification
functions are implemented locally. Backend deployment is required before use.
No tests, builds, analysis, browser automation, or device checks were run.

## Enable the backend

1. Enable Cloud Storage for `filo-app-1a2a5`. Confirm its bucket matches
   `lib/firebase_options.dart`; enable billing if Firebase requires it. Cloud
   Functions deployment also needs an eligible billing plan.
2. From the project root run `flutter pub get`. In `firebase/functions`, run
   `npm install --ignore-scripts` using Node 22.
3. Deploy from the root with
   `firebase deploy --only firestore:rules,storage,functions:materials --project filo-app-1a2a5`.
   Storage rules use Firestore membership reads; grant the cross-service access
   when the Firebase CLI prompts. Merge with any existing remote Storage rules
   before deploying if this bucket already serves other features.
4. Existing enrollments need their private class indexes populated once. With
   Application Default Credentials authorized for this project, run from
   `firebase/functions`:
   `npm run backfill -- --project=filo-app-1a2a5`.
   This writes only `users/{uid}/classes/{classId}` and sends no notifications.
5. Install a fresh Android build (new native plugins require a full rebuild),
   sign in as a student, and allow notifications. If permission was permanently
   denied, enable it in Android app settings and tap Enable notifications again.

Student joining remains a separate feature. Use existing enrollment documents
or instructor/admin-managed enrollment; the materials module does not redeem
class codes. Enrollment creation is now instructor/backend-only in the local
rules, closing the previous self-enrollment bypass before file access is enabled.

## Behavior and limits

- Instructor: open class > Materials > Post > File, Link, or Announcement.
- Posts are immutable in Phase 1; archived classes reject new posts. One reserved
  post ID survives retries within a form. A submitted form locks its payload to
  avoid ambiguous retries. Posting requires internet. Closing a failed form and
  creating a new one starts a new post, so first check the class feed.
- Uploads are limited to 25 MB. Files upload to a private Storage path before
  the Firestore post is committed. A failed/abandoned publish can leave an
  unpublished object; no automatic orphan cleanup is deployed in this phase.
- The student dashboard discovers all enrolled classes through server-managed
  per-user indexes. Subscriptions keep class materials current. Opening or
  resuming the app drains a sequential download queue across every class;
  downloads do not require opening each class. Failed files retry on resume or
  using Retry downloads. No background file downloads are promised.
- Native files are stored by UID/class/material in application support storage,
  written via a temporary file, and checked against their expected length.
  Filenames cannot control cache paths. A compatible document viewer is needed.
- Announcements and link metadata use native Firestore offline persistence.
  Link destinations still need internet. Offline data must have synced once.
- Account caches are isolated. Membership removal purges that class's files once
  the device receives the update; offline revocation cannot retract files already
  downloaded. This is offline access, not DRM. No cache-size eviction policy yet.
- Android push registration, foreground banner, background OS notification, and
  notification tap routing are wired. Android delivery depends on permission,
  connectivity, OS restrictions, and FCM; it cannot guarantee instant arrival.
  Outbox records deduplicate fanout, with stable Android tags for retries. As with
  all at-least-once triggers, a crash after sending can still repeat a notification.
- Push notifications are Android-only in this phase. Apple APNs setup and web
  service worker/VAPID setup are not added. Web files open online; persistent
  browser file downloads and browser offline metadata are not implemented.
- The temporary onboarding preview stays available on both dashboards. It does
  not create posts, register a simulated account, or modify enrollment/profile data.

## Manual scenarios

Use an instructor and an enrolled student on separate devices/accounts:

1. Post each type. Confirm each appears only in its assigned class.
2. Background/close the student app, post a file, and tap the notification.
   Confirm the correct class opens. Also post while the app is foregrounded.
3. Open the student app at its dashboard. Wait for downloads, disable internet,
   and open the downloaded file and announcement. A link destination needs internet.
4. Interrupt a download, reconnect, and resume/retry. Confirm no partial file is
   shown as available offline. Try a file larger than 25 MB.
5. Retry a failed publish without leaving the form. Confirm there is one post.
6. Archive the class and verify new posting is denied. Remove enrollment, reconnect
   the student, and confirm its class/files disappear. A nonmember cannot read files.
7. Sign out and switch accounts. Confirm the other account's materials are hidden.
   Replay onboarding and verify saved profile and class data remain unchanged.

References: [Flutter Storage downloads](https://firebase.google.com/docs/storage/flutter/download-files),
[Flutter FCM](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages),
[Firestore triggers](https://firebase.google.com/docs/functions/firestore-events).
