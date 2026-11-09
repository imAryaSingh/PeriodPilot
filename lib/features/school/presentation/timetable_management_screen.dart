import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/school_database.dart';
import '../domain/school_models.dart';

class TimetableManagementScreen extends StatefulWidget {
  const TimetableManagementScreen({super.key});

  @override
  State<TimetableManagementScreen> createState() =>
      _TimetableManagementScreenState();
}

class _TimetableManagementScreenState extends State<TimetableManagementScreen> {
  late Future<_TimetableData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_TimetableData> _load() async {
    final database = context.read<SchoolDatabase>();
    final values = await Future.wait<Object>([
      database.getPeriods(),
      database.getWorkingDays(),
      database.getClasses(),
      database.getTeachers(),
      database.getSubjects(),
      database.getTimetableEntries(),
    ]);
    final classes = values[2] as List<SchoolClass>;
    final sectionsByClass = await Future.wait(
      classes.map((schoolClass) => database.getSections(schoolClass.id)),
    );
    final sectionNames = <int, String>{};
    for (final sections in sectionsByClass) {
      for (final section in sections) {
        sectionNames[section.id] = section.name;
      }
    }
    return _TimetableData(
      periods: values[0] as List<SchoolPeriod>,
      workingDays: values[1] as List<int>,
      classes: classes,
      teachers: values[3] as List<Teacher>,
      subjects: values[4] as List<Subject>,
      entries: values[5] as List<TimetableEntry>,
      sectionNames: sectionNames,
    );
  }

  void _reload() {
    setState(() => _data = _load());
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Timetable management'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.schedule_rounded), text: 'Periods & days'),
            Tab(icon: Icon(Icons.view_week_rounded), text: 'Timetables'),
          ],
        ),
      ),
      body: FutureBuilder<_TimetableData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DataError(
              message: 'Could not load timetable data. ${snapshot.error}',
              onRetry: _reload,
            );
          }
          final data = snapshot.requireData;
          return TabBarView(
            children: [
              _PeriodsTab(data: data, onReload: _reload),
              _TimetablesTab(data: data, onReload: _reload),
            ],
          );
        },
      ),
    ),
  );
}

class _TimetableData {
  const _TimetableData({
    required this.periods,
    required this.workingDays,
    required this.classes,
    required this.teachers,
    required this.subjects,
    required this.entries,
    required this.sectionNames,
  });

  final List<SchoolPeriod> periods;
  final List<int> workingDays;
  final List<SchoolClass> classes;
  final List<Teacher> teachers;
  final List<Subject> subjects;
  final List<TimetableEntry> entries;
  final Map<int, String> sectionNames;
}

class _PeriodsTab extends StatefulWidget {
  const _PeriodsTab({required this.data, required this.onReload});

  final _TimetableData data;
  final VoidCallback onReload;

  @override
  State<_PeriodsTab> createState() => _PeriodsTabState();
}

class _PeriodsTabState extends State<_PeriodsTab> {
  late Set<int> _workingDays;
  bool _savingDays = false;

  @override
  void initState() {
    super.initState();
    _workingDays = widget.data.workingDays.toSet();
  }

  @override
  void didUpdateWidget(covariant _PeriodsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _workingDays = widget.data.workingDays.toSet();
    }
  }

  Future<void> _saveDays() async {
    setState(() => _savingDays = true);
    try {
      await context.read<SchoolDatabase>().saveWorkingDays(
        _workingDays.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Working days saved.')));
        widget.onReload();
      }
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _savingDays = false);
    }
  }

  Future<void> _editPeriod([SchoolPeriod? period]) async {
    final result = await showDialog<SchoolPeriod>(
      context: context,
      builder: (_) => _PeriodDialog(period: period),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<SchoolDatabase>().savePeriod(result);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _setActive(SchoolPeriod period, bool value) async {
    try {
      await context.read<SchoolDatabase>().setPeriodActive(period.id!, value);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PageIntro(
          title: 'School schedule',
          subtitle: 'Set your working days and the times used for each period.',
          action: FilledButton.icon(
            onPressed: () => _editPeriod(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add period'),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Working days', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Select at least one day when classes are held.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: schoolWeekdays.entries.map((day) {
                    return FilterChip(
                      label: Text(day.value.substring(0, 3)),
                      selected: _workingDays.contains(day.key),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _workingDays.add(day.key);
                        } else {
                          _workingDays.remove(day.key);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _savingDays || _workingDays.isEmpty
                        ? null
                        : _saveDays,
                    icon: _savingDays
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save working days'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Periods', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (widget.data.periods.isEmpty)
          const _EmptyPanel(
            icon: Icons.schedule_rounded,
            title: 'No periods configured',
            message: 'Add the school’s first period to start a timetable.',
          )
        else
          ...widget.data.periods.map((period) {
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text('${widget.data.periods.indexOf(period) + 1}'),
                ),
                title: Text(period.name),
                subtitle: Text(
                  '${_formatMinute(period.startMinute)} – ${_formatMinute(period.endMinute)}${period.isActive ? '' : ' · Inactive'}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Edit period',
                      onPressed: () => _editPeriod(period),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Switch(
                      value: period.isActive,
                      onChanged: (value) => _setActive(period, value),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({this.period});

  final SchoolPeriod? period;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.period?.name ?? '');
    _start = _timeFromMinute(widget.period?.startMinute ?? 8 * 60);
    _end = _timeFromMinute(widget.period?.endMinute ?? 8 * 60 + 45);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseTime(bool isStart) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (selected != null && mounted) {
      setState(() {
        if (isStart) {
          _start = selected;
        } else {
          _end = selected;
        }
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final start = _minuteFromTime(_start);
    final end = _minuteFromTime(_end);
    if (start >= end) {
      setState(
        () => _error = 'The end time must be later than the start time.',
      );
      return;
    }
    Navigator.pop(
      context,
      SchoolPeriod(
        id: widget.period?.id,
        name: _name.text.trim(),
        startMinute: start,
        endMinute: end,
        isActive: widget.period?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.period == null ? 'Add period' : 'Edit period'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Period name'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter a period name'
                  : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(true),
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_start.format(context)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _chooseTime(false),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(_end.format(context)),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save period')),
    ],
  );
}

enum _TimetableView { classView, teacherView }

class _TimetablesTab extends StatefulWidget {
  const _TimetablesTab({required this.data, required this.onReload});

  final _TimetableData data;
  final VoidCallback onReload;

  @override
  State<_TimetablesTab> createState() => _TimetablesTabState();
}

class _TimetablesTabState extends State<_TimetablesTab> {
  _TimetableView _view = _TimetableView.classView;
  int? _classId;
  int? _teacherId;
  int? _day;
  int _sectionId = 0;
  late Future<List<SchoolSection>> _sections;

  @override
  void initState() {
    super.initState();
    _classId = _firstActiveClass;
    _teacherId = _firstActiveTeacher;
    _day = _firstDay;
    _sections = _loadSections();
  }

  int? get _firstActiveClass {
    final classes = widget.data.classes;
    return classes.isEmpty ? null : classes.first.id;
  }

  int? get _firstActiveTeacher {
    final teachers = widget.data.teachers.where((teacher) => teacher.isActive);
    return teachers.isEmpty ? null : teachers.first.id;
  }

  int get _firstDay =>
      widget.data.workingDays.isEmpty ? 1 : widget.data.workingDays.first;

  @override
  void didUpdateWidget(covariant _TimetablesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      if (!widget.data.classes.any((item) => item.id == _classId)) {
        _classId = _firstActiveClass;
      }
      if (!widget.data.teachers.any((item) => item.id == _teacherId)) {
        _teacherId = _firstActiveTeacher;
      }
      if (!widget.data.workingDays.contains(_day)) _day = _firstDay;
      _sections = _loadSections();
    }
  }

  Future<List<SchoolSection>> _loadSections() async {
    if (_classId == null) return const [];
    return context.read<SchoolDatabase>().getSections(_classId!);
  }

  Future<void> _openEditor([TimetableEntry? entry]) async {
    final result = await showDialog<TimetableEntry>(
      context: context,
      builder: (_) => _TimetableEntryDialog(
        entry: entry,
        data: widget.data,
        initialClassId: _classId,
        initialTeacherId: _teacherId,
        initialDay: _day ?? _firstDay,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<SchoolDatabase>().saveTimetableEntry(result);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _delete(TimetableEntry entry) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove timetable entry?'),
        content: const Text('This will remove this lesson from the timetable.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep entry'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await context.read<SchoolDatabase>().deleteTimetableEntry(entry.id!);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final activePeriods = data.periods
        .where((period) => period.isActive)
        .toList();
    final activeTeachers = data.teachers
        .where((teacher) => teacher.isActive)
        .toList();
    final entries =
        data.entries.where((entry) {
            if (entry.dayOfWeek != _day) return false;
            if (_view == _TimetableView.teacherView) {
              return entry.teacherId == _teacherId;
            }
            if (entry.classId != _classId) return false;
            return _sectionId == 0 ||
                entry.sectionId == null ||
                entry.sectionId == _sectionId;
          }).toList()
          ..sort((a, b) => _periodOrder(a.periodId, b.periodId, activePeriods));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            children: [
              _PageIntro(
                title: 'Weekly timetable',
                subtitle: 'Assign a teacher and subject to each class period.',
                action: FilledButton.icon(
                  onPressed:
                      activePeriods.isEmpty ||
                          data.classes.isEmpty ||
                          activeTeachers.isEmpty ||
                          data.subjects
                              .where((subject) => subject.isActive)
                              .isEmpty
                      ? null
                      : () => _openEditor(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add lesson'),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<_TimetableView>(
                segments: const [
                  ButtonSegment(
                    value: _TimetableView.classView,
                    icon: Icon(Icons.class_outlined),
                    label: Text('By class'),
                  ),
                  ButtonSegment(
                    value: _TimetableView.teacherView,
                    icon: Icon(Icons.person_outline_rounded),
                    label: Text('By teacher'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (selection) =>
                    setState(() => _view = selection.first),
              ),
              const SizedBox(height: 12),
              if (_view == _TimetableView.classView)
                _classFilters(data)
              else
                _teacherFilter(activeTeachers),
              const SizedBox(height: 10),
              _daySelector(data.workingDays),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: activePeriods.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.schedule_rounded,
                  title: 'Add periods first',
                  message:
                      'Configure the school periods before adding lessons.',
                )
              : entries.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.event_note_outlined,
                  title: 'No lessons for this day',
                  message: 'Use Add lesson to build this timetable.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final period = _findById(activePeriods, entry.periodId);
                    final teacher = _findById(data.teachers, entry.teacherId);
                    final subject = _findById(data.subjects, entry.subjectId);
                    final schoolClass = _findById(data.classes, entry.classId);
                    final section = entry.sectionId == null
                        ? null
                        : data.sectionNames[entry.sectionId];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(subject?.name ?? 'Subject unavailable'),
                        subtitle: Text(
                          [
                            if (_view == _TimetableView.teacherView)
                              '${schoolClass?.name ?? 'Class'}${section == null ? '' : ' · $section'}',
                            if (_view == _TimetableView.classView)
                              teacher?.fullName ?? 'Teacher unavailable',
                            if (_view == _TimetableView.classView &&
                                section != null)
                              section,
                            if (entry.room.isNotEmpty) 'Room ${entry.room}',
                            if (period != null)
                              '${_formatMinute(period.startMinute)}–${_formatMinute(period.endMinute)}',
                          ].join(' · '),
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Edit lesson',
                              onPressed: () => _openEditor(entry),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remove lesson',
                              onPressed: () => _delete(entry),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _classFilters(_TimetableData data) {
    if (data.classes.isEmpty) {
      return const Text(
        'Add a class in School setup before creating a timetable.',
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int>(
            initialValue: _classId,
            decoration: const InputDecoration(labelText: 'Class'),
            items: data.classes
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _classId = value;
                _sectionId = 0;
                _sections = _loadSections();
              });
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: FutureBuilder<List<SchoolSection>>(
            future: _sections,
            builder: (context, snapshot) {
              final sections = snapshot.data ?? const <SchoolSection>[];
              return DropdownButtonFormField<int>(
                initialValue: _sectionId,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('All sections')),
                  ...sections.map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _sectionId = value ?? 0),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _teacherFilter(List<Teacher> teachers) {
    if (teachers.isEmpty) {
      return const Text(
        'Add an active teacher in School setup before creating a timetable.',
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 320,
        child: DropdownButtonFormField<int>(
          initialValue: _teacherId,
          decoration: const InputDecoration(labelText: 'Teacher'),
          items: teachers
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.fullName),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _teacherId = value),
        ),
      ),
    );
  }

  Widget _daySelector(List<int> days) {
    final available = days.isEmpty ? [1] : days;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: available.map((day) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(schoolWeekdays[day]!.substring(0, 3)),
              selected: _day == day,
              onSelected: (_) => setState(() => _day = day),
            ),
          );
        }).toList(),
      ),
    );
  }

  int _periodOrder(int firstId, int secondId, List<SchoolPeriod> periods) {
    final first = periods.indexWhere((period) => period.id == firstId);
    final second = periods.indexWhere((period) => period.id == secondId);
    if (first < 0 || second < 0) return firstId.compareTo(secondId);
    return periods[first].startMinute.compareTo(periods[second].startMinute);
  }
}

class _TimetableEntryDialog extends StatefulWidget {
  const _TimetableEntryDialog({
    required this.entry,
    required this.data,
    required this.initialClassId,
    required this.initialTeacherId,
    required this.initialDay,
  });

  final TimetableEntry? entry;
  final _TimetableData data;
  final int? initialClassId;
  final int? initialTeacherId;
  final int initialDay;

  @override
  State<_TimetableEntryDialog> createState() => _TimetableEntryDialogState();
}

class _TimetableEntryDialogState extends State<_TimetableEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _room = TextEditingController();
  late int? _classId;
  late int? _teacherId;
  late int? _subjectId;
  late int? _periodId;
  late int _day;
  late int _sectionId;
  late Future<List<SchoolSection>> _sections;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _classId = entry?.classId ?? widget.initialClassId;
    _teacherId = entry?.teacherId ?? widget.initialTeacherId;
    _subjectId = entry?.subjectId ?? _firstSubject;
    _periodId = entry?.periodId ?? _firstPeriod;
    _day = entry?.dayOfWeek ?? widget.initialDay;
    _sectionId = entry?.sectionId ?? 0;
    _room.text = entry?.room ?? '';
    _sections = _loadSections();
  }

  int? get _firstSubject {
    final subjects = widget.data.subjects.where((item) => item.isActive);
    return subjects.isEmpty ? null : subjects.first.id;
  }

  int? get _firstPeriod {
    final periods = widget.data.periods.where((item) => item.isActive);
    return periods.isEmpty ? null : periods.first.id;
  }

  Future<List<SchoolSection>> _loadSections() async {
    if (_classId == null) return const [];
    return context.read<SchoolDatabase>().getSections(_classId!);
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_classId == null ||
        _teacherId == null ||
        _subjectId == null ||
        _periodId == null) {
      setState(() => _error = 'Choose a class, teacher, subject, and period.');
      return;
    }
    Navigator.pop(
      context,
      TimetableEntry(
        id: widget.entry?.id,
        classId: _classId!,
        sectionId: _sectionId == 0 ? null : _sectionId,
        subjectId: _subjectId!,
        teacherId: _teacherId!,
        periodId: _periodId!,
        dayOfWeek: _day,
        room: _room.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classes = widget.data.classes;
    final teachers = widget.data.teachers
        .where((item) => item.isActive)
        .toList();
    final subjects = widget.data.subjects
        .where((item) => item.isActive)
        .toList();
    final periods = widget.data.periods.where((item) => item.isActive).toList();
    return AlertDialog(
      title: Text(
        widget.entry == null ? 'Add timetable lesson' : 'Edit lesson',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Class'),
                  items: classes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  validator: (value) => value == null ? 'Choose a class' : null,
                  onChanged: (value) => setState(() {
                    _classId = value;
                    _sectionId = 0;
                    _sections = _loadSections();
                  }),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<SchoolSection>>(
                  future: _sections,
                  builder: (context, snapshot) {
                    final sections = snapshot.data ?? const <SchoolSection>[];
                    return DropdownButtonFormField<int>(
                      initialValue: _sectionId,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Whole class'),
                        ),
                        ...sections.map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _sectionId = value ?? 0),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _subjectId,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: subjects
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a subject' : null,
                  onChanged: (value) => setState(() => _subjectId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _teacherId,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  items: teachers
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.fullName),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a teacher' : null,
                  onChanged: (value) => setState(() => _teacherId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _day,
                  decoration: const InputDecoration(labelText: 'Working day'),
                  items: widget.data.workingDays
                      .map(
                        (day) => DropdownMenuItem(
                          value: day,
                          child: Text(schoolWeekdays[day]!),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a working day' : null,
                  onChanged: (value) => setState(() => _day = value ?? 1),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _periodId,
                  decoration: const InputDecoration(labelText: 'Period'),
                  items: periods
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.name} · ${_formatMinute(item.startMinute)}–${_formatMinute(item.endMinute)}',
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose a period' : null,
                  onChanged: (value) => setState(() => _periodId = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _room,
                  decoration: const InputDecoration(
                    labelText: 'Room (optional)',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
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
        FilledButton(onPressed: _submit, child: const Text('Save lesson')),
      ],
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleContent, const SizedBox(height: 12), action],
        );
      }
      return Row(
        children: [
          Expanded(child: titleContent),
          const SizedBox(width: 16),
          action,
        ],
      );
    },
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

class _DataError extends StatelessWidget {
  const _DataError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

TimeOfDay _timeFromMinute(int minute) =>
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

int _minuteFromTime(TimeOfDay time) => time.hour * 60 + time.minute;

String _formatMinute(int minute) {
  final time = _timeFromMinute(minute);
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:${time.minute.toString().padLeft(2, '0')} $suffix';
}

T? _findById<T>(List<T> values, int id) {
  for (final value in values) {
    if (value is Teacher && value.id == id) return value;
    if (value is SchoolClass && value.id == id) return value;
    if (value is Subject && value.id == id) return value;
    if (value is SchoolPeriod && value.id == id) return value;
  }
  return null;
}

String _friendlyError(Object error) {
  if (error is SchoolDataException || error is DuplicateSchoolRecordException) {
    return error.toString();
  }
  return 'Could not save the timetable. Check the selections and try again.';
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
