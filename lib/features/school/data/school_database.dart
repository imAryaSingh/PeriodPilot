import '../domain/school_models.dart';

T? firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

abstract interface class SchoolDatabase {
  Future<SchoolProfile> getSchoolProfile();
  Future<void> saveSchoolProfile(SchoolProfile profile);
  Future<List<Teacher>> getTeachers();
  Future<void> saveTeacher(Teacher teacher);
  Future<void> setTeacherActive(int id, bool isActive);
  Future<List<SchoolClass>> getClasses();
  Future<List<SchoolSection>> getSections(int classId);
  Future<void> saveClass(SchoolClass schoolClass);
  Future<void> setClassActive(int id, bool isActive);
  Future<void> saveSection(SchoolSection section);
  Future<void> setSectionActive(int id, bool isActive);
  Future<List<Subject>> getSubjects();
  Future<void> saveSubject(Subject subject);
  Future<void> setSubjectActive(int id, bool isActive);
  Future<List<SchoolPeriod>> getPeriods();
  Future<void> savePeriod(SchoolPeriod period);
  Future<void> savePeriodConfiguration(List<SchoolPeriod> periods);
  Future<void> deletePeriod(int id);
  Future<void> setPeriodActive(int id, bool isActive);
  Future<List<int>> getWorkingDays();
  Future<void> saveWorkingDays(List<int> days);
  Future<List<TimetableEntry>> getTimetableEntries();
  Future<void> saveTimetableEntry(TimetableEntry entry);
  Future<void> saveTimetableEntries(List<TimetableEntry> entries);
  Future<void> deleteTimetableEntry(int id);
  Future<List<TeacherAbsence>> getAbsences();
  Future<List<TeacherAbsence>> getAbsencesForDate(DateTime date);
  Future<void> saveAbsence(TeacherAbsence absence);
  Future<void> saveAbsences(List<TeacherAbsence> absences);
  Future<void> deleteAbsence(int id);
  Future<List<SubstitutionAssignment>> getSubstitutions();
  Future<void> saveSubstitution(SubstitutionAssignment assignment);
  Future<void> cancelSubstitution(int id);
}

class SchoolDataException implements Exception {
  const SchoolDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DuplicateSchoolRecordException implements Exception {
  const DuplicateSchoolRecordException(this.message);
  final String message;
  @override
  String toString() => message;
}

void validateSchoolPeriodConfiguration(List<SchoolPeriod> periods) {
  final ids = <int>{};
  final active = <SchoolPeriod>[];
  for (final period in periods) {
    if (period.id != null && !ids.add(period.id!)) {
      throw const DuplicateSchoolRecordException(
        'A period appears more than once in this schedule.',
      );
    }
    if (period.name.trim().isEmpty) {
      throw const SchoolDataException('Every period needs a name.');
    }
    if (period.startMinute < 0 ||
        period.endMinute > 1439 ||
        period.startMinute >= period.endMinute) {
      throw const SchoolDataException(
        'Enter valid period start and end times.',
      );
    }
    if (period.isActive) active.add(period);
  }
  active.sort((a, b) => a.startMinute.compareTo(b.startMinute));
  for (var index = 1; index < active.length; index++) {
    if (active[index].startMinute < active[index - 1].endMinute) {
      throw const DuplicateSchoolRecordException(
        'Active period times cannot overlap.',
      );
    }
  }
}

void validateTimetableEntryConflicts(
  Iterable<TimetableEntry> existingEntries,
  TimetableEntry candidate,
) {
  for (final existing in existingEntries) {
    if ((candidate.id != null && existing.id == candidate.id) ||
        existing.dayOfWeek != candidate.dayOfWeek ||
        existing.periodId != candidate.periodId) {
      continue;
    }
    final sameClassAndSection =
        existing.classId == candidate.classId &&
        (existing.sectionId == candidate.sectionId ||
            existing.sectionId == null ||
            candidate.sectionId == null);
    if (sameClassAndSection) {
      throw const DuplicateSchoolRecordException(
        'This class or section already has a lesson during that period.',
      );
    }
    if (existing.teacherId == candidate.teacherId) {
      throw const DuplicateSchoolRecordException(
        'This teacher is already assigned during that period.',
      );
    }
  }
}

void validateTimetableEntryEligibility({
  required TimetableEntry entry,
  required Teacher? teacher,
  required SchoolClass? schoolClass,
  required SchoolSection? section,
  required Subject? subject,
}) {
  if (teacher == null || !teacher.isActive) {
    throw const SchoolDataException('Choose an enabled teacher.');
  }
  if (schoolClass == null || !schoolClass.isActive) {
    throw const SchoolDataException('Choose an enabled class.');
  }
  if (entry.sectionId != null &&
      (section == null ||
          !section.isActive ||
          section.classId != entry.classId)) {
    throw const SchoolDataException(
      'Choose an enabled section for this class.',
    );
  }
  if (subject == null || !subject.isActive) {
    throw const SchoolDataException('Choose an enabled subject.');
  }
  if (schoolClass.subjectIds.isNotEmpty &&
      !schoolClass.subjectIds.contains(entry.subjectId)) {
    throw const SchoolDataException(
      'This subject is not enabled for the selected class.',
    );
  }
}

void validateAbsenceChangeAgainstAssignments(
  TeacherAbsence previous,
  TeacherAbsence? updated,
  Iterable<SubstitutionAssignment> assignments,
) {
  final removesAbsenceContext =
      updated == null ||
      updated.teacherId != previous.teacherId ||
      updated.dateKey != previous.dateKey;
  if (!removesAbsenceContext) return;

  final hasActiveAssignments = assignments.any(
    (assignment) =>
        assignment.status == SubstitutionStatus.assigned &&
        assignment.absentTeacherId == previous.teacherId &&
        assignment.dateKey == previous.dateKey,
  );
  if (hasActiveAssignments) {
    throw const SchoolDataException(
      'Cancel active substitute assignments for this teacher and date before changing or removing the absence.',
    );
  }
}
