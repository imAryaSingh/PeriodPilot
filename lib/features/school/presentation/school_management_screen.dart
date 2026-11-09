import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/school_database.dart';
import '../domain/school_models.dart';

class SchoolManagementScreen extends StatelessWidget {
  const SchoolManagementScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('School setup'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.apartment_rounded), text: 'School'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Teachers'),
            Tab(icon: Icon(Icons.class_outlined), text: 'Classes'),
            Tab(icon: Icon(Icons.menu_book_outlined), text: 'Subjects'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _SchoolProfileTab(),
          _TeachersTab(),
          _ClassesTab(),
          _SubjectsTab(),
        ],
      ),
    ),
  );
}

class _SchoolProfileTab extends StatefulWidget {
  const _SchoolProfileTab();

  @override
  State<_SchoolProfileTab> createState() => _SchoolProfileTabState();
}

class _SchoolProfileTabState extends State<_SchoolProfileTab> {
  late Future<SchoolProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = context.read<SchoolDatabase>().getSchoolProfile();
  }

  void _reload() {
    setState(() {
      _profile = context.read<SchoolDatabase>().getSchoolProfile();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SchoolProfile>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingState();
      }
      if (snapshot.hasError) {
        return _LoadError(message: snapshot.error.toString(), onRetry: _reload);
      }
      return _SchoolProfileForm(
        profile: snapshot.requireData,
        onSaved: _reload,
      );
    },
  );
}

class _SchoolProfileForm extends StatefulWidget {
  const _SchoolProfileForm({required this.profile, required this.onSaved});

  final SchoolProfile profile;
  final VoidCallback onSaved;

  @override
  State<_SchoolProfileForm> createState() => _SchoolProfileFormState();
}

class _SchoolProfileFormState extends State<_SchoolProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _address = TextEditingController(text: widget.profile.address);
    _phone = TextEditingController(text: widget.profile.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SchoolDatabase>().saveSchoolProfile(
        SchoolProfile(
          name: _name.text,
          address: _address.text,
          phone: _phone.text,
        ),
      );
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('School profile saved.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the school profile.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const _SectionHeading(
        title: 'School profile',
        subtitle: 'Set the school details used throughout this device.',
      ),
      const SizedBox(height: 20),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'School name',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter the school name'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'School phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorCard(message: _error!),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save school profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _TeachersTab extends StatefulWidget {
  const _TeachersTab();

  @override
  State<_TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<_TeachersTab> {
  late Future<List<Teacher>> _teachers;

  @override
  void initState() {
    super.initState();
    _teachers = context.read<SchoolDatabase>().getTeachers();
  }

  void _reload() =>
      setState(() => _teachers = context.read<SchoolDatabase>().getTeachers());

  Future<void> _edit([Teacher? teacher]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TeacherDialog(teacher: teacher),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _setActive(Teacher teacher, bool active) async {
    await context.read<SchoolDatabase>().setTeacherActive(teacher.id!, active);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Teacher>>(
    future: _teachers,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingState();
      }
      if (snapshot.hasError) {
        return _LoadError(message: snapshot.error.toString(), onRetry: _reload);
      }
      final teachers = snapshot.requireData;
      return Column(
        children: [
          _ListHeader(
            title: 'Teachers',
            subtitle:
                '${teachers.where((teacher) => teacher.isActive).length} active',
            actionLabel: 'Add teacher',
            onAction: () => _edit(),
          ),
          Expanded(
            child: teachers.isEmpty
                ? const _EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No teachers yet',
                    message:
                        'Add your first teacher to build the school directory.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: teachers.length,
                    itemBuilder: (context, index) {
                      final teacher = teachers[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(_initials(teacher.fullName)),
                          ),
                          title: Text(teacher.fullName),
                          subtitle: Text(_teacherSubtitle(teacher)),
                          isThreeLine: _teacherSubtitle(teacher).contains('\n'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit teacher',
                                onPressed: () => _edit(teacher),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              Switch(
                                value: teacher.isActive,
                                onChanged: (value) =>
                                    _setActive(teacher, value),
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
    },
  );
}

String _teacherSubtitle(Teacher teacher) {
  final details = <String>[];
  if (teacher.staffCode.isNotEmpty) details.add('ID ${teacher.staffCode}');
  if (teacher.email.isNotEmpty) details.add(teacher.email);
  if (teacher.phone.isNotEmpty) details.add(teacher.phone);
  if (!teacher.isActive) details.add('Inactive');
  return details.join('\n');
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts
      .take(2)
      .map((part) => part.characters.first)
      .join()
      .toUpperCase();
}

class _TeacherDialog extends StatefulWidget {
  const _TeacherDialog({this.teacher});

  final Teacher? teacher;

  @override
  State<_TeacherDialog> createState() => _TeacherDialogState();
}

class _TeacherDialogState extends State<_TeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.teacher?.fullName ?? '');
    _code = TextEditingController(text: widget.teacher?.staffCode ?? '');
    _email = TextEditingController(text: widget.teacher?.email ?? '');
    _phone = TextEditingController(text: widget.teacher?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SchoolDatabase>().saveTeacher(
        Teacher(
          id: widget.teacher?.id,
          fullName: _name.text,
          staffCode: _code.text,
          email: _email.text,
          phone: _phone.text,
          isActive: widget.teacher?.isActive ?? true,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.toString().contains('UNIQUE') ||
                  error.toString().contains('already in use')
              ? 'That staff ID is already in use.'
              : 'Could not save this teacher. Check the details and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.teacher == null ? 'Add teacher' : 'Edit teacher'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Enter the teacher name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Staff ID (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isNotEmpty &&
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorCard(message: _error!),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

class _ClassesTab extends StatefulWidget {
  const _ClassesTab();

  @override
  State<_ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<_ClassesTab> {
  late Future<List<SchoolClass>> _classes;

  @override
  void initState() {
    super.initState();
    _classes = context.read<SchoolDatabase>().getClasses();
  }

  void _reload() =>
      setState(() => _classes = context.read<SchoolDatabase>().getClasses());

  Future<void> _editClass([SchoolClass? schoolClass]) async {
    final database = context.read<SchoolDatabase>();
    final name = await _nameDialog(
      context,
      title: schoolClass == null ? 'Add class' : 'Edit class',
      label: 'Class name or grade',
      initialValue: schoolClass?.name ?? '',
    );
    if (name == null) return;
    try {
      await database.saveClass(
        SchoolClass(id: schoolClass?.id ?? 0, name: name),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(context, _duplicateMessage(error, 'class name'));
    }
  }

  Future<void> _editSection(int classId, [SchoolSection? section]) async {
    final database = context.read<SchoolDatabase>();
    final name = await _nameDialog(
      context,
      title: section == null ? 'Add section' : 'Edit section',
      label: 'Section name',
      initialValue: section?.name ?? '',
    );
    if (name == null) return;
    try {
      await database.saveSection(
        SchoolSection(id: section?.id ?? 0, classId: classId, name: name),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        _showError(context, _duplicateMessage(error, 'section name'));
      }
    }
  }

  Future<void> _deleteClass(SchoolClass schoolClass) async {
    final database = context.read<SchoolDatabase>();
    if (!await _confirmDelete(
      context,
      'Delete ${schoolClass.name}?',
      'This will also remove its sections from this device.',
    )) {
      return;
    }
    if (!mounted) return;
    await database.deleteClass(schoolClass.id);
    if (mounted) _reload();
  }

  Future<void> _deleteSection(SchoolSection section) async {
    final database = context.read<SchoolDatabase>();
    if (!await _confirmDelete(
      context,
      'Delete section ${section.name}?',
      'This removes the section from this device.',
    )) {
      return;
    }
    if (!mounted) return;
    await database.deleteSection(section.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SchoolClass>>(
    future: _classes,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingState();
      }
      if (snapshot.hasError) {
        return _LoadError(message: snapshot.error.toString(), onRetry: _reload);
      }
      final classes = snapshot.requireData;
      return Column(
        children: [
          _ListHeader(
            title: 'Classes and sections',
            subtitle: '${classes.length} classes',
            actionLabel: 'Add class',
            onAction: () => _editClass(),
          ),
          Expanded(
            child: classes.isEmpty
                ? const _EmptyState(
                    icon: Icons.class_outlined,
                    title: 'No classes yet',
                    message: 'Add a class or grade, then add its sections.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final schoolClass = classes[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 12, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      schoolClass.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit class',
                                    onPressed: () => _editClass(schoolClass),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete class',
                                    onPressed: () => _deleteClass(schoolClass),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              FutureBuilder<List<SchoolSection>>(
                                future: context
                                    .read<SchoolDatabase>()
                                    .getSections(schoolClass.id),
                                builder: (context, sectionSnapshot) {
                                  if (sectionSnapshot.hasError) {
                                    return const Text(
                                      'Could not load sections.',
                                    );
                                  }
                                  if (!sectionSnapshot.hasData) {
                                    return const LinearProgressIndicator();
                                  }
                                  final sections = sectionSnapshot.data!;
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final section in sections)
                                        InputChip(
                                          label: Text(section.name),
                                          onPressed: () => _editSection(
                                            schoolClass.id,
                                            section,
                                          ),
                                          onDeleted: () =>
                                              _deleteSection(section),
                                        ),
                                      ActionChip(
                                        avatar: const Icon(Icons.add, size: 18),
                                        label: const Text('Add section'),
                                        onPressed: () =>
                                            _editSection(schoolClass.id),
                                      ),
                                    ],
                                  );
                                },
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
    },
  );
}

class _SubjectsTab extends StatefulWidget {
  const _SubjectsTab();

  @override
  State<_SubjectsTab> createState() => _SubjectsTabState();
}

class _SubjectsTabState extends State<_SubjectsTab> {
  late Future<List<Subject>> _subjects;

  @override
  void initState() {
    super.initState();
    _subjects = context.read<SchoolDatabase>().getSubjects();
  }

  void _reload() =>
      setState(() => _subjects = context.read<SchoolDatabase>().getSubjects());

  Future<void> _edit([Subject? subject]) async {
    final database = context.read<SchoolDatabase>();
    final values = await showDialog<(String, String)?>(
      context: context,
      builder: (_) => _SubjectDialog(subject: subject),
    );
    if (values == null) return;
    try {
      await database.saveSubject(
        Subject(
          id: subject?.id,
          name: values.$1,
          code: values.$2,
          isActive: subject?.isActive ?? true,
        ),
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        _showError(context, _duplicateMessage(error, 'subject name or code'));
      }
    }
  }

  Future<void> _setActive(Subject subject, bool active) async {
    await context.read<SchoolDatabase>().setSubjectActive(subject.id!, active);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Subject>>(
    future: _subjects,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingState();
      }
      if (snapshot.hasError) {
        return _LoadError(message: snapshot.error.toString(), onRetry: _reload);
      }
      final subjects = snapshot.requireData;
      return Column(
        children: [
          _ListHeader(
            title: 'Subjects',
            subtitle:
                '${subjects.where((subject) => subject.isActive).length} active',
            actionLabel: 'Add subject',
            onAction: () => _edit(),
          ),
          Expanded(
            child: subjects.isEmpty
                ? const _EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: 'No subjects yet',
                    message: 'Add subjects before building the timetable.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: subjects.length,
                    itemBuilder: (context, index) {
                      final subject = subjects[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.menu_book_outlined),
                          ),
                          title: Text(subject.name),
                          subtitle: Text(
                            [
                              if (subject.code.isNotEmpty) subject.code,
                              if (!subject.isActive) 'Inactive',
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit subject',
                                onPressed: () => _edit(subject),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              Switch(
                                value: subject.isActive,
                                onChanged: (value) =>
                                    _setActive(subject, value),
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
    },
  );
}

class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({this.subject});

  final Subject? subject;

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.subject?.name ?? '');
    _code = TextEditingController(text: widget.subject?.code ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.subject == null ? 'Add subject' : 'Edit subject'),
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
              decoration: const InputDecoration(labelText: 'Subject name'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter the subject name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Subject code (optional)',
              ),
            ),
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
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, (_name.text.trim(), _code.text.trim()));
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onAction,
          icon: const Icon(Icons.add_rounded),
          label: Text(actionLabel),
        ),
      ],
    ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storage_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}

Future<String?> _nameDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: label),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Enter a name' : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

Future<bool> _confirmDelete(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

String _duplicateMessage(Object error, String field) =>
    error.toString().contains('UNIQUE') ||
        error.toString().contains('already in use')
    ? 'That $field already exists.'
    : 'Could not save the record. Check the details and try again.';

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
