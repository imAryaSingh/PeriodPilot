import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/school_models.dart';
import 'school_database.dart';

class FirebaseSchoolDatabase implements SchoolDatabase {
  FirebaseSchoolDatabase({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  String? _schoolId;

  Future<String> get _currentSchoolId async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const SchoolDataException('Sign in to access school data.');
    }
    if (_schoolId != null) return _schoolId!;
    final profile = await _firestore.collection('users').doc(uid).get();
    final value = profile.data()?['schoolId'];
    if (!profile.exists || value is! String || value.isEmpty) {
      throw const SchoolDataException(
        'This account is not linked to a school.',
      );
    }
    return _schoolId = value;
  }

  Future<DocumentReference<Map<String, dynamic>>> get _school async =>
      _firestore.collection('schools').doc(await _currentSchoolId);

  Future<CollectionReference<Map<String, dynamic>>> _collection(
    String name,
  ) async => (await _school).collection(name);

  int _newId() =>
      DateTime.now().microsecondsSinceEpoch + Random.secure().nextInt(1000);

  @override
  Future<SchoolProfile> getSchoolProfile() async {
    final doc = await (await _school).get();
    final data = doc.data() ?? const <String, dynamic>{};
    return SchoolProfile(
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
    );
  }

  @override
  Future<void> saveSchoolProfile(SchoolProfile profile) async {
    await (await _school).set({
      'name': profile.name.trim(),
      'address': profile.address.trim(),
      'phone': profile.phone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<List<Teacher>> getTeachers() async {
    final snapshot = await (await _collection('teachers')).get();
    final teachers = snapshot.docs.map((doc) {
      final d = doc.data();
      return Teacher(
        id: d['id'] as int,
        fullName: d['fullName'] as String? ?? '',
        staffCode: d['staffCode'] as String? ?? '',
        email: d['email'] as String? ?? '',
        phone: d['phone'] as String? ?? '',
        isActive: d['isActive'] as bool? ?? true,
      );
    }).toList();
    teachers.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return teachers;
  }

  @override
  Future<void> saveTeacher(Teacher teacher) async {
    final collection = await _collection('teachers');
    final id = teacher.id ?? _newId();
    final code = teacher.staffCode.trim();
    if (code.isNotEmpty) {
      final duplicate = await collection
          .where('staffCodeKey', isEqualTo: code.toLowerCase())
          .get();
      if (duplicate.docs.any((doc) => doc.id != '$id')) {
        throw const DuplicateSchoolRecordException(
          'That staff ID is already in use.',
        );
      }
    }
    final ref = collection.doc('$id');
    final old = await ref.get();
    await ref.set({
      'id': id,
      'staffCode': code,
      'staffCodeKey': code.toLowerCase(),
      'fullName': teacher.fullName.trim(),
      'email': teacher.email.trim(),
      'phone': teacher.phone.trim(),
      'isActive': teacher.isActive,
      'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setTeacherActive(int id, bool isActive) async {
    await (await _collection('teachers')).doc('$id').update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<SchoolClass>> getClasses() async {
    final snapshot = await (await _collection('classes')).get();
    final classes = snapshot.docs
        .map(
          (doc) => SchoolClass(
            id: doc.data()['id'] as int,
            name: doc.data()['name'] as String? ?? '',
          ),
        )
        .toList();
    classes.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return classes;
  }

  @override
  Future<List<SchoolSection>> getSections(int classId) async {
    final snapshot = await (await _collection(
      'classes',
    )).doc('$classId').collection('sections').get();
    final sections = snapshot.docs
        .map(
          (doc) => SchoolSection(
            id: doc.data()['id'] as int,
            classId: classId,
            name: doc.data()['name'] as String? ?? '',
          ),
        )
        .toList();
    sections.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return sections;
  }

  @override
  Future<void> saveClass(SchoolClass schoolClass) async {
    final collection = await _collection('classes');
    final id = schoolClass.id == 0 ? _newId() : schoolClass.id;
    final name = schoolClass.name.trim();
    final duplicate = await collection
        .where('nameKey', isEqualTo: name.toLowerCase())
        .get();
    if (duplicate.docs.any((doc) => doc.id != '$id')) {
      throw const DuplicateSchoolRecordException(
        'That class name is already in use.',
      );
    }
    await collection.doc('$id').set({
      'id': id,
      'name': name,
      'nameKey': name.toLowerCase(),
    });
  }

  @override
  Future<void> deleteClass(int id) async {
    final ref = (await _collection('classes')).doc('$id');
    final sections = await ref.collection('sections').get();
    final batch = _firestore.batch();
    for (final section in sections.docs) {
      batch.delete(section.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  @override
  Future<void> saveSection(SchoolSection section) async {
    final parent = (await _collection('classes')).doc('${section.classId}');
    if (!(await parent.get()).exists) {
      throw const SchoolDataException('Class not found.');
    }
    final collection = parent.collection('sections');
    final id = section.id == 0 ? _newId() : section.id;
    final name = section.name.trim();
    final duplicate = await collection
        .where('nameKey', isEqualTo: name.toLowerCase())
        .get();
    if (duplicate.docs.any((doc) => doc.id != '$id')) {
      throw const DuplicateSchoolRecordException(
        'That section name is already in use.',
      );
    }
    await collection.doc('$id').set({
      'id': id,
      'name': name,
      'nameKey': name.toLowerCase(),
    });
  }

  @override
  Future<void> deleteSection(int id) async {
    final classes = await (await _collection('classes')).get();
    for (final schoolClass in classes.docs) {
      final section = schoolClass.reference.collection('sections').doc('$id');
      if ((await section.get()).exists) {
        await section.delete();
        return;
      }
    }
  }

  @override
  Future<List<Subject>> getSubjects() async {
    final snapshot = await (await _collection('subjects')).get();
    final subjects = snapshot.docs.map((doc) {
      final data = doc.data();
      return Subject(
        id: data['id'] as int,
        name: data['name'] as String? ?? '',
        code: data['code'] as String? ?? '',
        isActive: data['isActive'] as bool? ?? true,
      );
    }).toList();
    subjects.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return subjects;
  }

  @override
  Future<void> saveSubject(Subject subject) async {
    final collection = await _collection('subjects');
    final id = subject.id ?? _newId();
    final name = subject.name.trim();
    final code = subject.code.trim();
    final duplicateName = await collection
        .where('nameKey', isEqualTo: name.toLowerCase())
        .get();
    if (duplicateName.docs.any((doc) => doc.id != '$id')) {
      throw const DuplicateSchoolRecordException(
        'That subject name is already in use.',
      );
    }
    if (code.isNotEmpty) {
      final duplicateCode = await collection
          .where('codeKey', isEqualTo: code.toLowerCase())
          .get();
      if (duplicateCode.docs.any((doc) => doc.id != '$id')) {
        throw const DuplicateSchoolRecordException(
          'That subject code is already in use.',
        );
      }
    }
    await collection.doc('$id').set({
      'id': id,
      'name': name,
      'nameKey': name.toLowerCase(),
      'code': code,
      'codeKey': code.toLowerCase(),
      'isActive': subject.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setSubjectActive(int id, bool isActive) async {
    await (await _collection(
      'subjects',
    )).doc('$id').update({'isActive': isActive});
  }

  @override
  Future<List<SchoolPeriod>> getPeriods() async {
    final snapshot = await (await _collection('periods')).get();
    final periods = snapshot.docs.map((doc) {
      final data = doc.data();
      return SchoolPeriod(
        id: data['id'] as int,
        name: data['name'] as String? ?? '',
        startMinute: data['startMinute'] as int? ?? 0,
        endMinute: data['endMinute'] as int? ?? 0,
        isActive: data['isActive'] as bool? ?? true,
        sortOrder:
            data['sortOrder'] as int? ?? data['startMinute'] as int? ?? 0,
      );
    }).toList();
    periods.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.startMinute.compareTo(b.startMinute);
    });
    return periods;
  }

  @override
  Future<void> savePeriod(SchoolPeriod period) async {
    if (period.startMinute < 0 ||
        period.endMinute > 1439 ||
        period.startMinute >= period.endMinute) {
      throw const SchoolDataException('Enter a valid period time range.');
    }
    final collection = await _collection('periods');
    final id = period.id ?? _newId();
    final snapshot = await collection.get();
    final overlap = snapshot.docs.any((doc) {
      final data = doc.data();
      if (data['id'] == id || data['isActive'] == false) return false;
      final start = data['startMinute'] as int? ?? 0;
      final end = data['endMinute'] as int? ?? 0;
      return period.startMinute < end && period.endMinute > start;
    });
    if (overlap) {
      throw const DuplicateSchoolRecordException(
        'Period times cannot overlap another active period.',
      );
    }
    await collection.doc('$id').set({
      'id': id,
      'name': period.name.trim(),
      'startMinute': period.startMinute,
      'endMinute': period.endMinute,
      'isActive': period.isActive,
      'sortOrder': period.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> savePeriodConfiguration(List<SchoolPeriod> periods) async {
    validateSchoolPeriodConfiguration(periods);
    final collection = await _collection('periods');
    final existing = await collection.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final requestedIds = periods
        .where((period) => period.id != null)
        .map((period) => '${period.id}')
        .toSet();
    if (!existingIds.containsAll(requestedIds) ||
        !requestedIds.containsAll(existingIds)) {
      throw const SchoolDataException(
        'The period list changed. Reload the timetable and try again.',
      );
    }

    final lessonSnapshot = await (await _collection('timetables')).get();
    final assignedIds = lessonSnapshot.docs
        .map((doc) => doc.data()['periodId'])
        .whereType<int>()
        .toSet();
    for (final period in periods) {
      if (period.id != null &&
          assignedIds.contains(period.id) &&
          !period.isActive) {
        throw const SchoolDataException(
          'A period with timetable lessons cannot be deactivated. Its lessons were preserved.',
        );
      }
    }

    final schedule = periods
        .map(
          (period) => SchoolPeriod(
            id: period.id ?? _newId(),
            name: period.name.trim(),
            startMinute: period.startMinute,
            endMinute: period.endMinute,
            isActive: period.isActive,
            sortOrder: period.sortOrder,
          ),
        )
        .toList(growable: false);
    final refs = schedule
        .map((period) => collection.doc('${period.id}'))
        .toList();
    await _firestore.runTransaction<void>((transaction) async {
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in refs) {
        snapshots.add(await transaction.get(ref));
      }
      for (var index = 0; index < schedule.length; index++) {
        final wasExisting = periods[index].id != null;
        if (wasExisting != snapshots[index].exists) {
          throw const SchoolDataException(
            'The period list changed. Reload the timetable and try again.',
          );
        }
      }
      for (var index = 0; index < schedule.length; index++) {
        final period = schedule[index];
        transaction.set(refs[index], {
          'id': period.id,
          'name': period.name,
          'startMinute': period.startMinute,
          'endMinute': period.endMinute,
          'sortOrder': period.sortOrder,
          'isActive': period.isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  @override
  Future<void> deletePeriod(int id) async {
    final lessons = await (await _collection(
      'timetables',
    )).where('periodId', isEqualTo: id).limit(1).get();
    final substitutions = await (await _collection(
      'substitutions',
    )).where('periodId', isEqualTo: id).limit(1).get();
    if (lessons.docs.isNotEmpty || substitutions.docs.isNotEmpty) {
      throw const SchoolDataException(
        'This period is used by timetable or substitution history. Deactivate it to preserve those records.',
      );
    }
    final ref = (await _collection('periods')).doc('$id');
    if (!(await ref.get()).exists) {
      throw const SchoolDataException('Period not found.');
    }
    await ref.delete();
  }

  @override
  Future<void> setPeriodActive(int id, bool isActive) async {
    final periods = await _collection('periods');
    final periodRef = periods.doc('$id');
    final periodSnapshot = await periodRef.get();
    final data = periodSnapshot.data();
    if (data == null) throw const SchoolDataException('Period not found.');
    final entries = await _collection('timetables');
    final assigned = await entries.where('periodId', isEqualTo: id).get();
    if (!isActive && assigned.docs.isNotEmpty) {
      throw const SchoolDataException(
        'Move or remove the lessons assigned to this period before deactivating it.',
      );
    }
    if (isActive) {
      final overlaps = await periods.get();
      final start = data['startMinute'] as int? ?? 0;
      final end = data['endMinute'] as int? ?? 0;
      final hasOverlap = overlaps.docs.any((doc) {
        final other = doc.data();
        if (other['id'] == id || other['isActive'] == false) return false;
        final otherStart = other['startMinute'] as int? ?? 0;
        final otherEnd = other['endMinute'] as int? ?? 0;
        return start < otherEnd && end > otherStart;
      });
      if (hasOverlap) {
        throw const DuplicateSchoolRecordException(
          'Period times cannot overlap another active period.',
        );
      }
    }
    await periodRef.update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<int>> getWorkingDays() async {
    final data = (await _school).get().then((doc) => doc.data());
    final school = await data;
    final days = school?['workingDays'];
    if (days is List) {
      return days.whereType<int>().where((day) => day >= 1 && day <= 7).toList()
        ..sort();
    }
    return const [1, 2, 3, 4, 5];
  }

  @override
  Future<void> saveWorkingDays(List<int> days) async {
    final normalized =
        days.toSet().where((day) => day >= 1 && day <= 7).toList()..sort();
    if (normalized.isEmpty) {
      throw const SchoolDataException('Select at least one working day.');
    }
    await (await _school).set({
      'workingDays': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<List<TimetableEntry>> getTimetableEntries() async {
    final snapshot = await (await _collection('timetables')).get();
    final entries = snapshot.docs
        .map((doc) => TimetableEntry.fromMap(doc.data()))
        .toList();
    entries.sort((a, b) {
      final day = a.dayOfWeek.compareTo(b.dayOfWeek);
      return day != 0 ? day : a.periodId.compareTo(b.periodId);
    });
    return entries;
  }

  @override
  Future<void> saveTimetableEntry(TimetableEntry entry) async {
    final collection = await _collection('timetables');
    final id = entry.id ?? _newId();
    final existing = await collection.get();
    for (final doc in existing.docs) {
      final data = doc.data();
      if (data['id'] == id) continue;
      if (data['dayOfWeek'] != entry.dayOfWeek ||
          data['periodId'] != entry.periodId) {
        continue;
      }
      final sameClass =
          data['classId'] == entry.classId &&
          (data['sectionId'] == entry.sectionId ||
              data['sectionId'] == null ||
              entry.sectionId == null);
      if (sameClass) {
        throw const DuplicateSchoolRecordException(
          'This class or section already has a lesson during that period.',
        );
      }
      if (data['teacherId'] == entry.teacherId) {
        throw const DuplicateSchoolRecordException(
          'This teacher is already assigned during that period.',
        );
      }
    }
    await collection.doc('$id').set({
      'id': id,
      'classId': entry.classId,
      'sectionId': entry.sectionId,
      'subjectId': entry.subjectId,
      'teacherId': entry.teacherId,
      'periodId': entry.periodId,
      'dayOfWeek': entry.dayOfWeek,
      'room': entry.room.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteTimetableEntry(int id) async {
    await (await _collection('timetables')).doc('$id').delete();
  }

  @override
  Future<List<TeacherAbsence>> getAbsences() async {
    final snapshot = await (await _collection('attendance')).get();
    final absences = snapshot.docs
        .map((doc) => TeacherAbsence.fromMap(doc.data()))
        .toList();
    absences.sort((a, b) {
      final date = b.date.compareTo(a.date);
      return date != 0 ? date : (b.id ?? 0).compareTo(a.id ?? 0);
    });
    return absences;
  }

  @override
  Future<void> saveAbsence(TeacherAbsence absence) async {
    final collection = await _collection('attendance');
    final id = absence.id ?? _newId();
    final dateKey = schoolDateKey(absence.date);
    final existing = await collection.get();
    final duplicate = existing.docs.any((doc) {
      final data = doc.data();
      return data['id'] != id &&
          data['teacherId'] == absence.teacherId &&
          data['dateKey'] == dateKey;
    });
    if (duplicate) {
      throw const DuplicateSchoolRecordException(
        'This teacher already has an absence record for that date.',
      );
    }
    final ref = collection.doc('$id');
    final old = await ref.get();
    await ref.set({
      'id': id,
      'teacherId': absence.teacherId,
      'dateKey': dateKey,
      'type': absence.type.key,
      'notes': absence.notes.trim(),
      'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteAbsence(int id) async {
    await (await _collection('attendance')).doc('$id').delete();
  }

  @override
  Future<List<SubstitutionAssignment>> getSubstitutions() async {
    final snapshot = await (await _collection('substitutions')).get();
    final assignments = snapshot.docs
        .map((doc) => SubstitutionAssignment.fromMap(doc.data()))
        .toList();
    assignments.sort((a, b) => b.date.compareTo(a.date));
    return assignments;
  }

  @override
  Future<void> saveSubstitution(SubstitutionAssignment assignment) async {
    await _runOnlineAssignment(() async {
      final collection = await _collection('substitutions');
      // Read current server state first. A cache-only duplicate check could be
      // stale after another administrator assigns the same period.
      final existing = await collection.get(
        const GetOptions(source: Source.server),
      );
      final id = assignment.id ?? _newId();
      for (final doc in existing.docs) {
        final row = doc.data();
        if (row['id'] == id ||
            row['status'] == 'cancelled' ||
            row['dateKey'] != assignment.dateKey) {
          continue;
        }
        if (row['timetableEntryId'] == assignment.timetableEntryId) {
          throw const DuplicateSchoolRecordException(
            'This lesson already has a substitute assigned.',
          );
        }
        if (row['periodId'] == assignment.periodId &&
            row['substituteTeacherId'] == assignment.substituteTeacherId) {
          throw const DuplicateSchoolRecordException(
            'This teacher already has a substitution during that period.',
          );
        }
      }

      final ref = collection.doc('$id');
      final claims = (await _school).collection('substitutionClaims');
      final newClaims = _substitutionClaimReferences(
        claims,
        dateKey: assignment.dateKey,
        timetableEntryId: assignment.timetableEntryId,
        periodId: assignment.periodId,
        substituteTeacherId: assignment.substituteTeacherId,
      );
      await _firestore.runTransaction<void>((transaction) async {
        final oldAssignment = await transaction.get(ref);
        final oldData = oldAssignment.data();
        final claimRefs = <String, DocumentReference<Map<String, dynamic>>>{
          for (final claim in newClaims) claim.path: claim,
        };
        if (oldData != null && oldData['status'] == 'assigned') {
          for (final oldClaim in _substitutionClaimReferences(
            claims,
            dateKey: oldData['dateKey'] as String,
            timetableEntryId: (oldData['timetableEntryId'] as num).toInt(),
            periodId: (oldData['periodId'] as num).toInt(),
            substituteTeacherId: (oldData['substituteTeacherId'] as num)
                .toInt(),
          )) {
            claimRefs.putIfAbsent(oldClaim.path, () => oldClaim);
          }
        }

        final claimSnapshots =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final claim in claimRefs.values) {
          claimSnapshots[claim.path] = await transaction.get(claim);
        }
        for (final claim in newClaims) {
          final owner = claimSnapshots[claim.path]?.data()?['assignmentId'];
          if (owner != null && owner.toString() != '$id') {
            final isLessonClaim = claim.id.startsWith('lesson_');
            throw DuplicateSchoolRecordException(
              isLessonClaim
                  ? 'This lesson already has a substitute assigned.'
                  : 'This teacher already has a substitution during that period.',
            );
          }
        }

        if (oldData != null && oldData['status'] == 'assigned') {
          for (final oldClaim in claimRefs.values.where(
            (claim) => !newClaims.any((next) => next.path == claim.path),
          )) {
            final owner = claimSnapshots[oldClaim.path]
                ?.data()?['assignmentId'];
            if (owner?.toString() == '$id') transaction.delete(oldClaim);
          }
        }
        final oldCreatedAt = oldData?['createdAt'];
        transaction.set(ref, {
          'id': id,
          'timetableEntryId': assignment.timetableEntryId,
          'absentTeacherId': assignment.absentTeacherId,
          'substituteTeacherId': assignment.substituteTeacherId,
          'dateKey': assignment.dateKey,
          'classId': assignment.classId,
          'sectionId': assignment.sectionId,
          'subjectId': assignment.subjectId,
          'periodId': assignment.periodId,
          'room': assignment.room.trim(),
          'isOverride': assignment.isOverride,
          'status': 'assigned',
          'createdAt': oldCreatedAt ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        for (final claim in newClaims) {
          transaction.set(claim, {
            'assignmentId': id,
            'claimType': claim.id.startsWith('lesson_')
                ? 'lesson'
                : 'teacherPeriod',
            'dateKey': assignment.dateKey,
            'timetableEntryId': assignment.timetableEntryId,
            'periodId': assignment.periodId,
            'substituteTeacherId': assignment.substituteTeacherId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    });
  }

  @override
  Future<void> cancelSubstitution(int id) async {
    await _runOnlineAssignment(() async {
      final assignmentRef = (await _collection('substitutions')).doc('$id');
      final claims = (await _school).collection('substitutionClaims');
      await _firestore.runTransaction<void>((transaction) async {
        final assignmentSnapshot = await transaction.get(assignmentRef);
        final row = assignmentSnapshot.data();
        if (row == null || row['status'] == 'cancelled') return;
        final claimRefs = _substitutionClaimReferences(
          claims,
          dateKey: row['dateKey'] as String,
          timetableEntryId: (row['timetableEntryId'] as num).toInt(),
          periodId: (row['periodId'] as num).toInt(),
          substituteTeacherId: (row['substituteTeacherId'] as num).toInt(),
        );
        final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final claim in claimRefs) {
          snapshots.add(await transaction.get(claim));
        }
        for (var index = 0; index < claimRefs.length; index++) {
          if (snapshots[index].data()?['assignmentId']?.toString() == '$id') {
            transaction.delete(claimRefs[index]);
          }
        }
        transaction.update(assignmentRef, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  List<DocumentReference<Map<String, dynamic>>> _substitutionClaimReferences(
    CollectionReference<Map<String, dynamic>> claims, {
    required String dateKey,
    required int timetableEntryId,
    required int periodId,
    required int substituteTeacherId,
  }) => [
    claims.doc('lesson_${dateKey}_$timetableEntryId'),
    claims.doc('teacher_${dateKey}_${periodId}_$substituteTeacherId'),
  ];

  Future<void> _runOnlineAssignment(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'network-request-failed') {
        throw const SchoolDataException(
          'Connect to the internet before changing substitution assignments. This keeps the server schedule authoritative.',
        );
      }
      rethrow;
    }
  }
}
