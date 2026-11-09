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
