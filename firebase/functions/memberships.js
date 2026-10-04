const {getFirestore, FieldValue, FieldPath} = require('firebase-admin/firestore');

// Read current source documents inside a transaction. Duplicate/out-of-order
// triggers must never resurrect a removed enrollment or an old class name.
async function syncMembership(classId, uid) {
  const db = getFirestore();
  const classRef = db.doc(`classes/${classId}`);
  const enrollmentRef = classRef.collection('enrollments').doc(uid);
  const indexRef = db.doc(`users/${uid}/classes/${classId}`);
  await db.runTransaction(async (tx) => {
    const [course, enrollment] = await tx.getAll(classRef, enrollmentRef);
    if (!course.exists || !enrollment.exists) {
      tx.delete(indexRef);
      return;
    }
    const data = course.data();
    tx.set(indexRef, {
      name: data.name || data.title || 'Class',
      archived: data.archived === true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function forEachPage(collection, visit) {
  let cursor;
  while (true) {
    let query = collection.orderBy(FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return;
    // Bounded concurrency prevents a large class from flooding Firestore/FCM.
    for (let offset = 0; offset < page.docs.length; offset += 10) {
      await Promise.all(page.docs.slice(offset, offset + 10).map(visit));
    }
    cursor = page.docs[page.docs.length - 1];
  }
}

module.exports = {syncMembership, forEachPage};
