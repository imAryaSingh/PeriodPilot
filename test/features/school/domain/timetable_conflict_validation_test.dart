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
  group('validateTimetableEntryEligibility', () {
    final entry = lesson(classId: 1, sectionId: 2, teacherId: 3);
    const teacher = Teacher(
      id: 3,
      fullName: 'Teacher',
      staffCode: '',
      email: '',
      phone: '',
      isActive: true,
      subjectIds: [1],
    );
    const schoolClass = SchoolClass(id: 1, name: 'Class 1', subjectIds: [1]);
    const section = SchoolSection(id: 2, classId: 1, name: 'A');
    const subject = Subject(id: 1, name: 'Math', code: '', isActive: true);

    test('accepts enabled teacher, subject, class, and section links', () {
      expect(
        () => validateTimetableEntryEligibility(
          entry: entry,
          teacher: teacher,
          schoolClass: schoolClass,
          section: section,
          subject: subject,
        ),
        returnsNormally,
      );
    });

    test('rejects a teacher who is not assigned to the subject', () {
      expect(
        () => validateTimetableEntryEligibility(
          entry: entry,
          teacher: const Teacher(
            id: 3,
            fullName: 'Teacher',
            staffCode: '',
            email: '',
            phone: '',
            isActive: true,
          ),
          schoolClass: schoolClass,
          section: section,
          subject: subject,
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });

    test('rejects subjects disabled for the selected class', () {
      expect(
        () => validateTimetableEntryEligibility(
          entry: entry,
          teacher: teacher,
          schoolClass: const SchoolClass(
            id: 1,
            name: 'Class 1',
            subjectIds: [9],
          ),
          section: section,
          subject: subject,
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });
  });

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
