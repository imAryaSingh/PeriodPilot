import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/presentation/local_auth_controller.dart';
import '../../auth/domain/user_profile.dart';
import '../../school/data/school_database.dart';
import '../../school/domain/school_models.dart';

enum _Report { daily, monthly, teacher, absence, workload }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final Future<_ReportData> _future = _load();
  _Report _selected = _Report.daily;
  DateTime _date = DateTime.now();
  int? _teacherId;
  bool _sharing = false;

  Future<_ReportData> _load() async {
    final db = context.read<SchoolDatabase>();
    final values = await Future.wait<Object>([
      db.getTeachers(),
      db.getAbsences(),
      db.getSubstitutions(),
      db.getTimetableEntries(),
      db.getPeriods(),
      db.getClasses(),
      db.getSubjects(),
    ]);
    return _ReportData(
      teachers: values[0] as List<Teacher>,
      absences: values[1] as List<TeacherAbsence>,
      assignments: values[2] as List<SubstitutionAssignment>,
      entries: values[3] as List<TimetableEntry>,
      periods: values[4] as List<SchoolPeriod>,
      classes: {for (final x in values[5] as List<SchoolClass>) x.id: x.name},
      subjects: {
        for (final x in values[6] as List<Subject>)
          if (x.id != null) x.id!: x.name,
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports')),
    body: FutureBuilder<_ReportData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load reports: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final isTeacher =
            context.read<LocalAuthController>().profile?.role ==
            UserRole.teacher;
        final report = isTeacher ? _Report.teacher : _selected;
        final rows = _rows(data, report);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF193B58),
                    Color(0xFF1D3943),
                    Color(0xFF252C4E),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'School reports',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isTeacher
                        ? 'Review your substitution history.'
                        : 'Review coverage, absences, and staff workload.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<_Report>(
              initialValue: report,
              decoration: const InputDecoration(
                labelText: 'Report type',
                border: OutlineInputBorder(),
              ),
              items: _Report.values
                  .where((r) => !isTeacher || r == _Report.teacher)
                  .map(
                    (r) => DropdownMenuItem(value: r, child: Text(_label(r))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selected = v ?? report),
            ),
            if (report == _Report.daily || report == _Report.monthly) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                  report == _Report.daily
                      ? 'Date: ${schoolDateKey(_date)}'
                      : 'Month: ${_month(_date.month)} ${_date.year}',
                ),
              ),
            ],
            if (report == _Report.teacher && !isTeacher) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _teacherId,
                decoration: const InputDecoration(
                  labelText: 'Teacher',
                  border: OutlineInputBorder(),
                ),
                items: data.teachers
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(t.fullName),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _teacherId = v),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_label(report)} · ${rows.length} records',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: rows.isEmpty || _sharing
                      ? null
                      : () => _export(rows, report),
                  icon: _sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    report == _Report.teacher &&
                            _teacherId == null &&
                            !isTeacher
                        ? 'Select a teacher to view their duties.'
                        : 'No records match this report.',
                  ),
                ),
              )
            else
              ...rows
                  .take(60)
                  .map(
                    (r) => Card(
                      child: ListTile(
                        leading: Icon(
                          report == _Report.absence
                              ? Icons.event_busy_rounded
                              : Icons.assessment_outlined,
                        ),
                        title: Text(r[1]),
                        subtitle: Text(r.skip(2).join(' · ')),
                        trailing: Text(
                          r.first,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    ),
  );

  Future<void> _pickDate() async {
    if (_selected == _Report.monthly) {
      final value = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        helpText: 'Choose any date in the report month',
      );
      if (value != null && mounted) setState(() => _date = value);
    } else {
      final value = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (value != null && mounted) setState(() => _date = value);
    }
  }

  List<List<String>> _rows(_ReportData d, _Report report) {
    final profile = context.read<LocalAuthController>().profile;
    final own = d.teachers
        .where(
          (t) =>
              t.email.trim().toLowerCase() ==
              (profile?.email ?? '').trim().toLowerCase(),
        )
        .firstOrNull;
    final rows = <List<String>>[];
    if (report == _Report.absence) {
      for (final a in d.absences) {
        final t = d.teacher(a.teacherId);
        rows.add([
          a.dateKey,
          t?.fullName ?? 'Teacher ${a.teacherId}',
          a.type.label,
          a.notes,
        ]);
      }
    } else if (report == _Report.workload) {
      final counts = <int, int>{};
      for (final a in d.assignments.where(
        (x) => x.status == SubstitutionStatus.assigned,
      )) {
        counts.update(a.substituteTeacherId, (v) => v + 1, ifAbsent: () => 1);
      }
      final people = profile?.role == UserRole.teacher && own != null
          ? d.teachers.where((t) => t.id == own.id)
          : d.teachers;
      for (final t in people) {
        rows.add([
          '${counts[t.id] ?? 0}',
          t.fullName,
          t.staffCode,
          '${counts[t.id] ?? 0} duties',
        ]);
      }
    } else {
      Iterable<SubstitutionAssignment> values = d.assignments.where(
        (a) => a.status == SubstitutionStatus.assigned,
      );
      if (report == _Report.daily) {
        final key = schoolDateKey(_date);
        values = values.where((a) => a.dateKey == key);
      }
      if (report == _Report.monthly) {
        values = values.where(
          (a) => a.date.year == _date.year && a.date.month == _date.month,
        );
      }
      if (report == _Report.teacher) {
        final id = profile?.role == UserRole.teacher ? own?.id : _teacherId;
        if (id == null) return const [];
        values = values.where((a) => a.substituteTeacherId == id);
      }
      for (final a in values) {
        final substitute = d.teacher(a.substituteTeacherId);
        final absent = d.teacher(a.absentTeacherId);
        final period = d.period(a.periodId);
        rows.add([
          a.dateKey,
          d.classes[a.classId] ?? 'Class ${a.classId}',
          d.subjects[a.subjectId] ?? 'Subject ${a.subjectId}',
          period?.name ?? 'Period ${a.periodId}',
          substitute?.fullName ?? 'Teacher ${a.substituteTeacherId}',
          absent?.fullName ?? 'Teacher ${a.absentTeacherId}',
          a.room,
        ]);
      }
    }
    rows.sort((a, b) => a.first.compareTo(b.first));
    return rows;
  }

  Future<void> _export(List<List<String>> rows, _Report report) async {
    setState(() => _sharing = true);
    try {
      final headers = switch (report) {
        _Report.absence => ['Date', 'Teacher', 'Type', 'Notes'],
        _Report.workload => [
          'Substitution duties',
          'Teacher',
          'Staff code',
          'Total',
        ],
        _ => [
          'Date',
          'Class',
          'Subject',
          'Period',
          'Substitute teacher',
          'Absent teacher',
          'Room',
        ],
      };
      final csv = [
        headers,
        ...rows,
      ].map((row) => row.map(_csvCell).join(',')).join('\r\n');
      final name = '${report.name}_${schoolDateKey(_date)}.csv';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
          subject: '${_label(report)} report',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _label(_Report r) => switch (r) {
    _Report.daily => 'Daily substitution report',
    _Report.monthly => 'Monthly substitution report',
    _Report.teacher => 'Teacher substitution duties',
    _Report.absence => 'Teacher absence report',
    _Report.workload => 'Workload distribution',
  };
  String _csvCell(String value) {
    // CSV quoting alone does not stop spreadsheet formula evaluation.
    final safe = RegExp(r'^[\s]*[=+\-@]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
}

class _ReportData {
  const _ReportData({
    required this.teachers,
    required this.absences,
    required this.assignments,
    required this.entries,
    required this.periods,
    required this.classes,
    required this.subjects,
  });
  final List<Teacher> teachers;
  final List<TeacherAbsence> absences;
  final List<SubstitutionAssignment> assignments;
  final List<TimetableEntry> entries;
  final List<SchoolPeriod> periods;
  final Map<int, String> classes, subjects;
  Teacher? teacher(int id) => teachers.where((t) => t.id == id).firstOrNull;
  SchoolPeriod? period(int id) => periods.where((p) => p.id == id).firstOrNull;
}

String _month(int n) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][n - 1];
