import '../domain/school_models.dart';

abstract interface class SchoolDatabase {
  Future<SchoolProfile> getSchoolProfile();
  Future<void> saveSchoolProfile(SchoolProfile profile);
  Future<List<Teacher>> getTeachers();
  Future<void> saveTeacher(Teacher teacher);
  Future<void> setTeacherActive(int id, bool isActive);
  Future<List<SchoolClass>> getClasses();
  Future<List<SchoolSection>> getSections(int classId);
  Future<void> saveClass(SchoolClass schoolClass);
  Future<void> deleteClass(int id);
  Future<void> saveSection(SchoolSection section);
  Future<void> deleteSection(int id);
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
  Future<void> deleteTimetableEntry(int id);
  Future<List<TeacherAbsence>> getAbsences();
  Future<void> saveAbsence(TeacherAbsence absence);
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
