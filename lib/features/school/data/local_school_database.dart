import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/database_factory.dart';
import '../domain/school_models.dart';
import 'school_database.dart';

class LocalSchoolDatabase implements SchoolDatabase {
  Future<Database>? _database;

  Future<Database> get database => _database ??= _open();

  Future<Database> _open() async {
    await initializeDatabaseFactory();
    final basePath = await getDatabasesPath();
    return openDatabase(
      path.join(basePath, 'teacher_substitute.db'),
      version: 5,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE schools (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            name TEXT NOT NULL DEFAULT '',
            address TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            working_days TEXT NOT NULL DEFAULT '1,2,3,4,5'
          )
        ''');
        await database.insert('schools', {'id': 1});
        await database.execute('''
          CREATE TABLE teachers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            school_id INTEGER NOT NULL DEFAULT 1,
            staff_code TEXT,
            full_name TEXT NOT NULL,
            email TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (school_id) REFERENCES schools(id) ON DELETE RESTRICT,
            UNIQUE (school_id, staff_code)
          )
        ''');
        await database.execute('''
          CREATE TABLE classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            school_id INTEGER NOT NULL DEFAULT 1,
            name TEXT NOT NULL,
            FOREIGN KEY (school_id) REFERENCES schools(id) ON DELETE RESTRICT,
            UNIQUE (school_id, name)
          )
        ''');
        await database.execute('''
          CREATE TABLE sections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
            UNIQUE (class_id, name)
          )
        ''');
        await database.execute('''
          CREATE TABLE subjects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            school_id INTEGER NOT NULL DEFAULT 1,
            name TEXT NOT NULL,
            code TEXT,
            is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
            FOREIGN KEY (school_id) REFERENCES schools(id) ON DELETE RESTRICT,
            UNIQUE (school_id, name),
            UNIQUE (school_id, code)
          )
        ''');
        await _createTimetableTables(database);
        await _createAbsenceTable(database);
        await _createSubstitutionTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE schools ADD COLUMN working_days TEXT NOT NULL DEFAULT '1,2,3,4,5'",
          );
          await _createTimetableTables(database);
        }
        if (oldVersion < 3) await _createAbsenceTable(database);
        if (oldVersion < 4) await _createSubstitutionTable(database);
        if (oldVersion < 5) await _rebuildSubstitutionTable(database);
      },
    );
  }

  Future<void> _createTimetableTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        CHECK (start_minute >= 0 AND end_minute <= 1439 AND start_minute < end_minute)
      )
    ''');
    await database.execute('''
      CREATE TABLE timetable_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        section_id INTEGER,
        subject_id INTEGER NOT NULL,
        teacher_id INTEGER NOT NULL,
        period_id INTEGER NOT NULL,
        day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
        room TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT,
        FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT,
        FOREIGN KEY (period_id) REFERENCES periods(id) ON DELETE RESTRICT
      )
    ''');
    await database.execute(
      'CREATE INDEX timetable_day_period_idx ON timetable_entries(day_of_week, period_id)',
    );
    await database.execute(
      'CREATE INDEX timetable_teacher_idx ON timetable_entries(teacher_id, day_of_week)',
    );
  }

  Future<void> _createAbsenceTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE attendance_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacher_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('absent', 'leave')),
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT,
        UNIQUE (teacher_id, date)
      )
    ''');
    await database.execute(
      'CREATE INDEX attendance_date_idx ON attendance_records(date)',
    );
  }

  Future<void> _createSubstitutionTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE substitutions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timetable_entry_id INTEGER NOT NULL,
        absent_teacher_id INTEGER NOT NULL,
        substitute_teacher_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        class_id INTEGER NOT NULL,
        section_id INTEGER,
        subject_id INTEGER NOT NULL,
        period_id INTEGER NOT NULL,
        room TEXT NOT NULL DEFAULT '',
        is_override INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'cancelled')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (timetable_entry_id > 0)
      )
    ''');
    await database.execute(
      'CREATE INDEX substitutions_date_idx ON substitutions(date, status)',
    );
  }

  Future<void> _rebuildSubstitutionTable(DatabaseExecutor database) async {
    await database.execute(
      'ALTER TABLE substitutions RENAME TO substitutions_old',
    );
    await database.execute('DROP INDEX IF EXISTS substitutions_date_idx');
    await _createSubstitutionTable(database);
    await database.execute('''
      INSERT INTO substitutions (
        id, timetable_entry_id, absent_teacher_id, substitute_teacher_id, date,
        class_id, section_id, subject_id, period_id, room, is_override, status,
        created_at, updated_at
      ) SELECT id, timetable_entry_id, absent_teacher_id, substitute_teacher_id, date,
        class_id, section_id, subject_id, period_id, room, is_override, status,
        created_at, updated_at FROM substitutions_old
    ''');
    await database.execute('DROP TABLE substitutions_old');
  }

  @override
  Future<SchoolProfile> getSchoolProfile() async {
    final db = await database;
    final rows = await db.query('schools', where: 'id = 1', limit: 1);
    return SchoolProfile.fromMap(rows.single);
  }

  @override
  Future<void> saveSchoolProfile(SchoolProfile profile) async {
    final db = await database;
    await db.update('schools', {
      'name': profile.name.trim(),
      'address': profile.address.trim(),
      'phone': profile.phone.trim(),
    }, where: 'id = 1');
  }

  @override
  Future<List<Teacher>> getTeachers() async {
    final db = await database;
    final rows = await db.query(
      'teachers',
      orderBy: 'is_active DESC, full_name COLLATE NOCASE',
    );
    return rows.map(Teacher.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveTeacher(Teacher teacher) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'staff_code': teacher.staffCode.trim().isEmpty
          ? null
          : teacher.staffCode.trim(),
      'full_name': teacher.fullName.trim(),
      'email': teacher.email.trim(),
      'phone': teacher.phone.trim(),
      'updated_at': now,
    };
    if (teacher.id == null) {
      await db.insert('teachers', {...values, 'created_at': now});
    } else {
      await db.update(
        'teachers',
        values,
        where: 'id = ?',
        whereArgs: [teacher.id],
      );
    }
  }

  @override
  Future<void> setTeacherActive(int id, bool isActive) async {
    final db = await database;
    await db.update(
      'teachers',
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<SchoolClass>> getClasses() async {
    final db = await database;
    final rows = await db.query('classes', orderBy: 'name COLLATE NOCASE');
    return rows.map(SchoolClass.fromMap).toList(growable: false);
  }

  @override
  Future<List<SchoolSection>> getSections(int classId) async {
    final db = await database;
    final rows = await db.query(
      'sections',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(SchoolSection.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveClass(SchoolClass schoolClass) async {
    final db = await database;
    if (schoolClass.id == 0) {
      await db.insert('classes', {'name': schoolClass.name.trim()});
    } else {
      await db.update(
        'classes',
        {'name': schoolClass.name.trim()},
        where: 'id = ?',
        whereArgs: [schoolClass.id],
      );
    }
  }

  @override
  Future<void> deleteClass(int id) async {
    final db = await database;
    await db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> saveSection(SchoolSection section) async {
    final db = await database;
    if (section.id == 0) {
      await db.insert('sections', {
        'class_id': section.classId,
        'name': section.name.trim(),
      });
    } else {
      await db.update(
        'sections',
        {'name': section.name.trim()},
        where: 'id = ?',
        whereArgs: [section.id],
      );
    }
  }

  @override
  Future<void> deleteSection(int id) async {
    final db = await database;
    await db.delete('sections', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Subject>> getSubjects() async {
    final db = await database;
    final rows = await db.query(
      'subjects',
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(Subject.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveSubject(Subject subject) async {
    final db = await database;
    final values = {
      'name': subject.name.trim(),
      'code': subject.code.trim().isEmpty ? null : subject.code.trim(),
    };
    if (subject.id == null) {
      await db.insert('subjects', values);
    } else {
      await db.update(
        'subjects',
        values,
        where: 'id = ?',
        whereArgs: [subject.id],
      );
    }
  }

  @override
  Future<void> setSubjectActive(int id, bool isActive) async {
    final db = await database;
    await db.update(
      'subjects',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<SchoolPeriod>> getPeriods() async {
    final db = await database;
    final rows = await db.query('periods', orderBy: 'start_minute, name');
    return rows.map(SchoolPeriod.fromMap).toList(growable: false);
  }

  @override
  Future<void> savePeriod(SchoolPeriod period) async {
    if (period.startMinute < 0 ||
        period.endMinute > 1439 ||
        period.startMinute >= period.endMinute) {
      throw const SchoolDataException('Enter a valid period time range.');
    }
    final db = await database;
    final overlap = await db.rawQuery(
      '''SELECT id FROM periods
         WHERE is_active = 1 AND id != COALESCE(?, -1)
         AND ? < end_minute AND ? > start_minute LIMIT 1''',
      [period.id, period.startMinute, period.endMinute],
    );
    if (overlap.isNotEmpty) {
      throw const DuplicateSchoolRecordException(
        'Period times cannot overlap another active period.',
      );
    }
    final values = {
      'name': period.name.trim(),
      'start_minute': period.startMinute,
      'end_minute': period.endMinute,
      'is_active': period.isActive ? 1 : 0,
    };
    if (period.id == null) {
      await db.insert('periods', values);
    } else {
      await db.update(
        'periods',
        values,
        where: 'id = ?',
        whereArgs: [period.id],
      );
    }
  }

  @override
  Future<void> setPeriodActive(int id, bool isActive) async {
    final db = await database;
    final period = await db.query(
      'periods',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (period.isEmpty) throw const SchoolDataException('Period not found.');
    final entries = await db.query(
      'timetable_entries',
      columns: ['id'],
      where: 'period_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (!isActive && entries.isNotEmpty) {
      throw const SchoolDataException(
        'Move or remove the lessons assigned to this period before deactivating it.',
      );
    }
    if (isActive) {
      final start = period.single['start_minute'] as int;
      final end = period.single['end_minute'] as int;
      final overlaps = await db.rawQuery(
        '''SELECT id FROM periods
           WHERE is_active = 1 AND id != ?
           AND ? < end_minute AND ? > start_minute LIMIT 1''',
        [id, start, end],
      );
      if (overlaps.isNotEmpty) {
        throw const DuplicateSchoolRecordException(
          'Period times cannot overlap another active period.',
        );
      }
    }
    await db.update(
      'periods',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<int>> getWorkingDays() async {
    final db = await database;
    final rows = await db.query(
      'schools',
      columns: ['working_days'],
      where: 'id = 1',
      limit: 1,
    );
    final value = rows.single['working_days'] as String? ?? '1,2,3,4,5';
    return value
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .where((day) => day >= 1 && day <= 7)
        .toList()
      ..sort();
  }

  @override
  Future<void> saveWorkingDays(List<int> days) async {
    final normalized =
        days.toSet().where((day) => day >= 1 && day <= 7).toList()..sort();
    if (normalized.isEmpty) {
      throw const SchoolDataException('Select at least one working day.');
    }
    final db = await database;
    await db.update('schools', {
      'working_days': normalized.join(','),
    }, where: 'id = 1');
  }

  @override
  Future<List<TimetableEntry>> getTimetableEntries() async {
    final db = await database;
    final rows = await db.query(
      'timetable_entries',
      orderBy: 'day_of_week, period_id',
    );
    return rows.map(TimetableEntry.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveTimetableEntry(TimetableEntry entry) async {
    final db = await database;
    final conflicts = await db.query(
      'timetable_entries',
      where: 'day_of_week = ? AND period_id = ? AND id != COALESCE(?, -1)',
      whereArgs: [entry.dayOfWeek, entry.periodId, entry.id],
    );
    for (final row in conflicts) {
      final sameClass =
          row['class_id'] == entry.classId &&
          (row['section_id'] == entry.sectionId ||
              row['section_id'] == null ||
              entry.sectionId == null);
      if (sameClass) {
        throw const DuplicateSchoolRecordException(
          'This class or section already has a lesson during that period.',
        );
      }
      if (row['teacher_id'] == entry.teacherId) {
        throw const DuplicateSchoolRecordException(
          'This teacher is already assigned during that period.',
        );
      }
    }
    final values = {
      'class_id': entry.classId,
      'section_id': entry.sectionId,
      'subject_id': entry.subjectId,
      'teacher_id': entry.teacherId,
      'period_id': entry.periodId,
      'day_of_week': entry.dayOfWeek,
      'room': entry.room.trim(),
    };
    if (entry.id == null) {
      await db.insert('timetable_entries', values);
    } else {
      await db.update(
        'timetable_entries',
        values,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
    }
  }

  @override
  Future<void> deleteTimetableEntry(int id) async {
    final db = await database;
    await db.delete('timetable_entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<TeacherAbsence>> getAbsences() async {
    final db = await database;
    final rows = await db.query(
      'attendance_records',
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(TeacherAbsence.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveAbsence(TeacherAbsence absence) async {
    final db = await database;
    final date = schoolDateKey(absence.date);
    final duplicate = await db.query(
      'attendance_records',
      columns: ['id'],
      where: 'teacher_id = ? AND date = ? AND id != COALESCE(?, -1)',
      whereArgs: [absence.teacherId, date, absence.id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw const DuplicateSchoolRecordException(
        'This teacher already has an absence record for that date.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'teacher_id': absence.teacherId,
      'date': date,
      'type': absence.type.key,
      'notes': absence.notes.trim(),
      'updated_at': now,
    };
    if (absence.id == null) {
      await db.insert('attendance_records', {...values, 'created_at': now});
    } else {
      await db.update(
        'attendance_records',
        values,
        where: 'id = ?',
        whereArgs: [absence.id],
      );
    }
  }

  @override
  Future<void> deleteAbsence(int id) async {
    final db = await database;
    await db.delete('attendance_records', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<SubstitutionAssignment>> getSubstitutions() async {
    final db = await database;
    final rows = await db.query('substitutions', orderBy: 'date DESC, id DESC');
    return rows.map(SubstitutionAssignment.fromMap).toList(growable: false);
  }

  @override
  Future<void> saveSubstitution(SubstitutionAssignment assignment) async {
    final db = await database;
    final duplicate = await db.query(
      'substitutions',
      columns: ['id'],
      where:
          'date = ? AND timetable_entry_id = ? AND status = ? AND id != COALESCE(?, -1)',
      whereArgs: [
        assignment.dateKey,
        assignment.timetableEntryId,
        'assigned',
        assignment.id,
      ],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw const DuplicateSchoolRecordException(
        'This lesson already has a substitute assigned.',
      );
    }
    final teacherConflict = await db.query(
      'substitutions',
      columns: ['id'],
      where:
          'date = ? AND period_id = ? AND substitute_teacher_id = ? AND status = ? AND id != COALESCE(?, -1)',
      whereArgs: [
        assignment.dateKey,
        assignment.periodId,
        assignment.substituteTeacherId,
        'assigned',
        assignment.id,
      ],
      limit: 1,
    );
    if (teacherConflict.isNotEmpty) {
      throw const DuplicateSchoolRecordException(
        'This teacher already has a substitution during that period.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'timetable_entry_id': assignment.timetableEntryId,
      'absent_teacher_id': assignment.absentTeacherId,
      'substitute_teacher_id': assignment.substituteTeacherId,
      'date': assignment.dateKey,
      'class_id': assignment.classId,
      'section_id': assignment.sectionId,
      'subject_id': assignment.subjectId,
      'period_id': assignment.periodId,
      'room': assignment.room,
      'is_override': assignment.isOverride ? 1 : 0,
      'status': 'assigned',
      'updated_at': now,
    };
    if (assignment.id == null) {
      await db.insert('substitutions', {...values, 'created_at': now});
    } else {
      await db.update(
        'substitutions',
        values,
        where: 'id = ?',
        whereArgs: [assignment.id],
      );
    }
  }

  @override
  Future<void> cancelSubstitution(int id) async {
    final db = await database;
    await db.update(
      'substitutions',
      {
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
