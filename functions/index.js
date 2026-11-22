const { randomUUID } = require('node:crypto');
const { initializeApp, getApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { GoogleAuth } = require('google-auth-library');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
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

    // Prefer the stable school/teacher link; retain email fallback for older accounts.
    let users = await db.collection('users')
      .where('teacherId', '==', Number(assignment.substituteTeacherId)).get();
    if (users.empty && email) users = await db.collection('users').where('email', '==', email).get();
    const recipients = users.docs.filter((doc) => {
      const user = doc.data();
      return user.schoolId === schoolId && user.role === 'teacher' && user.active === true
        && (user.teacherId == null || Number(user.teacherId) === Number(assignment.substituteTeacherId));
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

exports.setTeacherLogin = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in as a school administrator.');
  const db = getFirestore();
  const profileSnapshot = await db.collection('users').doc(request.auth.uid).get();
  const profile = profileSnapshot.data();
  if (!profile || profile.active !== true || profile.role !== 'administrator' || !profile.schoolId) {
    throw new HttpsError('permission-denied', 'Only an active school administrator can set teacher logins.');
  }

  const teacherId = Number(request.data?.teacherId);
  const password = typeof request.data?.password === 'string' ? request.data.password : '';
  if (!Number.isSafeInteger(teacherId) || teacherId <= 0) {
    throw new HttpsError('invalid-argument', 'Select a valid teacher.');
  }
  if (password.length < 10 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    throw new HttpsError('invalid-argument', 'Use at least 10 characters with a letter and a number.');
  }

  const school = db.collection('schools').doc(profile.schoolId);
  const teacherRef = school.collection('teachers').doc(String(teacherId));
  const teacherSnapshot = await teacherRef.get();
  const teacher = teacherSnapshot.data();
  if (!teacherSnapshot.exists || !teacher || teacher.isActive !== true) {
    throw new HttpsError('not-found', 'This active teacher was not found in your school.');
  }
  const loginId = String(teacher.staffCode || '').trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,31}$/.test(loginId)) {
    throw new HttpsError('failed-precondition', 'Set a Teacher ID of 2–32 letters, numbers, dots, underscores, or hyphens first.');
  }

  // IDs are globally unique because teachers enter only an ID at sign-in, without a school selector.
  const authEmail = `teacher.${loginId}@login.periodpilot.invalid`;
  const linkedUid = typeof teacher.authUid === 'string' ? teacher.authUid : null;
  const conflictingProfiles = await db.collection('users').where('loginId', '==', loginId).get();
  const conflictingProfile = conflictingProfiles.docs.find((doc) => doc.id !== linkedUid);
  if (conflictingProfile) throw new HttpsError('already-exists', 'That Teacher ID is already used for sign-in.');

  let uid = linkedUid;
  let created = false;
  let existingProfileData;
  if (uid) {
    const linkedProfile = await db.collection('users').doc(uid).get();
    existingProfileData = linkedProfile.data();
    if (!existingProfileData || existingProfileData.role !== 'teacher'
        || existingProfileData.schoolId !== profile.schoolId
        || Number(existingProfileData.teacherId) !== teacherId) {
      throw new HttpsError('failed-precondition', 'This teacher login link is inconsistent. Contact support before resetting it.');
    }
    try {
      await getAuth().updateUser(uid, { email: authEmail, password, displayName: teacher.fullName });
    } catch (error) {
      if (error.code === 'auth/user-not-found') uid = null;
      else if (error.code === 'auth/email-already-exists') throw new HttpsError('already-exists', 'That Teacher ID is already used for sign-in.');
      else throw error;
    }
  }
  if (!uid) {
    try {
      const user = await getAuth().createUser({ email: authEmail, password, displayName: teacher.fullName });
      uid = user.uid;
      created = true;
    } catch (error) {
      if (error.code === 'auth/email-already-exists') throw new HttpsError('already-exists', 'That Teacher ID already has a login account. Contact support to link it.');
      throw error;
    }
  }

  try {
    await db.collection('users').doc(uid).set({
      uid,
      email: typeof teacher.email === 'string' ? teacher.email.trim().toLowerCase() : '',
      displayName: teacher.fullName,
      role: 'teacher',
      schoolId: profile.schoolId,
      teacherId,
      loginId,
      active: created ? true : existingProfileData.active === true,
      ...(created ? { createdAt: FieldValue.serverTimestamp() } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await teacherRef.update({ authUid: uid, updatedAt: FieldValue.serverTimestamp() });
  } catch (error) {
    if (created) await getAuth().deleteUser(uid).catch(() => {});
    throw error;
  }
  return { loginId, created };
});
