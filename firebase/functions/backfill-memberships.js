// Run once after deploying for enrollments that predate the index triggers.
// Requires Application Default Credentials; never embed service-account keys.
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {syncMembership, forEachPage} = require('./memberships');

if (process.argv[2] !== '--project=filo-app-1a2a5') {
  throw new Error('Pass --project=filo-app-1a2a5 explicitly.');
}
initializeApp({projectId: 'filo-app-1a2a5'});
const db = getFirestore();
forEachPage(db.collection('classes'), (course) =>
  forEachPage(course.ref.collection('enrollments'), (student) =>
    syncMembership(course.id, student.id)))
  .then(() => console.log('Existing enrollment indexes updated.'))
  .catch((error) => { console.error(error); process.exitCode = 1; });
