import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/school_database.dart';
import '../domain/school_models.dart';
import '../domain/substitute_suggestions.dart';

class SubstituteManagementScreen extends StatefulWidget {
  const SubstituteManagementScreen({super.key});
  @override
  State<SubstituteManagementScreen> createState() =>
      _SubstituteManagementScreenState();
}

class _SubstituteManagementScreenState
    extends State<SubstituteManagementScreen> {
  DateTime _date = DateTime.now();
  late Future<_AllocationData> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AllocationData> _load() async {
    final db = context.read<SchoolDatabase>();
    final values = await Future.wait<Object>([
      db.getTeachers(),
      db.getAbsences(),
      db.getTimetableEntries(),
      db.getPeriods(),
      db.getClasses(),
      db.getSubjects(),
      db.getSubstitutions(),
    ]);
    final classes = values[4] as List<SchoolClass>;
    final sectionGroups = await Future.wait(
      classes.map((c) => db.getSections(c.id)),
    );
    final sections = <int, String>{};
    for (final group in sectionGroups) {
      for (final section in group) {
        sections[section.id] = section.name;
      }
    }
    return _AllocationData(
      teachers: values[0] as List<Teacher>,
      absences: values[1] as List<TeacherAbsence>,
      entries: values[2] as List<TimetableEntry>,
      periods: values[3] as List<SchoolPeriod>,
      classes: classes,
      subjects: values[5] as List<Subject>,
      assignments: values[6] as List<SubstitutionAssignment>,
      sections: sections,
    );
  }

  void _reload() => setState(() => _future = _load());
  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _allocate(
    _AllocationData data,
    TimetableEntry lesson,
    TeacherAbsence absence, [
    SubstitutionAssignment? existing,
  ]) async {
    final suggestions = suggestSubstituteTeachers(
      teachers: data.teachers,
      timetable: data.entries,
      absences: data.absences,
      assignments: data.assignments,
      absentTeacherId: absence.teacherId,
      periodId: lesson.periodId,
      dayOfWeek: _date.weekday,
      date: _date,
      subjectId: lesson.subjectId,
      replacingAssignmentId: existing?.id,
    );
    if (suggestions.isEmpty) {
      _message('No active teachers are available to consider for this date.');
      return;
    }

    final selected = await showDialog<Teacher>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null ? 'Assign substitute' : 'Change substitute',
        ),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                '${_name(data.subjects, lesson.subjectId)} · ${_className(data, lesson)} · ${_periodName(data, lesson.periodId)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              for (final suggestion in suggestions)
                Builder(
                  builder: (context) {
                    final teacher = suggestion.teacher;
                    final detail = <String>[
                      if (suggestion.hasDutyConflict)
                        'Already assigned another duty in this period'
                      else if (suggestion.isOccupied)
                        'Regular class · administrator override required'
                      else if (suggestion.dutiesToday >=
                          defaultMaximumDailySubstitutions)
                        'Daily suggestion limit · administrator override required',
                      if (suggestion.hasSubjectExperience) 'Subject experience',
                      suggestion.dutiesToday == 0
                          ? 'No duties today'
                          : '${suggestion.dutiesToday} duties today',
                      if (suggestion.priorDuties > 0)
                        '${suggestion.priorDuties} prior assigned duties',
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      enabled: !suggestion.hasDutyConflict,
                      leading: CircleAvatar(
                        child: Text(
                          teacher.fullName.isEmpty
                              ? '?'
                              : teacher.fullName[0].toUpperCase(),
                        ),
                      ),
                      title: Text(teacher.fullName),
                      subtitle: Text(detail),
                      trailing: suggestion.hasDutyConflict
                          ? const Icon(Icons.block_outlined)
                          : Icon(
                              suggestion.requiresOverride
                                  ? Icons.warning_amber_rounded
                                  : Icons.add_circle_outline_rounded,
                            ),
                      onTap: suggestion.hasDutyConflict
                          ? null
                          : () async {
                              if (suggestion.requiresOverride) {
                                final confirm = await showDialog<bool>(
                                  context: dialogContext,
                                  builder: (confirmContext) => AlertDialog(
                                    title: const Text(
                                      'Confirm workload override?',
                                    ),
                                    content: Text(
                                      suggestion.isOccupied
                                          ? '${teacher.fullName} has a regular class during this period. Continue with an administrator override?'
                                          : '${teacher.fullName} already has ${suggestion.dutiesToday} substitution duties today. Continue with an administrator override?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          confirmContext,
                                          false,
                                        ),
                                        child: const Text('Choose another'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(confirmContext, true),
                                        child: const Text('Confirm override'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true || !dialogContext.mounted) {
                                  return;
                                }
                              }
                              Navigator.pop(dialogContext, teacher);
                            },
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    try {
      final selectedSuggestion = suggestions.firstWhere(
        (suggestion) => suggestion.teacher.id == selected.id,
      );
      await context.read<SchoolDatabase>().saveSubstitution(
        SubstitutionAssignment(
          id: existing?.id,
          timetableEntryId: lesson.id!,
          absentTeacherId: absence.teacherId,
          substituteTeacherId: selected.id!,
          date: _date,
          classId: lesson.classId,
          sectionId: lesson.sectionId,
          subjectId: lesson.subjectId,
          periodId: lesson.periodId,
          room: lesson.room,
          isOverride: selectedSuggestion.requiresOverride,
          status: SubstitutionStatus.assigned,
        ),
      );
      _reload();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _cancel(SubstitutionAssignment assignment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this assignment?'),
        content: const Text('The lesson will return to the unassigned list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel assignment'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await context.read<SchoolDatabase>().cancelSubstitution(assignment.id!);
        _reload();
      } catch (error) {
        _message('$error');
      }
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Substitute allocation')),
    body: FutureBuilder<_AllocationData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load allocation data: ${snapshot.error}'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        final data = snapshot.requireData;
        final absent = data.absences
            .where((a) => a.dateKey == schoolDateKey(_date))
            .toList();
        final assigned = data.assignments
            .where(
              (a) =>
                  a.dateKey == schoolDateKey(_date) &&
                  a.status == SubstitutionStatus.assigned,
            )
            .toList();
        final activeEntryIds = assigned.map((a) => a.timetableEntryId).toSet();
        final uncovered = <({TimetableEntry lesson, TeacherAbsence absence})>[];
        for (final absence in absent) {
          for (final lesson in data.entries.where(
            (e) =>
                e.teacherId == absence.teacherId &&
                e.dayOfWeek == _date.weekday &&
                !activeEntryIds.contains(e.id),
          )) {
            uncovered.add((lesson: lesson, absence: absence));
          }
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF244B70),
                    Color(0xFF183348),
                    Color(0xFF16413F),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    right: -34,
                    top: -58,
                    child: _HeroRing(size: 190),
                  ),
                  const Positioned(
                    right: 92,
                    bottom: -70,
                    child: _HeroRing(size: 140),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 16,
                      spacing: 20,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: Color(0xFF9BE4D8),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SUBSTITUTE DESK',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: const Color(0xFFBDE8E1),
                                          letterSpacing: 1.4,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Daily coverage',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Review suggested teachers and approve each assignment.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: .78,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: Text(_dateLabel(_date)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: .12,
                            ),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _metric(context, 'Absent', '${absent.length}'),
                _metric(context, 'Unassigned', '${uncovered.length}'),
                _metric(context, 'Assigned', '${assigned.length}'),
              ],
            ),
            const SizedBox(height: 20),
            if (absent.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No teachers are marked absent for this date. Add an absence first.',
                  ),
                ),
              ),
            if (uncovered.isNotEmpty) ...[
              Text(
                'Lessons needing coverage',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final item in uncovered)
                _lessonCard(
                  context,
                  data,
                  item.lesson,
                  item.absence,
                  null,
                  () => _allocate(data, item.lesson, item.absence),
                ),
            ],
            if (assigned.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Assigned duties',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final assignment in assigned) ...[
                _lessonCard(
                  context,
                  data,
                  data.entries
                          .where((e) => e.id == assignment.timetableEntryId)
                          .firstOrNull ??
                      TimetableEntry(
                        id: assignment.timetableEntryId,
                        classId: assignment.classId,
                        sectionId: assignment.sectionId,
                        subjectId: assignment.subjectId,
                        teacherId: assignment.absentTeacherId,
                        periodId: assignment.periodId,
                        dayOfWeek: _date.weekday,
                        room: assignment.room,
                      ),
                  TeacherAbsence(
                    id: null,
                    teacherId: assignment.absentTeacherId,
                    date: _date,
                    type: AbsenceType.absent,
                    notes: '',
                  ),
                  _teacherById(
                        data,
                        assignment.substituteTeacherId,
                      )?.fullName ??
                      'Unknown teacher',
                  () => _allocate(
                    data,
                    data.entries
                            .where((e) => e.id == assignment.timetableEntryId)
                            .firstOrNull ??
                        TimetableEntry(
                          id: assignment.timetableEntryId,
                          classId: assignment.classId,
                          sectionId: assignment.sectionId,
                          subjectId: assignment.subjectId,
                          teacherId: assignment.absentTeacherId,
                          periodId: assignment.periodId,
                          dayOfWeek: _date.weekday,
                          room: assignment.room,
                        ),
                    TeacherAbsence(
                      id: null,
                      teacherId: assignment.absentTeacherId,
                      date: _date,
                      type: AbsenceType.absent,
                      notes: '',
                    ),
                    assignment,
                  ),
                  onCancel: () => _cancel(assignment),
                ),
              ],
            ],
            if (uncovered.isEmpty && assigned.isEmpty && absent.isNotEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No timetable lessons need substitute coverage on this day.',
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _lessonCard(
    BuildContext context,
    _AllocationData data,
    TimetableEntry lesson,
    TeacherAbsence absence,
    Object? assignedTeacher,
    VoidCallback assign, {
    VoidCallback? onCancel,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            assignedTeacher == null
                ? Icons.assignment_late_outlined
                : Icons.assignment_turned_in_outlined,
            color: assignedTeacher == null
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_name(data.subjects, lesson.subjectId)} · ${_className(data, lesson)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_teacherName(data, absence.teacherId)} absent · ${_periodName(data, lesson.periodId)}${lesson.room.isNotEmpty ? ' · Room ${lesson.room}' : ''}',
                ),
                if (assignedTeacher != null)
                  Text(
                    'Substitute: $assignedTeacher',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (assignedTeacher == null)
            FilledButton.tonal(
              onPressed: assign,
              child: const Text('Review suggestions'),
            )
          else
            Wrap(
              children: [
                IconButton(
                  tooltip: 'Change substitute',
                  onPressed: assign,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Cancel assignment',
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _metric(BuildContext context, String label, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    ),
  );
}

class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: .075),
          width: 1.2,
        ),
      ),
    ),
  );
}

class _AllocationData {
  const _AllocationData({
    required this.teachers,
    required this.absences,
    required this.entries,
    required this.periods,
    required this.classes,
    required this.subjects,
    required this.assignments,
    required this.sections,
  });
  final List<Teacher> teachers;
  final List<TeacherAbsence> absences;
  final List<TimetableEntry> entries;
  final List<SchoolPeriod> periods;
  final List<SchoolClass> classes;
  final List<Subject> subjects;
  final List<SubstitutionAssignment> assignments;
  final Map<int, String> sections;
}

Teacher? _teacherById(_AllocationData d, int id) {
  for (final t in d.teachers) {
    if (t.id == id) return t;
  }
  return null;
}

String _teacherName(_AllocationData d, int id) =>
    _teacherById(d, id)?.fullName ?? 'Teacher';
String _name(List<Subject> values, int id) {
  for (final v in values) {
    if (v.id == id) return v.name;
  }
  return 'Subject';
}

String _className(_AllocationData d, TimetableEntry e) {
  final c =
      d.classes.where((v) => v.id == e.classId).firstOrNull?.name ?? 'Class';
  final s = e.sectionId == null ? null : d.sections[e.sectionId!];
  return s == null ? c : '$c · $s';
}

String _periodName(_AllocationData d, int id) {
  final p = d.periods.where((v) => v.id == id).firstOrNull;
  if (p == null) return 'Period';
  String time(int v) =>
      '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  return '${p.name} (${time(p.startMinute)}–${time(p.endMinute)})';
}

String _dateLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
