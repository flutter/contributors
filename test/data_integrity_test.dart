import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Dataset Integrity', () {
    final activityDir = Directory('data/activity');
    final summaryFile = File('data/activity_summary.json');

    test('all weekly activity snapshot files contain valid schema and math',
        () {
      expect(activityDir.existsSync(), isTrue);
      final files = activityDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(files, isNotEmpty);

      for (final file in files) {
        if (!file.path.endsWith('.json')) continue;
        final raw = file.readAsStringSync();
        final content = jsonDecode(raw) as Map<String, dynamic>;

        for (final entry in content.entries) {
          final user = entry.key;
          final stats = entry.value as Map<String, dynamic>;

          expect(user, isNotEmpty);
          final mergedPrs = stats['merged_prs'] as int?;
          final issues = stats['issues'] as int?;
          final reviews = stats['reviews'] as int?;
          final total = stats['total'] as int?;

          expect(mergedPrs, isNotNull);
          expect(issues, isNotNull);
          expect(reviews, isNotNull);
          expect(total, isNotNull);

          expect(mergedPrs!, isNonNegative);
          expect(issues!, isNonNegative);
          expect(reviews!, isNonNegative);
          expect(total!, equals(mergedPrs + issues + reviews),
              reason:
                  'Total must equal sum of PRs, issues, and reviews for user $user in ${file.path}');
        }
      }
    });

    test(
        'activity_summary.json matches the exact sum of all weekly activity files',
        () {
      expect(summaryFile.existsSync(), isTrue);
      final summaryContent =
          jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;

      final files = activityDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final expectedTotals = <String, Map<String, int>>{};

      for (final file in files) {
        if (!file.path.endsWith('.json')) continue;
        final content =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final entry in content.entries) {
          final user = entry.key;
          final stats = entry.value as Map<String, dynamic>;
          expectedTotals.putIfAbsent(
              user,
              () => {
                    'merged_prs': 0,
                    'issues': 0,
                    'reviews': 0,
                    'total': 0,
                  });
          expectedTotals[user]!['merged_prs'] =
              (expectedTotals[user]!['merged_prs'] ?? 0) +
                  (stats['merged_prs'] as int? ?? 0);
          expectedTotals[user]!['issues'] =
              (expectedTotals[user]!['issues'] ?? 0) +
                  (stats['issues'] as int? ?? 0);
          expectedTotals[user]!['reviews'] =
              (expectedTotals[user]!['reviews'] ?? 0) +
                  (stats['reviews'] as int? ?? 0);
          expectedTotals[user]!['total'] =
              (expectedTotals[user]!['total'] ?? 0) +
                  (stats['total'] as int? ?? 0);
        }
      }

      expect(summaryContent.length, equals(expectedTotals.length));

      for (final entry in expectedTotals.entries) {
        final user = entry.key;
        final expected = entry.value;
        final actual = summaryContent[user] as Map<String, dynamic>?;

        expect(actual, isNotNull,
            reason: 'User $user missing in activity_summary.json');
        expect(actual!['merged_prs'], equals(expected['merged_prs']),
            reason: 'merged_prs mismatch for $user');
        expect(actual['issues'], equals(expected['issues']),
            reason: 'issues mismatch for $user');
        expect(actual['reviews'], equals(expected['reviews']),
            reason: 'reviews mismatch for $user');
        expect(actual['total'], equals(expected['total']),
            reason: 'total mismatch for $user');
      }
    });
  });
}
