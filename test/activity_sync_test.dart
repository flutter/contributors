import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../tool/sync_activity.dart';

void main() {
  group('Activity Sync Logic', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('activity_sync_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'recomputeActivitySummary correctly sums multiple weekly files and sorts keys',
        () {
      final activityDir = Directory('${tempDir.path}/activity')..createSync();
      final summaryFile = File('${tempDir.path}/activity_summary.json');

      final week1 = {
        'zeta': {'merged_prs': 2, 'issues': 1, 'reviews': 3, 'total': 6},
        'alpha': {'merged_prs': 1, 'issues': 0, 'reviews': 0, 'total': 1},
      };

      final week2 = {
        'alpha': {'merged_prs': 2, 'issues': 1, 'reviews': 1, 'total': 4},
        'beta': {'merged_prs': 0, 'issues': 2, 'reviews': 0, 'total': 2},
      };

      File('${activityDir.path}/2026-W30.json')
          .writeAsStringSync(jsonEncode(week1));
      File('${activityDir.path}/2026-W31.json')
          .writeAsStringSync(jsonEncode(week2));

      recomputeActivitySummary(activityDir, outputFile: summaryFile);

      expect(summaryFile.existsSync(), isTrue);
      final rawContent = summaryFile.readAsStringSync();
      expect(rawContent.endsWith('\n'), isTrue);

      final summary = jsonDecode(rawContent) as Map<String, dynamic>;

      // Verify keys sorted alphabetically
      expect(summary.keys.toList(), equals(['alpha', 'beta', 'zeta']));

      // Verify stats totals
      expect(
          summary['alpha'],
          equals({
            'merged_prs': 3,
            'issues': 1,
            'reviews': 1,
            'total': 5,
          }));
      expect(
          summary['beta'],
          equals({
            'merged_prs': 0,
            'issues': 2,
            'reviews': 0,
            'total': 2,
          }));
      expect(
          summary['zeta'],
          equals({
            'merged_prs': 2,
            'issues': 1,
            'reviews': 3,
            'total': 6,
          }));
    });

    test(
        'pruneOldActivityFiles removes files older than 52 weeks based on filename',
        () {
      final activityDir = Directory('${tempDir.path}/activity')..createSync();
      final refDate = DateTime.utc(2026, 8, 3); // 2026-W32

      // Create 55 weekly files (from 2025-W25 to 2026-W32)
      for (var i = 0; i < 55; i++) {
        final date = refDate.subtract(Duration(days: i * 7));
        final wStr = formatIsoWeek(date);
        File('${activityDir.path}/$wStr.json').writeAsStringSync('{}');
      }

      final beforeCount = activityDir.listSync().whereType<File>().length;
      expect(beforeCount, equals(55));

      final pruned = pruneOldActivityFiles(activityDir, referenceDate: refDate);
      expect(pruned, equals(3)); // 55 - 52 = 3 oldest pruned

      final remaining = activityDir.listSync().whereType<File>().length;
      expect(remaining, equals(52));
    });
  });
}
