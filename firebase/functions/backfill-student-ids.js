// One-time migration for direct enrollment discovery. Uses private Application
// Default Credentials; run manually only after reviewing the target project.
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {forEachPage} = require('./memberships');

if (process.argv[2] !== '--project=filo-app-1a2a5') {
  throw new Error('Pass --project=filo-app-1a2a5 explicitly.');
}
initializeApp({projectId: 'filo-app-1a2a5'});
const db = getFirestore();
forEachPage(db.collection('classes'), (course) =>
  forEachPage(course.ref.collection('enrollments'), (student) =>
    db.runTransaction(async (tx) => {
      const current = await tx.get(student.ref);
      if (current.exists && current.data().studentId !== student.id) {
        tx.update(student.ref, {studentId: student.id});
      }
    })))
  .then(() => console.log('Enrollment studentId fields updated.'))
  .catch(() => { console.error('Enrollment migration failed; safe to retry.'); process.exitCode = 1; });
