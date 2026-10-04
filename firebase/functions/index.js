const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onDocumentCreated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const {createHash} = require('node:crypto');
const {syncMembership, forEachPage} = require('./memberships');

initializeApp();
const db = getFirestore();
const options = {region: 'asia-southeast1', retry: true, timeoutSeconds: 540, maxInstances: 10};

exports.indexMaterialEnrollment = onDocumentWritten({
  ...options, document: 'classes/{classId}/enrollments/{uid}',
}, (event) => syncMembership(event.params.classId, event.params.uid));

exports.indexMaterialClass = onDocumentWritten({
  ...options, document: 'classes/{classId}',
}, async (event) => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (before && after && before.name === after.name && before.title === after.title &&
      before.archived === after.archived) return;
  await forEachPage(db.collection(`classes/${event.params.classId}/enrollments`),
    (doc) => syncMembership(event.params.classId, doc.id));
});

exports.queueMaterialNotifications = onDocumentCreated({
  ...options, document: 'classes/{classId}/materials/{materialId}',
}, async (event) => {
  const {classId, materialId} = event.params;
  const alertId = createHash('sha256').update(`${classId}/${materialId}`).digest('hex');
  // Per-student outbox records make fanout retryable without creating new alerts.
  await forEachPage(db.collection(`classes/${classId}/enrollments`), async (student) => {
    try {
      await db.doc(`users/${student.id}/materialAlerts/${alertId}`).create({
        classId, materialId, createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (error.code !== 6 && error.code !== 'already-exists') throw error;
    }
  });
});

exports.deliverMaterialNotification = onDocumentCreated({
  ...options, document: 'users/{uid}/materialAlerts/{alertId}',
}, async (event) => {
  const {uid, alertId} = event.params;
  const alert = await event.data.ref.get();
  if (!alert.exists || alert.data().deliveredAt) return;
  const {classId, materialId} = alert.data();
  const [enrollment, material] = await db.getAll(
    db.doc(`classes/${classId}/enrollments/${uid}`),
    db.doc(`classes/${classId}/materials/${materialId}`));
  if (!enrollment.exists || !material.exists) return;
  await forEachPage(db.collection(`users/${uid}/devices`), async (device) => {
    const token = device.data().token;
    if (typeof token !== 'string' || !token) return;
    try {
      await getMessaging().send({
        token,
        // Keep lock-screen text generic, including on shared devices.
        notification: {title: 'New class material', body: 'Open Filo to see what is new.'},
        data: {uid, classId, materialId},
        android: {
          priority: 'high', ttl: 24 * 60 * 60 * 1000,
          notification: {tag: alertId, sound: 'default'},
        },
      });
    } catch (error) {
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
        await device.ref.delete();
      } else { throw error; }
    }
  });
  await event.data.ref.update({deliveredAt: FieldValue.serverTimestamp()});
});
