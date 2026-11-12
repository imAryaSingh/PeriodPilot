import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/features/school/domain/school_models.dart';
import 'package:teacher_substitute/features/school/domain/substitute_suggestions.dart';

Teacher teacher(
  int id, {
  bool active = true,
  List<int> subjectIds = const [],
}) => Teacher(
  id: id,
  fullName: 'Teacher $id',
  staffCode: '$id',
  email: '',
  phone: '',
  isActive: active,
  subjectIds: subjectIds,
);

TimetableEntry lesson({
  required int teacherId,
  required int subjectId,
  int day = 1,
  int period = 1,
  int classId = 1,
  int? sectionId,
}) => TimetableEntry(
  id: teacherId * 10 + period,
  classId: classId,
  sectionId: sectionId,
  subjectId: subjectId,
  teacherId: teacherId,
  periodId: period,
  dayOfWeek: day,
  room: '',
);

TeacherAbsence absence(int teacherId) => TeacherAbsence(
  id: teacherId,
  teacherId: teacherId,
  date: DateTime(2026, 11, 9),
  type: AbsenceType.absent,
  notes: '',
);

SubstitutionAssignment duty({
  required int id,
  required int teacherId,
  required DateTime date,
  int period = 1,
  SubstitutionStatus status = SubstitutionStatus.assigned,
}) => SubstitutionAssignment(
  id: id,
  timetableEntryId: id + 100,
  absentTeacherId: 99,
  substituteTeacherId: teacherId,
  date: date,
  classId: 1,
  sectionId: null,
  subjectId: 1,
  periodId: period,
  room: '',
  isOverride: false,
  status: status,
);

void main() {
  final date = DateTime(2026, 11, 9);

  test('ranks free, experienced teachers with lighter workloads first', () {
    final suggestions = suggestSubstituteTeachers(
      teachers: [teacher(1), teacher(2), teacher(3), teacher(4)],
      timetable: [
        lesson(teacherId: 1, subjectId: 8), // Occupied now.
        lesson(teacherId: 2, subjectId: 8, day: 2), // Subject experience.
        lesson(teacherId: 3, subjectId: 8, day: 2), // Subject experience.
      ],
      absences: [absence(99)],
      assignments: [
        duty(
          id: 11,
          teacherId: 3,
          date: date.subtract(const Duration(days: 1)),
        ),
      ],
      absentTeacherId: 99,
      periodId: 1,
      dayOfWeek: date.weekday,
      date: date,
      subjectId: 8,
    );

    expect(suggestions.map((item) => item.teacher.id), [2, 3, 4, 1]);
    expect(suggestions.first.hasSubjectExperience, isTrue);
    expect(suggestions.last.isOccupied, isTrue);
  });

  test(
    'excludes inactive, absent, and unavailable teachers from candidates',
    () {
      final suggestions = suggestSubstituteTeachers(
        teachers: [
          teacher(1, active: false),
          teacher(2),
          teacher(3),
          teacher(4),
        ],
        timetable: [lesson(teacherId: 4, subjectId: 8)],
        absences: [absence(99), absence(3)],
        assignments: [],
        absentTeacherId: 99,
        periodId: 1,
        dayOfWeek: date.weekday,
        date: date,
        subjectId: 8,
      );

      expect(suggestions.map((item) => item.teacher.id), [2, 4]);
    },
  );

  test('blocks duplicate period duties and marks workload overrides', () {
    final suggestions = suggestSubstituteTeachers(
      teachers: [teacher(1), teacher(2)],
      timetable: [],
      absences: [absence(99)],
      assignments: [
        duty(id: 11, teacherId: 1, date: date, period: 1),
        duty(id: 12, teacherId: 2, date: date, period: 2),
        duty(id: 13, teacherId: 2, date: date, period: 3),
      ],
      absentTeacherId: 99,
      periodId: 1,
      dayOfWeek: date.weekday,
      date: date,
      subjectId: 8,
    );

    final teacherOne = suggestions.firstWhere((item) => item.teacher.id == 1);
    final teacherTwo = suggestions.firstWhere((item) => item.teacher.id == 2);
    expect(teacherOne.hasDutyConflict, isTrue);
    expect(teacherTwo.dutiesToday, 2);
    expect(teacherTwo.requiresOverride, isTrue);
  });

  test('does not count canceled or replaced assignments toward workload', () {
    final suggestions = suggestSubstituteTeachers(
      teachers: [teacher(1)],
      timetable: [],
      absences: [absence(99)],
      assignments: [
        duty(
          id: 11,
          teacherId: 1,
          date: date,
          status: SubstitutionStatus.cancelled,
        ),
        duty(id: 12, teacherId: 1, date: date, period: 2),
      ],
      absentTeacherId: 99,
      periodId: 1,
      dayOfWeek: date.weekday,
      date: date,
      subjectId: 8,
      replacingAssignmentId: 12,
    );

    expect(suggestions.single.dutiesToday, 0);
    expect(suggestions.single.priorDuties, 0);
  });

  test('ranks subject-qualified teachers ahead of fallback candidates', () {
    final suggestions = suggestSubstituteTeachers(
      teachers: [
        teacher(1),
        teacher(2, subjectIds: [8]),
      ],
      timetable: [],
      absences: [absence(99)],
      assignments: [],
      absentTeacherId: 99,
      periodId: 1,
      dayOfWeek: date.weekday,
      date: date,
      subjectId: 8,
      classId: 4,
      sectionId: 2,
    );
    expect(suggestions.map((item) => item.teacher.id), [2, 1]);
    expect(suggestions.first.hasSubjectExperience, isTrue);
  });

  test('recognizes teachers with relevant class and section experience', () {
    final suggestions = suggestSubstituteTeachers(
      teachers: [teacher(1), teacher(2)],
      timetable: [
        lesson(teacherId: 2, subjectId: 8, classId: 4, sectionId: 2, day: 2),
      ],
      absences: [absence(99)],
      assignments: [],
      absentTeacherId: 99,
      periodId: 1,
      dayOfWeek: date.weekday,
      date: date,
      subjectId: 8,
      classId: 4,
      sectionId: 2,
    );
    final experienced = suggestions.firstWhere((item) => item.teacher.id == 2);
    expect(experienced.hasClassExperience, isTrue);
    expect(experienced.hasSectionExperience, isTrue);
    expect(experienced.hasSubjectExperience, isTrue);
  });
}
