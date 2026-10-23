// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../tool/github.dart';
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

    test(
        'pruneOldActivityFiles skips invalid filenames and handles missing dir',
        () {
      final missingDir = Directory('${tempDir.path}/non_existent');
      expect(pruneOldActivityFiles(missingDir), equals(0));

      final activityDir = Directory('${tempDir.path}/activity')..createSync();
      File('${activityDir.path}/not-a-week.json').writeAsStringSync('{}');
      File('${activityDir.path}/README.txt').writeAsStringSync('ignore');
      expect(
          pruneOldActivityFiles(activityDir,
              referenceDate: DateTime.utc(2026, 8, 3)),
          equals(0));
    });

    test(
        'fetchActivityForRange aggregates PRs, deduplicated reviews, and issues while excluding bots and ghost',
        () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final variables = body['variables'] as Map<String, dynamic>;
        final query = variables['query'] as String;

        if (query.contains('is:pr')) {
          return http.Response(
            jsonEncode({
              'data': {
                'search': {
                  'pageInfo': {'hasNextPage': false, 'endCursor': null},
                  'nodes': [
                    {
                      'author': {'login': 'alice'},
                      'reviews': {
                        'nodes': [
                          // Self-review by author should be ignored
                          {
                            'author': {'login': 'alice'}
                          },
                          // Duplicate review by bob on the same PR should count once
                          {
                            'author': {'login': 'bob'}
                          },
                          {
                            'author': {'login': 'bob'}
                          },
                          // Maintainer review should be recorded
                          {
                            'author': {'login': 'Piinks'}
                          },
                          // Bot review should be skipped
                          {
                            'author': {'login': 'auto-submit'}
                          },
                        ]
                      }
                    },
                    // PR by maintainer and community review on it should both be recorded
                    {
                      'author': {'login': 'Piinks'},
                      'reviews': {
                        'nodes': [
                          {
                            'author': {'login': 'alice'}
                          }
                        ]
                      }
                    },
                    // PR by bot should be skipped
                    {
                      'author': {'login': 'engine-flutter-autoroll'},
                      'reviews': {'nodes': <Map<String, dynamic>>[]}
                    },
                  ]
                }
              }
            }),
            200,
          );
        } else {
          // Issue search
          return http.Response(
            jsonEncode({
              'data': {
                'search': {
                  'pageInfo': {'hasNextPage': false, 'endCursor': null},
                  'nodes': [
                    {
                      'author': {'login': 'alice'}
                    },
                    {
                      'author': {'login': 'charlie'}
                    },
                    // Ghost issue should be skipped
                    {
                      'author': {'login': 'ghost'}
                    },
                    {
                      'author': {'login': 'Piinks'}
                    },
                  ]
                }
              }
            }),
            200,
          );
        }
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final stats = await fetchActivityForRange(
        client,
        since: DateTime.utc(2026, 8, 1),
        until: DateTime.utc(2026, 8, 8),
      );

      expect(
          stats['alice'],
          equals({
            'merged_prs': 1,
            'issues': 1,
            'reviews': 1,
            'total': 3,
          }));
      expect(
          stats['bob'],
          equals({
            'merged_prs': 0,
            'issues': 0,
            'reviews': 1,
            'total': 1,
          }));
      expect(
          stats['charlie'],
          equals({
            'merged_prs': 0,
            'issues': 1,
            'reviews': 0,
            'total': 1,
          }));
      expect(
          stats['Piinks'],
          equals({
            'merged_prs': 1,
            'issues': 1,
            'reviews': 1,
            'total': 3,
          }));
      expect(stats.containsKey('auto-submit'), isFalse);
      expect(stats.containsKey('engine-flutter-autoroll'), isFalse);
      expect(stats.containsKey('ghost'), isFalse);
    });
  });
}
