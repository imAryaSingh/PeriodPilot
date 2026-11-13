import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/school_database.dart';
import '../domain/school_models.dart';
import 'school_management_screen.dart';

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
  bool _savingPeriods = false;
  int? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _workingDays = widget.data.workingDays.toSet();
    _selectedPreset = _presetForCount(
      widget.data.periods.where((period) => period.isActive).length,
    );
  }

  @override
  void didUpdateWidget(covariant _PeriodsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _workingDays = widget.data.workingDays.toSet();
      _selectedPreset = _presetForCount(
        widget.data.periods.where((period) => period.isActive).length,
      );
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
    final nextOrder = widget.data.periods.isEmpty
        ? 0
        : widget.data.periods
                  .map((item) => item.sortOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final result = await showDialog<SchoolPeriod>(
      context: context,
      builder: (_) => _PeriodDialog(period: period, sortOrder: nextOrder),
    );
    if (result == null || !mounted) return;
    if (period != null &&
        (result.startMinute != period.startMinute ||
            result.endMinute != period.endMinute)) {
      final lessonCount = widget.data.entries
          .where((entry) => entry.periodId == period.id)
          .length;
      if (lessonCount > 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Change a period used by lessons?'),
            content: Text(
              'This changes the time shown for $lessonCount timetable lesson${lessonCount == 1 ? '' : 's'} linked to ${period.name}. The lesson records will stay assigned to this period.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep current time'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Change time'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
    }
    try {
      await context.read<SchoolDatabase>().savePeriod(result);
      if (mounted) setState(() => _selectedPreset = null);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _setActive(SchoolPeriod period, bool value) async {
    try {
      await context.read<SchoolDatabase>().setPeriodActive(period.id!, value);
      if (mounted) setState(() => _selectedPreset = null);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _deletePeriod(SchoolPeriod period) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this period?'),
        content: const Text(
          'A period used by timetable lessons or substitution history cannot be deleted. Those records will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep period'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove period'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await context.read<SchoolDatabase>().deletePeriod(period.id!);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _reorderPeriods(int oldIndex, int newIndex) async {
    if (_savingPeriods || oldIndex == newIndex) return;
    final periods = [...widget.data.periods];
    final period = periods.removeAt(oldIndex);
    periods.insert(newIndex, period);
    final ordered = [
      for (var index = 0; index < periods.length; index++)
        _withPeriod(periods[index], sortOrder: index),
    ];
    setState(() => _savingPeriods = true);
    try {
      await context.read<SchoolDatabase>().savePeriodConfiguration(ordered);
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _savingPeriods = false);
    }
  }

  Future<void> _configurePreset(int count) async {
    final active = widget.data.periods.where((p) => p.isActive).toList();
    final initialStart = active.isEmpty ? 8 * 60 : active.first.startMinute;
    final initialDuration = active.isEmpty
        ? 45
        : (active.first.endMinute - active.first.startMinute)
              .clamp(20, 120)
              .toInt();
    final options = await showDialog<_ScheduleOptions>(
      context: context,
      builder: (_) => _ScheduleGeneratorDialog(
        periodCount: count,
        initialStart: initialStart,
        initialDuration: initialDuration,
      ),
    );
    if (options == null || !mounted) return;

    try {
      final existingActive = widget.data.periods
          .where((period) => period.isActive)
          .toList();
      final configured = <SchoolPeriod>[];
      var cursor = options.startMinute;
      for (var index = 0; index < count; index++) {
        final start = cursor;
        final end = start + options.periodDuration;
        if (end > 1439) {
          throw const SchoolDataException(
            'These settings place a period past the end of the day. Choose an earlier start time or shorter periods/breaks.',
          );
        }
        configured.add(
          SchoolPeriod(
            id: index < existingActive.length ? existingActive[index].id : null,
            name: 'Period ${index + 1}',
            startMinute: start,
            endMinute: end,
            isActive: true,
            sortOrder: index,
          ),
        );
        cursor = end;
        if (options.breakAfter == index + 1) {
          cursor += options.breakDuration;
        }
        if (options.lunchAfter == index + 1) {
          cursor += options.lunchDuration;
        }
      }

      final retainedExtra = <SchoolPeriod>[];
      final inactiveExisting = <SchoolPeriod>[];
      for (final extra in existingActive.skip(count)) {
        final hasLessons = widget.data.entries.any(
          (entry) => entry.periodId == extra.id,
        );
        if (hasLessons) {
          final duration = extra.endMinute - extra.startMinute;
          final start = cursor == 1439 ? cursor : cursor + 5;
          final end = start + duration;
          if (end > 1439) {
            throw SchoolDataException(
              '${extra.name} has existing timetable lessons and cannot fit after the generated $count periods. Adjust the generated times to leave room for it.',
            );
          }
          retainedExtra.add(
            SchoolPeriod(
              id: extra.id,
              name: extra.name,
              startMinute: start,
              endMinute: end,
              isActive: true,
              sortOrder: count + retainedExtra.length,
            ),
          );
          cursor = end;
        } else {
          inactiveExisting.add(_withPeriod(extra, isActive: false));
        }
      }
      final otherInactive = widget.data.periods
          .where((period) => !period.isActive)
          .toList();
      final configuration = [
        ...configured,
        ...retainedExtra,
        ...inactiveExisting,
        ...otherInactive,
      ];
      final ordered = [
        for (var index = 0; index < configuration.length; index++)
          _withPeriod(configuration[index], sortOrder: index),
      ];
      final changesExistingLessons = widget.data.entries.where((entry) {
        final old = widget.data.periods
            .where((period) => period.id == entry.periodId)
            .firstOrNull;
        final next = ordered
            .where((period) => period.id == entry.periodId)
            .firstOrNull;
        return old == null ||
            next == null ||
            !next.isActive ||
            old.startMinute != next.startMinute ||
            old.endMinute != next.endMinute;
      }).length;
      if (changesExistingLessons > 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Apply this period schedule?'),
            content: Text(
              'This changes the timing of periods used by $changesExistingLessons existing timetable lesson${changesExistingLessons == 1 ? '' : 's'}. Lesson records stay linked to their existing period IDs. Extra periods with lessons will be kept active after the generated schedule; unused extra periods will be deactivated. No lesson records will be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Review settings'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply schedule'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }

      setState(() => _savingPeriods = true);
      await context.read<SchoolDatabase>().savePeriodConfiguration(ordered);
      if (!mounted) return;
      setState(() => _selectedPreset = count);
      final extraCount = retainedExtra.length;
      _showMessage(
        context,
        extraCount == 0
            ? '$count periods configured.'
            : '$count periods configured. $extraCount additional period${extraCount == 1 ? '' : 's'} with lessons kept active.',
      );
      widget.onReload();
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _savingPeriods = false);
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
        Text(
          'Choose a starting schedule, then adjust individual periods as needed.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final count in [6, 7, 8])
              ChoiceChip(
                label: Text('$count periods'),
                selected: _selectedPreset == count,
                onSelected: _savingPeriods
                    ? null
                    : (_) => _configurePreset(count),
              ),
            ChoiceChip(
              label: const Text('Custom / manual'),
              selected: _selectedPreset == null,
              onSelected: _savingPeriods
                  ? null
                  : (_) => setState(() => _selectedPreset = null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.data.periods.isEmpty)
          const _EmptyPanel(
            icon: Icons.schedule_rounded,
            title: 'No periods configured',
            message: 'Add the school’s first period to start a timetable.',
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: widget.data.periods.length,
            onReorderItem: _reorderPeriods,
            itemBuilder: (context, index) {
              final period = widget.data.periods[index];
              return Card(
                key: ValueKey('school-period-${period.id}'),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(period.name),
                  subtitle: Text(
                    '${_formatMinute(period.startMinute)} – ${_formatMinute(period.endMinute)}${period.isActive ? '' : ' · Inactive'}',
                  ),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_indicator_rounded),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit period',
                        onPressed: _savingPeriods
                            ? null
                            : () => _editPeriod(period),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Remove unused period',
                        onPressed: _savingPeriods
                            ? null
                            : () => _deletePeriod(period),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      Switch(
                        value: period.isActive,
                        onChanged: _savingPeriods
                            ? null
                            : (value) => _setActive(period, value),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({this.period, required this.sortOrder});

  final SchoolPeriod? period;
  final int sortOrder;

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
        sortOrder: widget.period?.sortOrder ?? widget.sortOrder,
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

int? _presetForCount(int count) => [6, 7, 8].contains(count) ? count : null;

SchoolPeriod _withPeriod(
  SchoolPeriod period, {
  int? sortOrder,
  bool? isActive,
}) => SchoolPeriod(
  id: period.id,
  name: period.name,
  startMinute: period.startMinute,
  endMinute: period.endMinute,
  isActive: isActive ?? period.isActive,
  sortOrder: sortOrder ?? period.sortOrder,
);

class _ScheduleOptions {
  const _ScheduleOptions({
    required this.startMinute,
    required this.periodDuration,
    required this.breakAfter,
    required this.breakDuration,
    required this.lunchAfter,
    required this.lunchDuration,
  });

  final int startMinute;
  final int periodDuration;
  final int? breakAfter;
  final int breakDuration;
  final int? lunchAfter;
  final int lunchDuration;
}

class _ScheduleGeneratorDialog extends StatefulWidget {
  const _ScheduleGeneratorDialog({
    required this.periodCount,
    required this.initialStart,
    required this.initialDuration,
  });

  final int periodCount;
  final int initialStart;
  final int initialDuration;

  @override
  State<_ScheduleGeneratorDialog> createState() =>
      _ScheduleGeneratorDialogState();
}

class _ScheduleGeneratorDialogState extends State<_ScheduleGeneratorDialog> {
  late TimeOfDay _start;
  late int _duration;
  bool _includeBreak = true;
  int _breakAfter = 3;
  int _breakDuration = 15;
  bool _includeLunch = false;
  int _lunchAfter = 5;
  int _lunchDuration = 40;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = _timeFromMinute(widget.initialStart);
    _duration = widget.initialDuration;
    _breakAfter = (widget.periodCount ~/ 2).clamp(1, widget.periodCount - 1);
    _lunchAfter = (widget.periodCount - 1).clamp(1, widget.periodCount - 1);
  }

  Future<void> _chooseStart() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _start,
    );
    if (selected != null && mounted) setState(() => _start = selected);
  }

  void _submit() {
    if (_includeBreak && _includeLunch && _breakAfter == _lunchAfter) {
      setState(
        () => _error = 'Place the break and lunch after different periods.',
      );
      return;
    }
    Navigator.pop(
      context,
      _ScheduleOptions(
        startMinute: _minuteFromTime(_start),
        periodDuration: _duration,
        breakAfter: _includeBreak ? _breakAfter : null,
        breakDuration: _breakDuration,
        lunchAfter: _includeLunch ? _lunchAfter : null,
        lunchDuration: _lunchDuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insertionPoints = List.generate(widget.periodCount - 1, (i) => i + 1);
    return AlertDialog(
      title: Text('Configure ${widget.periodCount} periods'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _chooseStart,
                icon: const Icon(Icons.access_time_rounded),
                label: Text('School starts at ${_start.format(context)}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(
                  labelText: 'Minutes per period',
                ),
                items: [30, 35, 40, 45, 50, 55, 60, 75, 90, 120]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value minutes'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _duration = value ?? _duration),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add a short break'),
                value: _includeBreak,
                onChanged: (value) => setState(() => _includeBreak = value),
              ),
              if (_includeBreak) ...[
                _insertionSelector(
                  'Break after period',
                  _breakAfter,
                  insertionPoints,
                  (v) => setState(() => _breakAfter = v),
                ),
                _durationSelector('Break length', _breakDuration, [
                  5,
                  10,
                  15,
                  20,
                  25,
                  30,
                ], (v) => setState(() => _breakDuration = v)),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add a lunch interval'),
                value: _includeLunch,
                onChanged: (value) => setState(() => _includeLunch = value),
              ),
              if (_includeLunch) ...[
                _insertionSelector(
                  'Lunch after period',
                  _lunchAfter,
                  insertionPoints,
                  (v) => setState(() => _lunchAfter = v),
                ),
                _durationSelector('Lunch length', _lunchDuration, [
                  20,
                  25,
                  30,
                  35,
                  40,
                  45,
                  50,
                  60,
                ], (v) => setState(() => _lunchDuration = v)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
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
        FilledButton(
          onPressed: _submit,
          child: const Text('Generate schedule'),
        ),
      ],
    );
  }

  Widget _insertionSelector(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    initialValue: values.contains(value) ? value : values.first,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((n) => DropdownMenuItem(value: n, child: Text('After period $n')))
        .toList(),
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
  );

  Widget _durationSelector(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    initialValue: values.contains(value) ? value : values.first,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((n) => DropdownMenuItem(value: n, child: Text('$n minutes')))
        .toList(),
    onChanged: (selected) {
      if (selected != null) onChanged(selected);
    },
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
  late Set<int> _selectedDays;
  late int _activeDay;
  int _sectionId = 0;
  late Future<List<SchoolSection>> _sections;

  @override
  void initState() {
    super.initState();
    _classId = _firstActiveClass;
    _teacherId = _firstActiveTeacher;
    _selectedDays = {_firstDay};
    _activeDay = _firstDay;
    _sections = _loadSections();
  }

  int? get _firstActiveClass {
    final classes = widget.data.classes.where((item) => item.isActive);
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
      if (!widget.data.classes.any(
        (item) => item.id == _classId && item.isActive,
      )) {
        _classId = _firstActiveClass;
      }
      if (!widget.data.teachers.any((item) => item.id == _teacherId)) {
        _teacherId = _firstActiveTeacher;
      }
      _selectedDays.removeWhere(
        (day) => !widget.data.workingDays.contains(day),
      );
      if (_selectedDays.isEmpty) _selectedDays = {_firstDay};
      if (!_selectedDays.contains(_activeDay)) _activeDay = _selectedDays.first;
      _sections = _loadSections();
    }
  }

  Future<List<SchoolSection>> _loadSections() async {
    if (_classId == null) return const [];
    return context.read<SchoolDatabase>().getSections(_classId!);
  }

  Future<void> _openEditor({
    TimetableEntry? entry,
    int? periodId,
    Set<int>? initialDays,
  }) async {
    final result = await showDialog<List<TimetableEntry>>(
      context: context,
      builder: (_) => _TimetableEntryDialog(
        entry: entry,
        data: widget.data,
        initialClassId: _view == _TimetableView.classView ? _classId : null,
        initialTeacherId: _teacherId,
        initialDay: _activeDay,
        initialDays: initialDays ?? {entry?.dayOfWeek ?? _activeDay},
        initialPeriodId: periodId,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final candidates = await _prepareEntriesForSave(result);
      if (candidates == null || !mounted) return;
      await context.read<SchoolDatabase>().saveTimetableEntries(candidates);
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

  List<int> get _daysForDisplay => _selectedDays.toList()..sort();

  Future<void> _copyActiveDayPattern(_TimetableData data) async {
    final targets = _daysForDisplay.where((day) => day != _activeDay).toList();
    final source = data.entries.where((entry) {
      if (entry.dayOfWeek != _activeDay) return false;
      if (_view == _TimetableView.teacherView) {
        return entry.teacherId == _teacherId;
      }
      return entry.classId == _classId &&
          (_sectionId == 0 ||
              entry.sectionId == null ||
              entry.sectionId == _sectionId);
    }).toList();
    if (targets.isEmpty || source.isEmpty) {
      _showMessage(context, 'The active day has no timetable pattern to copy.');
      return;
    }
    final copies = [
      for (final day in targets)
        for (final entry in source)
          TimetableEntry(
            id: null,
            classId: entry.classId,
            sectionId: entry.sectionId,
            subjectId: entry.subjectId,
            teacherId: entry.teacherId,
            periodId: entry.periodId,
            dayOfWeek: day,
            room: entry.room,
          ),
    ];
    try {
      final candidates = await _prepareEntriesForSave(copies);
      if (candidates == null || !mounted) return;
      await context.read<SchoolDatabase>().saveTimetableEntries(candidates);
      widget.onReload();
      if (mounted) _showMessage(context, 'Timetable pattern copied.');
    } catch (error) {
      if (mounted) _showMessage(context, _friendlyError(error));
    }
  }

  Future<List<TimetableEntry>?> _prepareEntriesForSave(
    List<TimetableEntry> entries,
  ) async {
    final existing = widget.data.entries;
    final candidates = <TimetableEntry>[];
    var replacementCount = 0;
    for (final entry in entries) {
      final colliding = existing.where((item) {
        if (item.id == entry.id ||
            item.dayOfWeek != entry.dayOfWeek ||
            item.periodId != entry.periodId) {
          return false;
        }
        final sameClassSlot =
            item.classId == entry.classId &&
            (item.sectionId == entry.sectionId ||
                item.sectionId == null ||
                entry.sectionId == null);
        return sameClassSlot || item.teacherId == entry.teacherId;
      }).toList();
      final exactSlot = colliding.where(
        (item) =>
            item.classId == entry.classId && item.sectionId == entry.sectionId,
      );
      final replaceable = exactSlot.length == 1 ? exactSlot.first : null;
      final nonReplaceable = colliding
          .where((item) => item.id != replaceable?.id)
          .toList();
      if (nonReplaceable.isNotEmpty || exactSlot.length > 1) {
        _showMessage(
          context,
          'This period conflicts with another class or teacher assignment. Edit that lesson first.',
        );
        return null;
      }
      if (replaceable != null) {
        replacementCount++;
        candidates.add(_withTimetableId(entry, replaceable.id!));
      } else {
        candidates.add(entry);
      }
    }
    if (replacementCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update existing timetable entries?'),
          content: Text(
            '$replacementCount selected day/period slot(s) already have a lesson. Replace those entries with the selected configuration?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update entries'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return null;
    }
    if (!mounted) return null;
    return candidates;
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
    final chosenTeacher =
        data.teachers.any((teacher) => teacher.id == _teacherId)
        ? data.teachers.firstWhere((teacher) => teacher.id == _teacherId)
        : null;
    final hasLessonOptions =
        chosenTeacher != null &&
        data.classes
            .where((item) => item.isActive)
            .any(
              (schoolClass) => data.subjects.any(
                (subject) =>
                    subject.isActive &&
                    (schoolClass.subjectIds.isEmpty ||
                        schoolClass.subjectIds.contains(subject.id)),
              ),
            );
    final entries =
        data.entries.where((entry) {
            if (!_selectedDays.contains(entry.dayOfWeek)) return false;
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
                          !data.classes.any((item) => item.isActive) ||
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
              if (_selectedDays.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<int>(
                    value: _selectedDays.contains(_activeDay)
                        ? _activeDay
                        : _selectedDays.first,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    hint: const Text('Choose source day'),
                    items: _daysForDisplay
                        .map(
                          (day) => DropdownMenuItem(
                            value: day,
                            child: Text(
                              'Copy pattern from ${schoolWeekdays[day]}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (day) {
                      if (day != null) setState(() => _activeDay = day);
                    },
                  ),
                ),
              if (_selectedDays.length > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _copyActiveDayPattern(data),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: Text(
                      'Copy ${schoolWeekdays[_activeDay]} pattern to selected days',
                    ),
                  ),
                ),
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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  itemCount: activePeriods.length * _daysForDisplay.length,
                  itemBuilder: (context, index) {
                    final displayDays = _daysForDisplay;
                    final day = displayDays[index ~/ activePeriods.length];
                    final period = activePeriods[index % activePeriods.length];
                    final lessons = entries
                        .where(
                          (entry) =>
                              entry.dayOfWeek == day &&
                              entry.periodId == period.id,
                        )
                        .toList();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                child: Text(
                                  '${index % activePeriods.length + 1}',
                                ),
                              ),
                              title: Text(
                                '${schoolWeekdays[day]} · ${period.name}',
                              ),
                              subtitle: Text(
                                '${_formatMinute(period.startMinute)} – ${_formatMinute(period.endMinute)}',
                              ),
                              trailing: lessons.isEmpty
                                  ? const Chip(label: Text('Free period'))
                                  : null,
                            ),
                            if (lessons.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  60,
                                  0,
                                  12,
                                  4,
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.add_circle_outline),
                                  title: Text(
                                    hasLessonOptions
                                        ? _view == _TimetableView.teacherView
                                              ? 'Assign class and subject'
                                              : 'Assign subject and teacher'
                                        : 'Complete school setup first',
                                  ),
                                  subtitle: Text(
                                    hasLessonOptions
                                        ? _view == _TimetableView.teacherView
                                              ? 'Tap to add a lesson for this teacher.'
                                              : 'Tap to assign this class period.'
                                        : 'Add an active class and at least one active class subject before assigning lessons.',
                                  ),
                                  onTap: hasLessonOptions
                                      ? () => _openEditor(
                                          periodId: period.id,
                                          initialDays: {day},
                                        )
                                      : null,
                                ),
                              )
                            else if (lessons.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  72,
                                  0,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  'No lesson assigned during this period.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              )
                            else
                              ...lessons.map(
                                (entry) => _lessonTile(entry, data),
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

  Widget _lessonTile(TimetableEntry entry, _TimetableData data) {
    final teacher = _findById(data.teachers, entry.teacherId);
    final subject = _findById(data.subjects, entry.subjectId);
    final schoolClass = _findById(data.classes, entry.classId);
    final needsCorrection =
        teacher == null ||
        !teacher.isActive ||
        subject == null ||
        !subject.isActive ||
        schoolClass == null ||
        !schoolClass.isActive ||
        (schoolClass.subjectIds.isNotEmpty &&
            !schoolClass.subjectIds.contains(entry.subjectId));
    final section = entry.sectionId == null
        ? null
        : data.sectionNames[entry.sectionId];
    final details = <String>[
      if (_view == _TimetableView.teacherView)
        '${schoolClass?.name ?? 'Class'}${section == null ? '' : ' · $section'}',
      if (_view == _TimetableView.classView)
        teacher?.fullName ?? 'Teacher unavailable',
      if (teacher != null && !teacher.subjectIds.contains(entry.subjectId))
        'Subject fallback',
      if (_view == _TimetableView.classView && section != null) section,
      if (entry.room.isNotEmpty) 'Room ${entry.room}',
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 72, right: 12),
      title: Text(subject?.name ?? 'Subject unavailable'),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Wrap(
        children: [
          if (needsCorrection)
            const Padding(
              padding: EdgeInsets.only(top: 10, right: 4),
              child: Chip(
                avatar: Icon(Icons.warning_amber_rounded, size: 16),
                label: Text('Needs correction'),
              ),
            ),
          IconButton(
            tooltip: 'Edit lesson',
            onPressed: () => _openEditor(entry: entry),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Remove lesson',
            onPressed: () => _delete(entry),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _classFilters(_TimetableData data) {
    final activeClasses = data.classes.where((item) => item.isActive).toList();
    if (activeClasses.isEmpty) {
      return const Text(
        'Add a class in School setup before creating a timetable.',
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _classId,
            decoration: const InputDecoration(labelText: 'Class'),
            items: activeClasses
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
        const SizedBox(width: 12),
        Expanded(
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
    final available = days.isEmpty ? [1] : days.toSet().toList()
      ..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            available.map((day) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(schoolWeekdays[day]!.substring(0, 3)),
                  selected: _selectedDays.contains(day),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedDays.add(day);
                      _activeDay = day;
                    } else if (_selectedDays.length > 1) {
                      _selectedDays.remove(day);
                      if (_activeDay == day) _activeDay = _selectedDays.first;
                    }
                  }),
                ),
              );
            }).toList()..add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: const Text('All days'),
                  onPressed: () => setState(() {
                    _selectedDays = available.toSet();
                    _activeDay = available.first;
                  }),
                ),
              ),
            ),
      ),
    );
  }

  int _periodOrder(int firstId, int secondId, List<SchoolPeriod> periods) {
    final first = periods.indexWhere((period) => period.id == firstId);
    final second = periods.indexWhere((period) => period.id == secondId);
    if (first < 0 || second < 0) return firstId.compareTo(secondId);
    return periods[first].sortOrder.compareTo(periods[second].sortOrder);
  }
}

class _TimetableEntryDialog extends StatefulWidget {
  const _TimetableEntryDialog({
    required this.entry,
    required this.data,
    required this.initialClassId,
    required this.initialTeacherId,
    required this.initialDay,
    required this.initialDays,
    required this.initialPeriodId,
  });

  final TimetableEntry? entry;
  final _TimetableData data;
  final int? initialClassId;
  final int? initialTeacherId;
  final int initialDay;
  final Set<int> initialDays;
  final int? initialPeriodId;

  @override
  State<_TimetableEntryDialog> createState() => _TimetableEntryDialogState();
}

class _TimetableEntryDialogState extends State<_TimetableEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _room = TextEditingController();
  late int? _classId;
  late int? _teacherId;
  int? _subjectId;
  late int? _periodId;
  late Set<int> _days;
  late int _sectionId;
  late Future<List<SchoolSection>> _sections;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _classId = entry?.classId ?? widget.initialClassId;
    _teacherId = entry?.teacherId ?? widget.initialTeacherId;
    _periodId = entry?.periodId ?? widget.initialPeriodId ?? _firstPeriod;
    _subjectId = entry?.subjectId ?? _firstSubject;
    _days = entry == null ? widget.initialDays.toSet() : {entry.dayOfWeek};
    if (_days.isEmpty) _days = {widget.initialDay};
    _sectionId = entry?.sectionId ?? 0;
    _room.text = entry?.room ?? '';
    _sections = _loadSections();
  }

  List<Subject> get _teacherSubjects {
    final selectedClass = firstOrNull(
      widget.data.classes.where((item) => item.id == _classId && item.isActive),
    );
    final classSubjects = selectedClass?.subjectIds.toSet() ?? <int>{};
    final subjects = widget.data.subjects
        .where(
          (item) =>
              item.isActive &&
              (classSubjects.isEmpty || classSubjects.contains(item.id)),
        )
        .toList();
    if (widget.entry != null &&
        widget.entry!.teacherId == _teacherId &&
        widget.entry!.classId == _classId) {
      final oldSubject = widget.data.subjects.where(
        (item) => item.id == widget.entry!.subjectId,
      );
      if (oldSubject.isNotEmpty &&
          !subjects.any((item) => item.id == oldSubject.first.id)) {
        subjects.add(oldSubject.first);
      }
    }
    return subjects;
  }

  Teacher? get _selectedTeacher =>
      widget.data.teachers.any((item) => item.id == _teacherId)
      ? widget.data.teachers.firstWhere((item) => item.id == _teacherId)
      : null;

  int? get _firstSubject =>
      _teacherSubjects.isEmpty ? null : _teacherSubjects.first.id;

  bool get _selectedSubjectNeedsCorrection {
    final teacher = _selectedTeacher;
    final subject = firstOrNull(
      widget.data.subjects.where((item) => item.id == _subjectId),
    );
    final schoolClass = firstOrNull(
      widget.data.classes.where((item) => item.id == _classId),
    );
    return teacher == null ||
        subject == null ||
        !subject.isActive ||
        (schoolClass != null &&
            schoolClass.subjectIds.isNotEmpty &&
            !schoolClass.subjectIds.contains(_subjectId));
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
        _periodId == null ||
        _days.isEmpty) {
      setState(() => _error = 'Choose a class, teacher, subject, and period.');
      return;
    }
    Navigator.pop(
      context,
      _days
          .map(
            (day) => TimetableEntry(
              id: widget.entry?.dayOfWeek == day ? widget.entry?.id : null,
              classId: _classId!,
              sectionId: _sectionId == 0 ? null : _sectionId,
              subjectId: _subjectId!,
              teacherId: _teacherId!,
              periodId: _periodId!,
              dayOfWeek: day,
              room: _room.text.trim(),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classes = widget.data.classes
        .where((item) => item.isActive || item.id == widget.entry?.classId)
        .toList();
    final subjects = _teacherSubjects;
    final teachers =
        widget.data.teachers.where((item) => item.isActive).toList()
          ..sort((a, b) {
            final aQualified =
                _subjectId != null && a.subjectIds.contains(_subjectId);
            final bQualified =
                _subjectId != null && b.subjectIds.contains(_subjectId);
            if (aQualified != bQualified) return aQualified ? -1 : 1;
            return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
          });
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _classId,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: classes
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.isActive
                                      ? item.name
                                      : '${item.name} (disabled · historical)',
                                ),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? 'Choose a class' : null,
                        onChanged: (value) => setState(() {
                          _classId = value;
                          _sectionId = 0;
                          _sections = _loadSections();
                          if (!_teacherSubjects.any(
                            (item) => item.id == _subjectId,
                          )) {
                            _subjectId = _firstSubject;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<List<SchoolSection>>(
                        future: _sections,
                        builder: (context, snapshot) {
                          final sections =
                              snapshot.data ?? const <SchoolSection>[];
                          return DropdownButtonFormField<int>(
                            initialValue: _sectionId,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 0,
                                child: Text('Whole class'),
                              ),
                              ...sections
                                  .where(
                                    (item) =>
                                        item.isActive ||
                                        item.id == widget.entry?.sectionId,
                                  )
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item.id,
                                      child: Text(
                                        item.isActive
                                            ? item.name
                                            : '${item.name} (disabled · historical)',
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) =>
                                setState(() => _sectionId = value ?? 0),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownMenu<Teacher>(
                  key: ValueKey('teacher-$_teacherId'),
                  initialSelection: _selectedTeacher,
                  label: const Text('Teacher'),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  dropdownMenuEntries: teachers
                      .map(
                        (item) => DropdownMenuEntry<Teacher>(
                          value: item,
                          label: item.fullName,
                          trailingIcon: item.subjectIds.contains(_subjectId)
                              ? const Icon(Icons.check_circle_outline_rounded)
                              : const Icon(Icons.info_outline_rounded),
                          labelWidget: Row(
                            children: [
                              Expanded(child: Text(item.fullName)),
                              const SizedBox(width: 8),
                              Text(
                                item.subjectIds.contains(_subjectId)
                                    ? 'Subject match'
                                    : 'Fallback',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onSelected: (teacher) => setState(() {
                    _teacherId = teacher?.id;
                  }),
                ),
                if (_selectedTeacher != null &&
                    _subjectId != null &&
                    !_selectedTeacher!.subjectIds.contains(_subjectId)) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Subject fallback: this teacher is not listed for the selected subject. Choose a subject-qualified teacher when available.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (subjects.isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No active subjects are available for this class. Enable subjects in School setup.',
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SchoolManagementScreen(
                                initialTabIndex: 2,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage class subjects'),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue:
                            subjects.any((item) => item.id == _subjectId)
                            ? _subjectId
                            : _firstSubject,
                        decoration: const InputDecoration(labelText: 'Subject'),
                        items: subjects
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.id == widget.entry?.subjectId &&
                                          _selectedSubjectNeedsCorrection
                                      ? '${item.name} (needs correction)'
                                      : item.name,
                                ),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? 'Choose a class subject' : null,
                        onChanged: (value) =>
                            setState(() => _subjectId = value),
                      ),
                      if (_selectedTeacher != null &&
                          _subjectId != null &&
                          !_selectedTeacher!.subjectIds.contains(_subjectId))
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Subject fallback: this teacher is not listed for the selected subject. Choose a subject-qualified teacher when available.',
                          ),
                        )
                      else if (_selectedSubjectNeedsCorrection)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'This historical lesson no longer matches the teacher or class subject settings. Choose an enabled subject to correct it.',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Days · same lesson will be applied to each selected day',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: widget.data.workingDays
                      .map(
                        (day) => FilterChip(
                          label: Text(schoolWeekdays[day]!),
                          selected: _days.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _days.add(day);
                            } else if (_days.length > 1) {
                              _days.remove(day);
                            }
                          }),
                        ),
                      )
                      .toList(),
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

TimetableEntry _withTimetableId(TimetableEntry entry, int id) => TimetableEntry(
  id: id,
  classId: entry.classId,
  sectionId: entry.sectionId,
  subjectId: entry.subjectId,
  teacherId: entry.teacherId,
  periodId: entry.periodId,
  dayOfWeek: entry.dayOfWeek,
  room: entry.room,
);

String _friendlyError(Object error) {
  if (error is SchoolDataException || error is DuplicateSchoolRecordException) {
    return error.toString();
  }
  return 'Could not save the timetable. Check the selections and try again.';
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
