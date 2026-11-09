import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/features/school/data/school_database.dart';
import 'package:teacher_substitute/features/school/domain/school_models.dart';

TimetableEntry lesson({
  int? id,
  required int classId,
  int? sectionId,
  required int teacherId,
  int day = 1,
  int period = 1,
}) => TimetableEntry(
  id: id,
  classId: classId,
  sectionId: sectionId,
  subjectId: 1,
  teacherId: teacherId,
  periodId: period,
  dayOfWeek: day,
  room: '',
);

void main() {
  group('validateTimetableEntryConflicts', () {
    test('prevents a teacher from being assigned to two classes at once', () {
      expect(
        () => validateTimetableEntryConflicts([
          lesson(classId: 1, teacherId: 7),
        ], lesson(classId: 2, teacherId: 7)),
        throwsA(isA<DuplicateSchoolRecordException>()),
      );
    });

    test('prevents a whole-class lesson from overlapping a section lesson', () {
      expect(
        () => validateTimetableEntryConflicts([
          lesson(classId: 1, teacherId: 3),
        ], lesson(classId: 1, sectionId: 8, teacherId: 4)),
        throwsA(isA<DuplicateSchoolRecordException>()),
      );
    });

    test(
      'allows different sections with different teachers at the same time',
      () {
        expect(
          () => validateTimetableEntryConflicts([
            lesson(classId: 1, sectionId: 8, teacherId: 3),
          ], lesson(classId: 1, sectionId: 9, teacherId: 4)),
          returnsNormally,
        );
      },
    );

    test(
      'allows editing the same lesson and ignores different periods or days',
      () {
        expect(
          () => validateTimetableEntryConflicts([
            lesson(id: 10, classId: 1, teacherId: 3),
            lesson(classId: 2, teacherId: 4, day: 2),
            lesson(classId: 3, teacherId: 5, period: 2),
          ], lesson(id: 10, classId: 1, teacherId: 3)),
          returnsNormally,
        );
      },
    );
  });
}
