const { randomUUID } = require('node:crypto');
const { initializeApp, getApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { GoogleAuth } = require('google-auth-library');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');

initializeApp();
const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/firebase.messaging'] });

async function sendToFid(message) {
  const projectId = process.env.GCLOUD_PROJECT || getApp().options.projectId;
  if (!projectId) throw new Error('Firebase project ID is unavailable to the notification function.');
  const client = await auth.getClient();
  return client.request({
    url: `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    method: 'POST',
    data: { message },
  });
}

exports.notifySubstituteAssignment = onDocumentWritten(
  {
    document: 'schools/{schoolId}/substitutions/{assignmentId}',
    region: 'us-central1',
    retry: true,
  },
  async (event) => {
    const before = event.data?.before.data();
    const assignment = event.data?.after.data();
    if (!assignment || assignment.status !== 'assigned') return;
    if (before?.status === 'assigned' &&
        before?.substituteTeacherId === assignment.substituteTeacherId) return;

    const { schoolId } = event.params;
    const db = getFirestore();
    const school = db.collection('schools').doc(schoolId);
    const teacherSnapshot = await school.collection('teachers')
      .doc(String(assignment.substituteTeacherId)).get();
    const teacher = teacherSnapshot.data();
    const email = typeof teacher?.email === 'string' ? teacher.email.trim().toLowerCase() : '';
    if (!teacherSnapshot.exists || !email) {
      logger.warn('Substitute has no email address; assignment notification was not sent.', {
        schoolId,
        assignmentId: event.params.assignmentId,
      });
      return;
    }

    // The email query uses a single indexed field; school and role are checked below.
    const users = await db.collection('users').where('email', '==', email).get();
    const recipients = users.docs.filter((doc) => {
      const user = doc.data();
      return user.schoolId === schoolId && user.role === 'teacher' && user.active === true;
    });
    if (recipients.length === 0) {
      logger.info('No active teacher account matches the substitute email.', {
        schoolId,
        assignmentId: event.params.assignmentId,
      });
      return;
    }

    const classRef = school.collection('classes').doc(String(assignment.classId));
    const subjectRef = school.collection('subjects').doc(String(assignment.subjectId));
    const periodRef = school.collection('periods').doc(String(assignment.periodId));
    const [classSnapshot, subjectSnapshot, periodSnapshot] = await Promise.all([
      classRef.get(), subjectRef.get(), periodRef.get(),
    ]);
    const className = classSnapshot.data()?.name || 'assigned class';
    const subjectName = subjectSnapshot.data()?.name || 'assigned subject';
    const periodName = periodSnapshot.data()?.name || `Period ${assignment.periodId}`;
    const title = 'New substitute duty';
    const body = `Cover ${subjectName} for ${className} during ${periodName} on ${assignment.dateKey}.`;

    for (const recipient of recipients) {
      const notificationRef = school.collection('notifications').doc(`${event.id}_${recipient.id}`);
      const claimId = randomUUID();
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(notificationRef);
        const data = current.data();
        if (data?.deliveryStatus === 'sent' || data?.deliveryStatus === 'no_installations') return false;
        if (data?.deliveryStatus === 'sending' &&
            data?.leaseUntil instanceof Timestamp && data.leaseUntil.toMillis() > Date.now()) return false;
        transaction.set(notificationRef, {
          recipientUid: recipient.id,
          teacherId: assignment.substituteTeacherId,
          assignmentId: event.params.assignmentId,
          type: 'substitution_assigned',
          title,
          body,
          readAt: null,
          createdAt: data?.createdAt || FieldValue.serverTimestamp(),
          deliveryStatus: 'sending',
          claimId,
          leaseUntil: Timestamp.fromMillis(Date.now() + 120000),
        }, { merge: true });
        return true;
      });
      if (!claimed) continue;

      const installations = await db.collection('users').doc(recipient.id)
        .collection('fcmInstallations').get();
      const fids = installations.docs
        .map((doc) => doc.data().fid)
        .filter((fid) => typeof fid === 'string' && fid.length > 0);
      if (fids.length === 0) {
        await notificationRef.update({
          deliveryStatus: 'no_installations',
          leaseUntil: FieldValue.delete(),
          claimId: FieldValue.delete(),
        });
        continue;
      }

      try {
        const responses = await Promise.allSettled(fids.map((fid) => sendToFid({
          fid,
          notification: { title, body },
          data: {
            notificationId: notificationRef.id,
            assignmentId: String(event.params.assignmentId),
            type: 'substitution_assigned',
          },
          webpush: { fcmOptions: { link: 'https://teachersubstitute.web.app/' } },
        })));
        const succeeded = responses.filter((result) => result.status === 'fulfilled').length;
        const failures = responses.filter((result) => result.status === 'rejected');
        if (succeeded === 0 && failures.length > 0) {
          throw failures[0].reason;
        }
        await notificationRef.update({
          deliveryStatus: 'sent',
          sentCount: succeeded,
          failedCount: failures.length,
          leaseUntil: FieldValue.delete(),
          claimId: FieldValue.delete(),
        });
      } catch (error) {
        logger.error('Assignment notification delivery failed.', {
          schoolId,
          assignmentId: event.params.assignmentId,
          error: error?.message || String(error),
        });
        await notificationRef.update({
          deliveryStatus: 'pending',
          leaseUntil: FieldValue.delete(),
          claimId: FieldValue.delete(),
        });
        throw error;
      }
    }
  },
);
