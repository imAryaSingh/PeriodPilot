import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/features/school/data/school_database.dart';
import 'package:teacher_substitute/features/school/domain/school_models.dart';

Teacher _teacher({String email = '', List<int> subjects = const []}) => Teacher(
  id: 4,
  fullName: 'Teacher',
  staffCode: '',
  email: email,
  phone: '',
  isActive: true,
  subjectIds: subjects,
);

TimetableEntry _entry({
  int teacherId = 4,
  int classId = 40,
  int subjectId = 9,
}) => TimetableEntry(
  id: 1,
  classId: classId,
  sectionId: null,
  subjectId: subjectId,
  teacherId: teacherId,
  periodId: 1,
  dayOfWeek: 1,
  room: '',
);

void main() {
  group('teacher deletion safety', () {
    test('allows an unlinked teacher with no history to be deleted', () {
      expect(
        () => validateTeacherCanBeDeleted(
          teacher: _teacher(),
          timetableEntries: const [],
          absences: const [],
          substitutions: const [],
        ),
        returnsNormally,
      );
    });

    test('keeps email-linked teachers so sign-in records are not orphaned', () {
      expect(
        () => validateTeacherCanBeDeleted(
          teacher: _teacher(email: 'teacher@school.edu'),
          timetableEntries: const [],
          absences: const [],
          substitutions: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });

    test('keeps teachers referenced by timetable entries', () {
      expect(
        () => validateTeacherCanBeDeleted(
          teacher: _teacher(),
          timetableEntries: [_entry()],
          absences: const [],
          substitutions: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });
  });

  group('class deletion safety', () {
    test('allows an unused custom class to be deleted', () {
      expect(
        () => validateClassCanBeDeleted(
          schoolClass: const SchoolClass(id: 40, name: 'Robotics'),
          timetableEntries: const [],
          substitutions: const [],
        ),
        returnsNormally,
      );
    });

    test('keeps predefined grades and classes with timetable entries', () {
      expect(
        () => validateClassCanBeDeleted(
          schoolClass: const SchoolClass(id: 1, name: 'Class 11'),
          timetableEntries: const [],
          substitutions: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
      expect(
        () => validateClassCanBeDeleted(
          schoolClass: const SchoolClass(id: 40, name: 'Robotics'),
          timetableEntries: [_entry(classId: 40)],
          substitutions: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });
  });

  group('subject deletion safety', () {
    test('allows a subject with no assignments or history to be deleted', () {
      expect(
        () => validateSubjectCanBeDeleted(
          subjectId: 9,
          timetableEntries: const [],
          substitutions: const [],
          teachers: const [],
          classes: const [],
        ),
        returnsNormally,
      );
    });

    test('keeps subjects referenced by teachers, classes, or timetable', () {
      expect(
        () => validateSubjectCanBeDeleted(
          subjectId: 9,
          timetableEntries: const [],
          substitutions: const [],
          teachers: [
            _teacher(subjects: [9]),
          ],
          classes: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
      expect(
        () => validateSubjectCanBeDeleted(
          subjectId: 9,
          timetableEntries: [_entry()],
          substitutions: const [],
          teachers: const [],
          classes: const [],
        ),
        throwsA(isA<SchoolDataException>()),
      );
    });
  });
}
