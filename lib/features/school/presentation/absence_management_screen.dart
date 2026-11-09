import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/school_database.dart';
import '../domain/school_models.dart';

class AbsenceManagementScreen extends StatefulWidget {
  const AbsenceManagementScreen({super.key});

  @override
  State<AbsenceManagementScreen> createState() =>
      _AbsenceManagementScreenState();
}

class _AbsenceManagementScreenState extends State<AbsenceManagementScreen> {
  late Future<_AbsenceData> _data;
  DateTime _selectedDate = _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_AbsenceData> _load() async {
    final database = context.read<SchoolDatabase>();
    final values = await Future.wait<Object>([
      database.getTeachers(),
      database.getAbsences(),
      database.getTimetableEntries(),
      database.getPeriods(),
      database.getClasses(),
      database.getSubjects(),
    ]);
    final classes = values[4] as List<SchoolClass>;
    final sectionsByClass = await Future.wait(
      classes.map((schoolClass) => database.getSections(schoolClass.id)),
    );
    final sections = <int, String>{};
    for (final classSections in sectionsByClass) {
      for (final section in classSections) {
        sections[section.id] = section.name;
      }
    }
    return _AbsenceData(
      teachers: values[0] as List<Teacher>,
      absences: values[1] as List<TeacherAbsence>,
      entries: values[2] as List<TimetableEntry>,
      periods: values[3] as List<SchoolPeriod>,
      classes: classes,
      subjects: values[5] as List<Subject>,
      sectionNames: sections,
    );
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Choose absence date',
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = _dateOnly(selected));
    }
  }

  Future<void> _edit([TeacherAbsence? absence]) async {
    final data = await _data;
    if (!mounted) return;
    final result = await showDialog<TeacherAbsence>(
      context: context,
      builder: (_) => _AbsenceDialog(
        teachers: data.teachers,
        initialDate: absence?.date ?? _selectedDate,
        absence: absence,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<SchoolDatabase>().saveAbsence(result);
      setState(() {
        _selectedDate = _dateOnly(result.date);
        _data = _load();
      });
    } catch (error) {
      if (mounted) _showError(context, _friendlyError(error));
    }
  }

  Future<void> _delete(TeacherAbsence absence) async {
    final data = await _data;
    if (!mounted) return;
    final teacher = _findById(data.teachers, absence.teacherId);
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel absence record?'),
        content: Text(
          'Remove the ${absence.type.label.toLowerCase()} record for ${teacher?.fullName ?? 'this teacher'}? If substitute assignments are active for this date, cancel them first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep record'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel absence'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await context.read<SchoolDatabase>().deleteAbsence(absence.id!);
      _reload();
    } catch (error) {
      if (mounted) _showError(context, _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Absence management')),
    body: FutureBuilder<_AbsenceData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _LoadError(onRetry: _reload);
        }
        return _buildContent(snapshot.requireData);
      },
    ),
  );

  Widget _buildContent(_AbsenceData data) {
    final dateKey = schoolDateKey(_selectedDate);
    final daily = data.absences
        .where((absence) => absence.dateKey == dateKey)
        .toList();
    final affectedCount = daily.fold<int>(
      0,
      (total, absence) => total + _affectedLessons(data, absence).length,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily attendance',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Record teacher absences and review the lessons they affect.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: 'Previous day',
                  onPressed: () => setState(() {
                    _selectedDate = _selectedDate.subtract(
                      const Duration(days: 1),
                    );
                  }),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(_displayDate(_selectedDate)),
                ),
                IconButton.outlined(
                  tooltip: 'Next day',
                  onPressed: () => setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                  }),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                FilledButton.icon(
                  onPressed: data.teachers.any((teacher) => teacher.isActive)
                      ? () => _edit()
                      : null,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Mark absent'),
                ),
              ],
            );
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 14), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _SummaryRow(
          teachersAbsent: daily.length,
          affectedLessons: affectedCount,
        ),
        const SizedBox(height: 14),
        if (daily.isEmpty)
          const _EmptyState(
            icon: Icons.event_available_rounded,
            title: 'No absences recorded',
            message: 'Teachers marked absent for this date will appear here.',
          )
        else
          ...daily.map((absence) => _absenceCard(data, absence)),
      ],
    );
  }

  Widget _absenceCard(_AbsenceData data, TeacherAbsence absence) {
    final teacher = _findById(data.teachers, absence.teacherId);
    final lessons = _affectedLessons(data, absence);
    final color = absence.type == AbsenceType.leave
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.16),
          foregroundColor: color,
          child: Icon(
            absence.type == AbsenceType.leave
                ? Icons.event_busy_rounded
                : Icons.person_off_rounded,
          ),
        ),
        title: Text(teacher?.fullName ?? 'Teacher unavailable'),
        subtitle: Text(
          '${absence.type.label} · ${lessons.length} affected ${lessons.length == 1 ? 'lesson' : 'lessons'}${absence.notes.isEmpty ? '' : '\n${absence.notes}'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _edit(absence),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _delete(absence),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Cancel absence'),
                ),
              ],
            ),
          ),
          if (lessons.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('No timetable lessons are assigned for this day.'),
            )
          else
            ...lessons.map((lesson) => _AffectedLessonTile(lesson: lesson)),
        ],
      ),
    );
  }

  List<_LessonDetails> _affectedLessons(
    _AbsenceData data,
    TeacherAbsence absence,
  ) {
    final entries = data.entries
        .where(
          (entry) =>
              entry.teacherId == absence.teacherId &&
              entry.dayOfWeek == absence.date.weekday,
        )
        .toList();
    entries.sort(
      (a, b) => _periodOrder(
        data,
        a.periodId,
      ).compareTo(_periodOrder(data, b.periodId)),
    );
    return entries.map((entry) {
      final period = _findById(data.periods, entry.periodId);
      final schoolClass = _findById(data.classes, entry.classId);
      final subject = _findById(data.subjects, entry.subjectId);
      final section = entry.sectionId == null
          ? null
          : data.sectionNames[entry.sectionId];
      return _LessonDetails(
        period: period?.name ?? 'Period',
        time: period == null
            ? ''
            : '${_formatMinute(period.startMinute)}–${_formatMinute(period.endMinute)}',
        className: schoolClass?.name ?? 'Class',
        section: section,
        subject: subject?.name ?? 'Subject',
        room: entry.room,
      );
    }).toList();
  }

  int _periodOrder(_AbsenceData data, int periodId) =>
      _findById(data.periods, periodId)?.sortOrder ?? periodId;
}

class _AbsenceData {
  const _AbsenceData({
    required this.teachers,
    required this.absences,
    required this.entries,
    required this.periods,
    required this.classes,
    required this.subjects,
    required this.sectionNames,
  });

  final List<Teacher> teachers;
  final List<TeacherAbsence> absences;
  final List<TimetableEntry> entries;
  final List<SchoolPeriod> periods;
  final List<SchoolClass> classes;
  final List<Subject> subjects;
  final Map<int, String> sectionNames;
}

class _AbsenceDialog extends StatefulWidget {
  const _AbsenceDialog({
    required this.teachers,
    required this.initialDate,
    this.absence,
  });

  final List<Teacher> teachers;
  final DateTime initialDate;
  final TeacherAbsence? absence;

  @override
  State<_AbsenceDialog> createState() => _AbsenceDialogState();
}

class _AbsenceDialogState extends State<_AbsenceDialog> {
  final _formKey = GlobalKey<FormState>();
  late int? _teacherId;
  late DateTime _date;
  late AbsenceType _type;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _teacherId =
        widget.absence?.teacherId ??
        (widget.teachers.where((teacher) => teacher.isActive).isEmpty
            ? null
            : widget.teachers.firstWhere((teacher) => teacher.isActive).id);
    _date = _dateOnly(widget.absence?.date ?? widget.initialDate);
    _type = widget.absence?.type ?? AbsenceType.absent;
    _notes = TextEditingController(text: widget.absence?.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _date = _dateOnly(date));
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _teacherId == null) return;
    Navigator.pop(
      context,
      TeacherAbsence(
        id: widget.absence?.id,
        teacherId: _teacherId!,
        date: _date,
        type: _type,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teachers = widget.teachers
        .where((teacher) => teacher.isActive)
        .toList();
    if (widget.absence case final old?) {
      final oldTeacher = _findById(widget.teachers, old.teacherId);
      if (oldTeacher != null && !oldTeacher.isActive) teachers.add(oldTeacher);
    }
    return AlertDialog(
      title: Text(
        widget.absence == null ? 'Mark teacher absent' : 'Edit absence',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _teacherId,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  items: teachers
                      .map(
                        (teacher) => DropdownMenuItem(
                          value: teacher.id,
                          child: Text(teacher.fullName),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a teacher' : null,
                  onChanged: (value) => setState(() => _teacherId = value),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(_displayDate(_date)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AbsenceType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Record type'),
                  items: AbsenceType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    if (value != null) _type = value;
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save absence')),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.teachersAbsent,
    required this.affectedLessons,
  });

  final int teachersAbsent;
  final int affectedLessons;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _SummaryCard(
          label: 'Teachers absent',
          value: '$teachersAbsent',
          icon: Icons.person_off_outlined,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _SummaryCard(
          label: 'Affected lessons',
          value: '$affectedLessons',
          icon: Icons.event_busy_outlined,
        ),
      ),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LessonDetails {
  const _LessonDetails({
    required this.period,
    required this.time,
    required this.className,
    required this.section,
    required this.subject,
    required this.room,
  });

  final String period;
  final String time;
  final String className;
  final String? section;
  final String subject;
  final String room;
}

class _AffectedLessonTile extends StatelessWidget {
  const _AffectedLessonTile({required this.lesson});

  final _LessonDetails lesson;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: const Icon(Icons.schedule_rounded),
    title: Text(
      '${lesson.period}${lesson.time.isEmpty ? '' : ' · ${lesson.time}'}',
    ),
    subtitle: Text(
      '${lesson.className}${lesson.section == null ? '' : ' · ${lesson.section}'} · ${lesson.subject}${lesson.room.isEmpty ? '' : ' · Room ${lesson.room}'}',
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 42),
        const SizedBox(height: 10),
        const Text('Could not load absence records.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

T? _findById<T>(List<T> values, int id) {
  for (final value in values) {
    if (value is Teacher && value.id == id) return value;
    if (value is SchoolPeriod && value.id == id) return value;
    if (value is SchoolClass && value.id == id) return value;
    if (value is Subject && value.id == id) return value;
  }
  return null;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _displayDate(DateTime date) =>
    '${schoolWeekdays[date.weekday]}, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

TimeOfDay _timeFromMinute(int minute) =>
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

String _formatMinute(int minute) {
  final time = _timeFromMinute(minute);
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}

String _friendlyError(Object error) {
  if (error is SchoolDataException || error is DuplicateSchoolRecordException) {
    return error.toString();
  }
  return 'Could not save the absence. Check the details and try again.';
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
