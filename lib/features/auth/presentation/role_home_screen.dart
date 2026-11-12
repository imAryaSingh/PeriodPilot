import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/user_profile.dart';
import 'local_auth_controller.dart';
import '../../school/data/school_database.dart';
import '../../school/domain/school_models.dart';
import '../../school/presentation/school_management_screen.dart';
import '../../school/presentation/timetable_management_screen.dart';
import '../../school/presentation/absence_management_screen.dart';
import '../../school/presentation/substitute_management_screen.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../reports/presentation/reports_screen.dart';

class RoleHomeScreen extends StatelessWidget {
  const RoleHomeScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LocalAuthController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(profile.role == UserRole.teacher ? 'My day' : 'Overview'),
        actions: [
          if (auth.usesFirebase)
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => _open(context, const NotificationCenterScreen()),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _Dashboard(profile: profile),
    );
  }
}

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.profile});
  final UserProfile profile;
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<_DashboardData> _future = _load();
  Future<_DashboardData> _load() async {
    final db = context.read<SchoolDatabase>();
    final all = await Future.wait<Object>([
      db.getTeachers(),
      db.getAbsences(),
      db.getSubstitutions(),
      db.getTimetableEntries(),
      db.getPeriods(),
      db.getClasses(),
      db.getSubjects(),
    ]);
    final date = DateTime.now();
    final today = schoolDateKey(date);
    final teachers = all[0] as List<Teacher>;
    final absences = (all[1] as List<TeacherAbsence>)
        .where((x) => x.dateKey == today)
        .toList();
    final assignments = all[2] as List<SubstitutionAssignment>;
    final entries = all[3] as List<TimetableEntry>;
    final periods = all[4] as List<SchoolPeriod>;
    final classes = all[5] as List<SchoolClass>;
    final subjects = all[6] as List<Subject>;
    final own = teachers
        .where(
          (t) =>
              t.email.trim().toLowerCase() ==
              widget.profile.email.trim().toLowerCase(),
        )
        .firstOrNull;
    return _DashboardData(
      teachers: teachers,
      absences: absences,
      assignments: assignments,
      entries: entries,
      periods: periods,
      classes: {for (final c in classes) c.id: c.name},
      subjects: {
        for (final s in subjects)
          if (s.id != null) s.id!: s.name,
      },
      own: own,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<_DashboardData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _state(
          'Could not load school data',
          '${snapshot.error}',
          onRetry: _refresh,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      return LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth > 850;
          final horizontalPadding = wide ? 32.0 : 18.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              22,
            ),
            children: [
              _hero(context),
              const SizedBox(height: 20),
              if (widget.profile.role == UserRole.teacher)
                _teacherContent(context, data)
              else
                _adminContent(context, data),
            ],
          );
        },
      );
    },
  );

  Widget _hero(BuildContext context) {
    final name = widget.profile.displayName.trim().isEmpty
        ? widget.profile.email
        : widget.profile.displayName;
    final date = DateTime.now();
    final subtitle =
        '${schoolWeekdays[date.weekday]}, ${date.day} ${_month(date.month)} ${date.year}';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF173B5A), Color(0xFF183A43), Color(0xFF252C52)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${date.hour < 12
                      ? 'morning'
                      : date.hour < 17
                      ? 'afternoon'
                      : 'evening'}, $name',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    ),
                    if (widget.profile.role == UserRole.administrator)
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            _open(context, const AbsenceManagementScreen()),
                        icon: const Icon(Icons.person_off_rounded, size: 18),
                        label: const Text('Mark absent'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _pill(widget.profile.role.label),
              ],
            ),
          ),
          if (widget.profile.role == UserRole.teacher)
            const Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: Color(0xFF74D6C3),
            )
          else
            const Icon(
              Icons.dashboard_customize_rounded,
              size: 48,
              color: Color(0xFF89C9F5),
            ),
        ],
      ),
    );
  }

  Widget _adminContent(BuildContext context, _DashboardData d) {
    final today = schoolDateKey(DateTime.now());
    final activeAssignments = d.assignments
        .where(
          (a) => a.dateKey == today && a.status == SubstitutionStatus.assigned,
        )
        .toList();
    final affected = <String>{};
    for (final a in d.absences) {
      affected.addAll(
        d.entries
            .where(
              (e) =>
                  e.teacherId == a.teacherId &&
                  e.dayOfWeek == DateTime.now().weekday,
            )
            .map((e) => '${e.id}'),
      );
    }
    final covered = activeAssignments
        .map((a) => '${a.timetableEntryId}')
        .toSet();
    final unassigned = affected.difference(covered).length;
    final cards = [
      _Metric(
        'Teachers',
        '${d.teachers.where((t) => t.isActive).length}',
        Icons.groups_rounded,
        const Color(0xFF68B6EE),
      ),
      _Metric(
        'Absent today',
        '${d.absences.length}',
        Icons.event_busy_rounded,
        const Color(0xFFF0A078),
      ),
      _Metric(
        'Available today',
        '${d.teachers.where((t) => t.isActive && !d.absences.any((a) => a.teacherId == t.id)).length}',
        Icons.person_outline_rounded,
        const Color(0xFF75D9B8),
      ),
      _Metric(
        'Duties today',
        '${activeAssignments.length}',
        Icons.swap_horiz_rounded,
        const Color(0xFFB3A0FF),
      ),
      _Metric(
        'Unassigned periods',
        '$unassigned',
        Icons.pending_actions_rounded,
        const Color(0xFFF2C46D),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          context,
          'Today at school',
          'Live summary from your school records',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = ((constraints.maxWidth + 12) / 168).floor().clamp(
              1,
              5,
            );
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 142,
              ),
              itemBuilder: (context, index) =>
                  _metricCard(context, cards[index]),
            );
          },
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, 'Quick actions', 'Common administrator tasks'),
        const SizedBox(height: 12),
        if (widget.profile.role == UserRole.administrator)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _action(
                context,
                'Assign substitute',
                Icons.swap_horiz_rounded,
                () => _open(context, const SubstituteManagementScreen()),
              ),
              _action(
                context,
                'Manage timetable',
                Icons.calendar_month_rounded,
                () => _open(context, const TimetableManagementScreen()),
              ),
              _action(
                context,
                'Manage teachers',
                Icons.manage_accounts_rounded,
                () => _open(context, const SchoolManagementScreen()),
              ),
              _action(
                context,
                'Reports',
                Icons.summarize_rounded,
                () => _open(context, const ReportsScreen()),
              ),
            ],
          ),
        if (widget.profile.role == UserRole.principal) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _open(context, const ReportsScreen()),
              icon: const Icon(Icons.summarize_rounded),
              label: const Text('View reports'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionTitle(
          context,
          'Recent duties',
          'Today’s confirmed substitute assignments',
        ),
        const SizedBox(height: 12),
        if (activeAssignments.isEmpty)
          _emptyCard('No substitution duties recorded for today.')
        else
          ...activeAssignments
              .take(6)
              .map((a) => _assignmentTile(context, a, d)),
      ],
    );
  }

  Widget _teacherContent(BuildContext context, _DashboardData d) {
    final teacher = d.own;
    if (teacher == null) {
      return _state(
        'Teacher profile not linked',
        'Ask the school administrator to add this account email to the teacher directory.',
      );
    }
    final now = DateTime.now();
    final key = schoolDateKey(now);
    final lessons =
        d.entries
            .where(
              (e) => e.teacherId == teacher.id && e.dayOfWeek == now.weekday,
            )
            .toList()
          ..sort((a, b) => _periodOrder(a, d).compareTo(_periodOrder(b, d)));
    final duties =
        d.assignments
            .where(
              (a) =>
                  a.substituteTeacherId == teacher.id &&
                  a.status == SubstitutionStatus.assigned &&
                  !a.date.isBefore(DateTime(now.year, now.month, now.day)),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final todayDuties = duties.where((a) => a.dateKey == key).toList();
    final current = now.hour * 60 + now.minute;
    final next =
        [
              ...lessons.map((e) => _period(e.periodId, d)),
              ...todayDuties.map((e) => _period(e.periodId, d)),
            ]
            .where((p) => p != null && p.startMinute >= current)
            .cast<SchoolPeriod?>()
            .toList()
          ..sort((a, b) => a!.startMinute.compareTo(b!.startMinute));
    final occupiedPeriods = {
      ...lessons.map((e) => e.periodId),
      ...todayDuties.map((e) => e.periodId),
    };
    final freePeriods =
        d.periods
            .where((p) => p.isActive && !occupiedPeriods.contains(p.id))
            .toList()
          ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next.isNotEmpty) _nextCard(context, next.first!),
        const SizedBox(height: 20),
        _sectionTitle(
          context,
          'Today’s timetable',
          '${lessons.length} regular periods · ${todayDuties.length} substitute duties · ${freePeriods.length} free',
        ),
        const SizedBox(height: 12),
        if (lessons.isEmpty && todayDuties.isEmpty)
          _emptyCard('No scheduled classes or substitute duties today.')
        else
          ..._teacherTimeline(context, lessons, todayDuties, d),
        if (freePeriods.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            color: const Color(0xFF183C39),
            child: ListTile(
              leading: const Icon(
                Icons.coffee_rounded,
                color: Color(0xFF75D9B8),
              ),
              title: const Text('Free periods'),
              subtitle: Text(
                freePeriods
                    .map(
                      (p) =>
                          '${p.name} · ${_clock(p.startMinute)}–${_clock(p.endMinute)}',
                    )
                    .join('  |  '),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _sectionTitle(
          context,
          'Upcoming substitute duties',
          'Your assigned duties and history',
        ),
        const SizedBox(height: 12),
        if (duties.isEmpty)
          _emptyCard('No upcoming substitute duties.')
        else
          ...duties.take(6).map((a) => _assignmentTile(context, a, d)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _open(context, const ReportsScreen()),
            icon: const Icon(Icons.history_rounded),
            label: const Text('View substitution history'),
          ),
        ),
      ],
    );
  }

  List<Widget> _teacherTimeline(
    BuildContext context,
    List<TimetableEntry> lessons,
    List<SubstitutionAssignment> duties,
    _DashboardData d,
  ) {
    final rows =
        <
          ({
            SchoolPeriod? period,
            TimetableEntry? lesson,
            SubstitutionAssignment? duty,
          })
        >[];
    for (final e in lessons) {
      rows.add((period: _period(e.periodId, d), lesson: e, duty: null));
    }
    for (final a in duties) {
      rows.add((period: _period(a.periodId, d), lesson: null, duty: a));
    }
    rows.sort(
      (a, b) =>
          (a.period?.startMinute ?? 0).compareTo(b.period?.startMinute ?? 0),
    );
    return rows.map((r) {
      final title = r.duty != null ? 'Substitution duty' : 'Regular class';
      final id = r.duty?.classId ?? r.lesson!.classId;
      final subjectId = r.duty?.subjectId ?? r.lesson!.subjectId;
      final period = r.period;
      return Card(
        child: ListTile(
          leading: Icon(
            r.duty != null ? Icons.swap_horiz_rounded : Icons.menu_book_rounded,
            color: r.duty != null
                ? const Color(0xFF74D6C3)
                : Theme.of(context).colorScheme.primary,
          ),
          title: Text('$title · ${period?.name ?? 'Period'}'),
          subtitle: Text(
            '${d.classes[id] ?? 'Class'} · ${d.subjects[subjectId] ?? 'Subject'} · Room ${r.duty?.room ?? r.lesson?.room ?? '—'}',
          ),
          trailing: period == null
              ? null
              : Text(
                  '${_clock(period.startMinute)}\n${_clock(period.endMinute)}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
        ),
      );
    }).toList();
  }

  Widget _assignmentTile(
    BuildContext context,
    SubstitutionAssignment a,
    _DashboardData d,
  ) {
    final teacher = d.teachers
        .where((t) => t.id == a.substituteTeacherId)
        .firstOrNull;
    final period = _period(a.periodId, d);
    final date =
        '${a.date.day.toString().padLeft(2, '0')} ${_month(a.date.month)}';
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.swap_horiz_rounded)),
        title: Text(
          '${d.classes[a.classId] ?? 'Class'} · ${d.subjects[a.subjectId] ?? 'Subject'}',
        ),
        subtitle: Text(
          '${teacher?.fullName ?? 'Substitute'} · ${period?.name ?? 'Period'} · $date',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _nextCard(BuildContext context, SchoolPeriod period) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        colors: [Color(0xFF174C55), Color(0xFF213757)],
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.schedule_rounded, color: Color(0xFF75E0C5), size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEXT PERIOD',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(letterSpacing: 1.3),
              ),
              const SizedBox(height: 4),
              Text(
                '${period.name} · ${_clock(period.startMinute)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _metricCard(BuildContext context, _Metric m) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(m.icon, color: m.color),
          const SizedBox(height: 16),
          Text(
            m.value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(m.label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(label),
  );
  Widget _sectionTitle(BuildContext context, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
  Widget _emptyCard(String s) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(s)),
  );
  Widget _state(String title, String details, {VoidCallback? onRetry}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 38),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(details, textAlign: TextAlign.center),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
  Widget _pill(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    ),
  );
  SchoolPeriod? _period(int id, _DashboardData d) =>
      d.periods.where((p) => p.id == id).firstOrNull;
  int _periodOrder(TimetableEntry e, _DashboardData d) =>
      _period(e.periodId, d)?.sortOrder ?? 0;
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}

class _DashboardData {
  const _DashboardData({
    required this.teachers,
    required this.absences,
    required this.assignments,
    required this.entries,
    required this.periods,
    required this.classes,
    required this.subjects,
    required this.own,
  });
  final List<Teacher> teachers;
  final List<TeacherAbsence> absences;
  final List<SubstitutionAssignment> assignments;
  final List<TimetableEntry> entries;
  final List<SchoolPeriod> periods;
  final Map<int, String> classes, subjects;
  final Teacher? own;
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
String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
