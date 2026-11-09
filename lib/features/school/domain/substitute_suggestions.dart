import 'school_models.dart';

const int defaultMaximumDailySubstitutions = 2;

class SubstituteSuggestion {
  const SubstituteSuggestion({
    required this.teacher,
    required this.isOccupied,
    required this.hasDutyConflict,
    required this.dutiesToday,
    required this.priorDuties,
    required this.hasSubjectExperience,
  });

  final Teacher teacher;
  final bool isOccupied;
  final bool hasDutyConflict;
  final int dutiesToday;
  final int priorDuties;
  final bool hasSubjectExperience;

  bool get requiresOverride =>
      isOccupied || dutiesToday >= defaultMaximumDailySubstitutions;

  int get _rank =>
      (hasDutyConflict ? 20000 : 0) +
      (isOccupied ? 10000 : 0) +
      dutiesToday * 100 +
      priorDuties * 5 -
      (hasSubjectExperience ? 20 : 0);
}

List<SubstituteSuggestion> suggestSubstituteTeachers({
  required Iterable<Teacher> teachers,
  required Iterable<TimetableEntry> timetable,
  required Iterable<TeacherAbsence> absences,
  required Iterable<SubstitutionAssignment> assignments,
  required int absentTeacherId,
  required int periodId,
  required int dayOfWeek,
  required DateTime date,
  required int subjectId,
  int? replacingAssignmentId,
}) {
  final dateKey = schoolDateKey(date);
  final allTeachers = teachers.toList(growable: false);
  final lessons = timetable.toList(growable: false);
  final absenceRows = absences.toList(growable: false);
  final assignmentRows = assignments
      .where(
        (assignment) =>
            assignment.status == SubstitutionStatus.assigned &&
            assignment.id != replacingAssignmentId,
      )
      .toList(growable: false);
  final absentTeacherIds = absenceRows
      .where((absence) => absence.dateKey == dateKey)
      .map((absence) => absence.teacherId)
      .toSet();

  final suggestions = <SubstituteSuggestion>[];
  for (final teacher in allTeachers) {
    if (!teacher.isActive ||
        teacher.id == absentTeacherId ||
        absentTeacherIds.contains(teacher.id)) {
      continue;
    }
    final id = teacher.id;
    final isOccupied = lessons.any(
      (lesson) =>
          lesson.teacherId == id &&
          lesson.dayOfWeek == dayOfWeek &&
          lesson.periodId == periodId,
    );
    final teacherDutiesToday = assignmentRows.where(
      (assignment) =>
          assignment.substituteTeacherId == id && assignment.dateKey == dateKey,
    );
    final hasDutyConflict = teacherDutiesToday.any(
      (assignment) => assignment.periodId == periodId,
    );
    final priorDuties = assignmentRows
        .where(
          (assignment) =>
              assignment.substituteTeacherId == id &&
              assignment.dateKey.compareTo(dateKey) < 0,
        )
        .length;
    final hasSubjectExperience = lessons.any(
      (lesson) => lesson.teacherId == id && lesson.subjectId == subjectId,
    );
    suggestions.add(
      SubstituteSuggestion(
        teacher: teacher,
        isOccupied: isOccupied,
        hasDutyConflict: hasDutyConflict,
        dutiesToday: teacherDutiesToday.length,
        priorDuties: priorDuties,
        hasSubjectExperience: hasSubjectExperience,
      ),
    );
  }
  suggestions.sort((a, b) {
    final rank = a._rank.compareTo(b._rank);
    return rank != 0
        ? rank
        : a.teacher.fullName.toLowerCase().compareTo(
            b.teacher.fullName.toLowerCase(),
          );
  });
  return suggestions;
}
