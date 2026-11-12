bool _valueToBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return false;
}

bool _rowBool(Map<String, Object?> row, String camelKey, [String? snakeKey]) {
  final snake =
      snakeKey ??
      camelKey.replaceAllMapped(
        RegExp(r'(?<!^)([A-Z])'),
        (match) => '_${match.group(1)!.toLowerCase()}',
      );
  final value = row[camelKey] ?? row[snake];
  return _valueToBool(value);
}

List<int> _intList(Object? value) {
  if (value is Iterable) {
    return value
        .whereType<num>()
        .map((id) => id.toInt())
        .toList(growable: false);
  }
  if (value is String && value.isNotEmpty) {
    return value
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
  }
  return const <int>[];
}

class SchoolProfile {
  const SchoolProfile({required this.name, this.address = '', this.phone = ''});

  final String name;
  final String address;
  final String phone;

  factory SchoolProfile.fromMap(Map<String, Object?> row) => SchoolProfile(
    name: row['name'] as String? ?? '',
    address: row['address'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
  );
}

class Teacher {
  const Teacher({
    required this.id,
    required this.fullName,
    required this.staffCode,
    required this.email,
    required this.phone,
    required this.isActive,
    this.subjectIds = const <int>[],
  });

  final int? id;
  final String fullName;
  final String staffCode;
  final String email;
  final String phone;
  final bool isActive;
  final List<int> subjectIds;

  factory Teacher.fromMap(Map<String, Object?> row) => Teacher(
    id: row['id'] as int,
    fullName: row['full_name'] as String,
    staffCode: row['staff_code'] as String? ?? '',
    email: row['email'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    isActive: _rowBool(row, 'isActive', 'is_active'),
    subjectIds: _intList(row['subjectIds'] ?? row['subject_ids']),
  );
}

class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    this.isActive = true,
    this.sortOrder = 0,
    this.subjectIds = const <int>[],
  });

  final int id;
  final String name;
  final bool isActive;
  final int sortOrder;
  final List<int> subjectIds;

  factory SchoolClass.fromMap(Map<String, Object?> row) => SchoolClass(
    id: row['id'] as int,
    name: row['name'] as String,
    isActive: row['isActive'] == null && row['is_active'] == null
        ? true
        : _rowBool(row, 'isActive', 'is_active'),
    sortOrder: ((row['sortOrder'] ?? row['sort_order']) as num?)?.toInt() ?? 0,
    subjectIds: _intList(row['subjectIds'] ?? row['subject_ids']),
  );
}

class SchoolSection {
  const SchoolSection({
    required this.id,
    required this.classId,
    required this.name,
    this.isActive = true,
  });

  final int id;
  final int classId;
  final String name;
  final bool isActive;

  factory SchoolSection.fromMap(Map<String, Object?> row) => SchoolSection(
    id: row['id'] as int,
    classId: row['class_id'] as int,
    name: row['name'] as String,
    isActive: row['isActive'] == null && row['is_active'] == null
        ? true
        : _rowBool(row, 'isActive', 'is_active'),
  );
}

class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
  });

  final int? id;
  final String name;
  final String code;
  final bool isActive;

  factory Subject.fromMap(Map<String, Object?> row) => Subject(
    id: row['id'] as int,
    name: row['name'] as String,
    code: row['code'] as String? ?? '',
    isActive: _rowBool(row, 'isActive', 'is_active'),
  );
}

class SchoolPeriod {
  const SchoolPeriod({
    required this.id,
    required this.name,
    required this.startMinute,
    required this.endMinute,
    required this.isActive,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final int startMinute;
  final int endMinute;
  final bool isActive;
  final int sortOrder;

  factory SchoolPeriod.fromMap(Map<String, Object?> row) => SchoolPeriod(
    id: row['id'] as int?,
    name: row['name'] as String? ?? '',
    startMinute: row['startMinute'] as int? ?? row['start_minute'] as int? ?? 0,
    endMinute: row['endMinute'] as int? ?? row['end_minute'] as int? ?? 0,
    isActive: _rowBool(row, 'isActive', 'is_active'),
    sortOrder:
        row['sortOrder'] as int? ??
        row['sort_order'] as int? ??
        row['startMinute'] as int? ??
        row['start_minute'] as int? ??
        0,
  );
}

class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.classId,
    required this.sectionId,
    required this.subjectId,
    required this.teacherId,
    required this.periodId,
    required this.dayOfWeek,
    required this.room,
  });

  final int? id;
  final int classId;
  final int? sectionId;
  final int subjectId;
  final int teacherId;
  final int periodId;

  /// ISO weekday number: Monday = 1, Sunday = 7.
  final int dayOfWeek;
  final String room;

  factory TimetableEntry.fromMap(Map<String, Object?> row) => TimetableEntry(
    id: row['id'] as int?,
    classId: (row['classId'] ?? row['class_id']) as int,
    sectionId: (row['sectionId'] ?? row['section_id']) as int?,
    subjectId: (row['subjectId'] ?? row['subject_id']) as int,
    teacherId: (row['teacherId'] ?? row['teacher_id']) as int,
    periodId: (row['periodId'] ?? row['period_id']) as int,
    dayOfWeek: (row['dayOfWeek'] ?? row['day_of_week']) as int,
    room: row['room'] as String? ?? '',
  );
}

enum AbsenceType {
  absent('absent', 'Absent'),
  leave('leave', 'On leave');

  const AbsenceType(this.key, this.label);

  final String key;
  final String label;

  static AbsenceType fromKey(String? value) =>
      value == 'leave' ? AbsenceType.leave : AbsenceType.absent;
}

class TeacherAbsence {
  const TeacherAbsence({
    required this.id,
    required this.teacherId,
    required this.date,
    required this.type,
    required this.notes,
  });

  final int? id;
  final int teacherId;
  final DateTime date;
  final AbsenceType type;
  final String notes;

  String get dateKey => schoolDateKey(date);

  factory TeacherAbsence.fromMap(Map<String, Object?> row) => TeacherAbsence(
    id: row['id'] as int?,
    teacherId: (row['teacherId'] ?? row['teacher_id']) as int,
    date: DateTime.parse(row['dateKey'] as String? ?? row['date'] as String),
    type: AbsenceType.fromKey(row['type'] as String?),
    notes: row['notes'] as String? ?? '',
  );
}

enum SubstitutionStatus { assigned, cancelled }

class SubstitutionAssignment {
  const SubstitutionAssignment({
    required this.id,
    required this.timetableEntryId,
    required this.absentTeacherId,
    required this.substituteTeacherId,
    required this.date,
    required this.classId,
    required this.sectionId,
    required this.subjectId,
    required this.periodId,
    required this.room,
    required this.isOverride,
    required this.status,
  });
  final int? id;
  final int timetableEntryId,
      absentTeacherId,
      substituteTeacherId,
      classId,
      subjectId,
      periodId;
  final int? sectionId;
  final DateTime date;
  final String room;
  final bool isOverride;
  final SubstitutionStatus status;
  String get dateKey => schoolDateKey(date);
  factory SubstitutionAssignment.fromMap(
    Map<String, Object?> row,
  ) => SubstitutionAssignment(
    id: (row['id'] as num?)?.toInt(),
    timetableEntryId:
        ((row['timetableEntryId'] ?? row['timetable_entry_id']) as num).toInt(),
    absentTeacherId:
        ((row['absentTeacherId'] ?? row['absent_teacher_id']) as num).toInt(),
    substituteTeacherId:
        ((row['substituteTeacherId'] ?? row['substitute_teacher_id']) as num)
            .toInt(),
    date: DateTime.parse((row['dateKey'] ?? row['date']) as String),
    classId: ((row['classId'] ?? row['class_id']) as num).toInt(),
    sectionId: ((row['sectionId'] ?? row['section_id']) as num?)?.toInt(),
    subjectId: ((row['subjectId'] ?? row['subject_id']) as num).toInt(),
    periodId: ((row['periodId'] ?? row['period_id']) as num).toInt(),
    room: row['room'] as String? ?? '',
    isOverride: _rowBool(row, 'isOverride', 'is_override'),
    status: (row['status'] as String?) == 'cancelled'
        ? SubstitutionStatus.cancelled
        : SubstitutionStatus.assigned,
  );
}

String schoolDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

const schoolWeekdays = <int, String>{
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};
