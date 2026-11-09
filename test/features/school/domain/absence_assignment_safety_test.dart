import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/features/school/data/school_database.dart';
import 'package:teacher_substitute/features/school/domain/school_models.dart';

TeacherAbsence absence({int teacherId = 4, DateTime? date}) => TeacherAbsence(
  id: 10,
  teacherId: teacherId,
  date: date ?? DateTime(2026, 11, 9),
  type: AbsenceType.absent,
  notes: '',
);

SubstitutionAssignment assignment({
  int teacherId = 4,
  SubstitutionStatus status = SubstitutionStatus.assigned,
}) => SubstitutionAssignment(
  id: 20,
  timetableEntryId: 30,
  absentTeacherId: teacherId,
  substituteTeacherId: 5,
  date: DateTime(2026, 11, 9),
  classId: 2,
  sectionId: null,
  subjectId: 3,
  periodId: 1,
  room: '',
  isOverride: false,
  status: status,
);

void main() {
  group('validateAbsenceChangeAgainstAssignments', () {
    test('blocks moving or removing an absence with active assignments', () {
      final old = absence();
      final active = [assignment()];
      expect(
        () => validateAbsenceChangeAgainstAssignments(
          old,
          absence(teacherId: 6),
          active,
        ),
        throwsA(isA<SchoolDataException>()),
      );
      expect(
        () => validateAbsenceChangeAgainstAssignments(old, null, active),
        throwsA(isA<SchoolDataException>()),
      );
    });

    test('allows note edits and changes after assignments are cancelled', () {
      final old = absence();
      expect(
        () => validateAbsenceChangeAgainstAssignments(old, absence(), [
          assignment(),
        ]),
        returnsNormally,
      );
      expect(
        () => validateAbsenceChangeAgainstAssignments(
          old,
          absence(teacherId: 6),
          [assignment(status: SubstitutionStatus.cancelled)],
        ),
        returnsNormally,
      );
    });
  });
}
