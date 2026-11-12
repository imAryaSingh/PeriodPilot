import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/features/school/data/school_database.dart';
import 'package:teacher_substitute/features/school/domain/school_models.dart';

SchoolPeriod period({
  required int id,
  required int start,
  required int end,
  bool active = true,
}) => SchoolPeriod(
  id: id,
  name: 'Period $id',
  startMinute: start,
  endMinute: end,
  isActive: active,
  sortOrder: id,
);

void main() {
  group('validateSchoolPeriodConfiguration', () {
    test('allows ordered periods with gaps and inactive overlaps', () {
      expect(
        () => validateSchoolPeriodConfiguration([
          period(id: 1, start: 480, end: 525),
          period(id: 2, start: 540, end: 585),
          period(id: 3, start: 500, end: 550, active: false),
        ]),
        returnsNormally,
      );
    });

    test('rejects overlapping active periods', () {
      expect(
        () => validateSchoolPeriodConfiguration([
          period(id: 1, start: 480, end: 530),
          period(id: 2, start: 525, end: 570),
        ]),
        throwsA(isA<DuplicateSchoolRecordException>()),
      );
    });

    test('rejects duplicate ids, blank names, and invalid times', () {
      expect(
        () => validateSchoolPeriodConfiguration([
          period(id: 1, start: 480, end: 525),
          period(id: 1, start: 540, end: 585),
        ]),
        throwsA(isA<DuplicateSchoolRecordException>()),
      );
      expect(
        () => validateSchoolPeriodConfiguration([
          const SchoolPeriod(
            id: 3,
            name: ' ',
            startMinute: 480,
            endMinute: 525,
            isActive: true,
          ),
        ]),
        throwsA(isA<SchoolDataException>()),
      );
      expect(
        () => validateSchoolPeriodConfiguration([
          period(id: 4, start: 525, end: 480),
        ]),
        throwsA(isA<SchoolDataException>()),
      );
    });
  });

  group('model record parsing', () {
    test('reads active flags from bool or numeric values', () {
      expect(
        Teacher.fromMap({
          'id': 1,
          'full_name': 'Ada',
          'staff_code': 'A1',
          'email': '',
          'phone': '',
          'is_active': 0,
        }).isActive,
        isFalse,
      );
      expect(
        Subject.fromMap({
          'id': 2,
          'name': 'Math',
          'code': 'MTH',
          'is_active': true,
        }).isActive,
        isTrue,
      );
      expect(
        SchoolPeriod.fromMap({
          'id': 5,
          'name': 'P5',
          'start_minute': 480,
          'end_minute': 525,
          'isActive': 1,
        }).isActive,
        isTrue,
      );
      expect(
        SubstitutionAssignment.fromMap({
          'id': 3,
          'timetableEntryId': 10,
          'absentTeacherId': 1,
          'substituteTeacherId': 2,
          'date': '2026-11-09',
          'classId': 1,
          'sectionId': null,
          'subjectId': 8,
          'periodId': 2,
          'room': '',
          'is_override': 0,
          'status': 'assigned',
        }).isOverride,
        isFalse,
      );
    });
  });
}
