import 'package:test/test.dart';
import '../tool/sync_activity.dart';

void main() {
  group('ISO 8601 Week Utilities', () {
    test('formats standard mid-year dates', () {
      expect(formatIsoWeek(DateTime.utc(2026, 8, 3)), equals('2026-W32'));
      expect(formatIsoWeek(DateTime.utc(2026, 7, 27)), equals('2026-W31'));
      expect(formatIsoWeek(DateTime.utc(2025, 8, 1)), equals('2025-W31'));
    });

    test(
        'handles year-boundary edge case: January dates belonging to previous year',
        () {
      // 2023-01-01 was Sunday; its Thursday was in 2022 -> 2022-W52
      expect(formatIsoWeek(DateTime.utc(2023, 1, 1)), equals('2022-W52'));
      // 2021-01-01 was Friday; its Thursday was in 2020 -> 2020-W53
      expect(formatIsoWeek(DateTime.utc(2021, 1, 1)), equals('2020-W53'));
      // 2021-01-03 was Sunday -> 2020-W53
      expect(formatIsoWeek(DateTime.utc(2021, 1, 3)), equals('2020-W53'));
      // 2021-01-04 was Monday -> 2021-W01
      expect(formatIsoWeek(DateTime.utc(2021, 1, 4)), equals('2021-W01'));
    });

    test(
        'handles year-boundary edge case: December dates belonging to next year',
        () {
      // 2024-12-30 was Monday; its Thursday is 2025-01-02 -> 2025-W01
      expect(formatIsoWeek(DateTime.utc(2024, 12, 30)), equals('2025-W01'));
      expect(formatIsoWeek(DateTime.utc(2024, 12, 31)), equals('2025-W01'));
      // 2024-12-29 was Sunday -> 2024-W52
      expect(formatIsoWeek(DateTime.utc(2024, 12, 29)), equals('2024-W52'));
    });

    test('startOfIsoWeek returns Monday 00:00:00 UTC', () {
      // Monday
      final mon = DateTime.utc(2026, 8, 3, 14, 30);
      expect(startOfIsoWeek(mon), equals(DateTime.utc(2026, 8, 3)));

      // Wednesday
      final wed = DateTime.utc(2026, 8, 5, 23, 59);
      expect(startOfIsoWeek(wed), equals(DateTime.utc(2026, 8, 3)));

      // Sunday
      final sun = DateTime.utc(2026, 8, 9, 12, 0);
      expect(startOfIsoWeek(sun), equals(DateTime.utc(2026, 8, 3)));
    });

    test('parseIsoWeekStart accurately parses ISO week to Monday start date',
        () {
      expect(parseIsoWeekStart('2026-W32'), equals(DateTime.utc(2026, 8, 3)));
      expect(parseIsoWeekStart('2025-W01'), equals(DateTime.utc(2024, 12, 30)));
      expect(parseIsoWeekStart('2022-W52'), equals(DateTime.utc(2022, 12, 26)));

      // Round-trip verification
      for (final week in ['2025-W31', '2025-W52', '2026-W01', '2026-W32']) {
        final start = parseIsoWeekStart(week);
        expect(formatIsoWeek(start), equals(week));
      }
    });
  });
}
