import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:intl/intl.dart';
import 'bots.dart';
import 'github.dart';

/// Formats a [DateTime] into an ISO 8601 week string, e.g. '2026-W31'.
String formatIsoWeek(DateTime date) {
  final utc = date.toUtc();
  // Find Thursday of the current week (which determines the ISO year).
  final thursday = utc.add(Duration(days: 4 - utc.weekday));
  final isoYear = thursday.year;
  // First Thursday of the ISO year is always in Week 1.
  final firstThursdayOfYear = DateTime.utc(isoYear, 1, 4);
  final firstThursdayOfWeek =
      firstThursdayOfYear.add(Duration(days: 4 - firstThursdayOfYear.weekday));
  final weekNumber =
      1 + ((thursday.difference(firstThursdayOfWeek).inDays) / 7).round();
  final weekPad = weekNumber.toString().padLeft(2, '0');
  return '$isoYear-W$weekPad';
}

/// Returns the start (Monday 00:00:00 UTC) of the ISO week containing [date].
DateTime startOfIsoWeek(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day)
      .subtract(Duration(days: utc.weekday - 1));
}

/// Returns the start (Monday 00:00:00 UTC) for a given ISO week string, e.g. '2026-W31'.
DateTime parseIsoWeekStart(String weekString) {
  final parts = weekString.split('-W');
  if (parts.length != 2) {
    throw FormatException('Invalid ISO week format: $weekString');
  }
  final year = int.parse(parts[0]);
  final week = int.parse(parts[1]);
  final jan4 = DateTime.utc(year, 1, 4);
  final firstMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
  return firstMonday.add(Duration(days: (week - 1) * 7));
}

/// Prunes weekly activity snapshot files older than 52 weeks based on their ISO week filenames.
int pruneOldActivityFiles(Directory activityDir, {DateTime? referenceDate}) {
  if (!activityDir.existsSync()) return 0;
  final now = (referenceDate ?? DateTime.now()).toUtc();
  final currentWeekStart = startOfIsoWeek(now);
  final files = activityDir.listSync().whereType<File>().toList();
  var pruned = 0;

  for (final file in files) {
    final fileName = file.uri.pathSegments.last;
    if (!fileName.endsWith('.json')) continue;
    final weekString = fileName.replaceAll('.json', '');
    try {
      final weekStart = parseIsoWeekStart(weekString);
      final ageInWeeks =
          (currentWeekStart.difference(weekStart).inDays / 7).floor();
      // Keep up to 52 weeks of activity (weeks 0 through 51)
      if (ageInWeeks >= 52) {
        file.deleteSync();
        pruned++;
      }
    } catch (_) {
      // Skip files that do not match the YYYY-Wxx format
    }
  }

  if (pruned > 0) {
    print('Pruned $pruned activity files older than 52 weeks.');
  }
  return pruned;
}

/// Recomputes [outputFile] (default: `data/activity_summary.json`) by summing
/// all active weekly snapshot files in [activityDir].
void recomputeActivitySummary(Directory activityDir, {File? outputFile}) {
  final targetFile = outputFile ?? File('data/activity_summary.json');
  final files = activityDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) return;

  final summary = <String, Map<String, int>>{};

  for (final file in files) {
    if (!file.path.endsWith('.json')) continue;
    try {
      final content =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in content.entries) {
        final user = entry.key;
        final stats = entry.value as Map<String, dynamic>;
        summary.putIfAbsent(
            user,
            () => {
                  'merged_prs': 0,
                  'issues': 0,
                  'reviews': 0,
                  'total': 0,
                });
        summary[user]!['merged_prs'] = (summary[user]!['merged_prs'] ?? 0) +
            (stats['merged_prs'] as int? ?? 0);
        summary[user]!['issues'] =
            (summary[user]!['issues'] ?? 0) + (stats['issues'] as int? ?? 0);
        summary[user]!['reviews'] =
            (summary[user]!['reviews'] ?? 0) + (stats['reviews'] as int? ?? 0);
        summary[user]!['total'] =
            (summary[user]!['total'] ?? 0) + (stats['total'] as int? ?? 0);
      }
    } catch (e) {
      print('Warning: Failed to parse ${file.path}: $e');
    }
  }

  // Sort contributors alphabetically for deterministic output and minimal git diffs
  final sortedSummary = SplayTreeMap<String, Map<String, int>>.from(summary);

  targetFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(sortedSummary)}\n');
  print(
      'Updated ${targetFile.path} from ${files.length} weekly snapshot files.');
}

/// Fetches activity for a given date range [since]..[until] across public repositories in `org:flutter`.
Future<Map<String, Map<String, int>>> fetchActivityForRange(
  GitHubClient client, {
  required DateTime since,
  required DateTime until,
  required Set<String> maintainers,
}) async {
  final activeStats = <String, Map<String, int>>{};

  final sinceIso = '${since.toUtc().toIso8601String().split('.').first}Z';
  final untilIso = '${until.toUtc().toIso8601String().split('.').first}Z';

  final prQuery =
      'org:flutter is:public is:pr is:merged merged:$sinceIso..$untilIso';
  final issueQuery =
      'org:flutter is:public is:issue created:$sinceIso..$untilIso';

  // 1. Paged PR search
  String? prCursor;
  var hasNextPrPage = true;
  while (hasNextPrPage) {
    Map<String, dynamic>? prData;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        prData = await client.queryGraphQL('''
query(\$query: String!, \$cursor: String) {
  search(query: \$query, type: ISSUE, first: 100, after: \$cursor) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on PullRequest {
        author { login }
        reviews(first: 50) {
          nodes {
            author { login }
          }
        }
      }
    }
  }
}
''', variables: {'query': prQuery, 'cursor': prCursor});
        break;
      } catch (e) {
        if (attempt == 3) {
          throw Exception('Failed to fetch PRs after 3 attempts: $e');
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }

    final search = prData?['search'] as Map<String, dynamic>?;
    final prNodes = search?['nodes'] as List? ?? [];
    for (final node in prNodes) {
      final author = node['author']?['login'] as String?;
      if (author != null &&
          !isExcludedAccount(author) &&
          !maintainers.contains(author)) {
        activeStats.putIfAbsent(
            author,
            () => {
                  'merged_prs': 0,
                  'issues': 0,
                  'reviews': 0,
                  'total': 0,
                });
        activeStats[author]!['merged_prs'] =
            (activeStats[author]!['merged_prs'] ?? 0) + 1;
        activeStats[author]!['total'] =
            (activeStats[author]!['total'] ?? 0) + 1;
      }

      // Deduplicate reviews per pull request: 1 review credit per unique non-author reviewer
      final reviews = node['reviews']?['nodes'] as List? ?? [];
      final uniqueReviewers = <String>{};
      for (final rev in reviews) {
        final revAuthor = rev['author']?['login'] as String?;
        if (revAuthor != null &&
            revAuthor != author &&
            !isExcludedAccount(revAuthor) &&
            !maintainers.contains(revAuthor)) {
          uniqueReviewers.add(revAuthor);
        }
      }

      for (final revAuthor in uniqueReviewers) {
        activeStats.putIfAbsent(
            revAuthor,
            () => {
                  'merged_prs': 0,
                  'issues': 0,
                  'reviews': 0,
                  'total': 0,
                });
        activeStats[revAuthor]!['reviews'] =
            (activeStats[revAuthor]!['reviews'] ?? 0) + 1;
        activeStats[revAuthor]!['total'] =
            (activeStats[revAuthor]!['total'] ?? 0) + 1;
      }
    }

    final pageInfo = search?['pageInfo'] as Map<String, dynamic>?;
    hasNextPrPage = pageInfo?['hasNextPage'] as bool? ?? false;
    prCursor = pageInfo?['endCursor'] as String?;
  }

  // 2. Paged Issue search
  String? issueCursor;
  var hasNextIssuePage = true;
  while (hasNextIssuePage) {
    Map<String, dynamic>? issueData;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        issueData = await client.queryGraphQL('''
query(\$query: String!, \$cursor: String) {
  search(query: \$query, type: ISSUE, first: 100, after: \$cursor) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on Issue {
        author { login }
      }
    }
  }
}
''', variables: {'query': issueQuery, 'cursor': issueCursor});
        break;
      } catch (e) {
        if (attempt == 3) {
          throw Exception('Failed to fetch issues after 3 attempts: $e');
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }

    final search = issueData?['search'] as Map<String, dynamic>?;
    final issueNodes = search?['nodes'] as List? ?? [];
    for (final node in issueNodes) {
      final author = node['author']?['login'] as String?;
      if (author != null &&
          !isExcludedAccount(author) &&
          !maintainers.contains(author)) {
        activeStats.putIfAbsent(
            author,
            () => {
                  'merged_prs': 0,
                  'issues': 0,
                  'reviews': 0,
                  'total': 0,
                });
        activeStats[author]!['issues'] =
            (activeStats[author]!['issues'] ?? 0) + 1;
        activeStats[author]!['total'] =
            (activeStats[author]!['total'] ?? 0) + 1;
      }
    }

    final pageInfo = search?['pageInfo'] as Map<String, dynamic>?;
    hasNextIssuePage = pageInfo?['hasNextPage'] as bool? ?? false;
    issueCursor = pageInfo?['endCursor'] as String?;
  }

  return activeStats;
}

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('days',
        abbr: 'd',
        help:
            'Number of past days of activity to sync (default: 7 to self-heal and cover week boundaries)',
        defaultsTo: '7')
    ..addOption('week',
        abbr: 'w', help: 'Specific ISO week to sync (e.g. 2026-W32)');

  final results = parser.parse(args);
  final specifiedWeek = results['week'] as String?;
  final days = int.tryParse(results['days'] as String) ?? 7;

  print('=== Contributor Activity Sync ===');

  final now = DateTime.now().toUtc();
  final client = GitHubClient();

  try {
    // 1. Fetch team members to exclude Googlers, Partners, and Robots
    Set<String> googlers = {};
    Set<String> partners = {};
    try {
      googlers = await client.getTeamMembers('flutter', 'googlers');
      partners = await client.getTeamMembers('flutter', 'partners');
      await loadRobotsTeam(client);
    } catch (_) {
      // Elevated team read permissions may not be available with default GITHUB_TOKEN
    }

    final maintainers = {...googlers, ...partners};
    if (maintainers.isEmpty) {
      print(
          'Notice: Maintainer teams returned 0 members (normal for standard CI GITHUB_TOKEN).');
    } else {
      print(
          'Loaded Maintainer exclusions (${maintainers.length} members) and @flutter/robots team.');
    }

    final activityDir = Directory('data/activity');
    if (!activityDir.existsSync()) {
      activityDir.createSync(recursive: true);
    }

    // Determine week(s) to sync
    final weeksToSync = <String, ({DateTime since, DateTime until})>{};

    if (specifiedWeek != null && specifiedWeek.isNotEmpty) {
      final weekStart = parseIsoWeekStart(specifiedWeek);
      final weekEnd = weekStart.add(const Duration(days: 7));
      final untilDate = now.isBefore(weekEnd) ? now : weekEnd;
      weeksToSync[specifiedWeek] = (since: weekStart, until: untilDate);
    } else {
      // By default sync the current ISO week from Monday 00:00:00 UTC to now
      final currentWeekStart = startOfIsoWeek(now);
      final currentWeekString = formatIsoWeek(now);
      weeksToSync[currentWeekString] = (since: currentWeekStart, until: now);

      // If requested days extends into prior week(s), also sync them
      final earliestDate = now.subtract(Duration(days: days > 0 ? days : 7));
      if (earliestDate.isBefore(currentWeekStart)) {
        var cursorDate = earliestDate;
        while (cursorDate.isBefore(currentWeekStart)) {
          final wStr = formatIsoWeek(cursorDate);
          final wStart = startOfIsoWeek(cursorDate);
          final wEnd = wStart.add(const Duration(days: 7));
          weeksToSync[wStr] = (since: wStart, until: wEnd);
          cursorDate = cursorDate.add(const Duration(days: 7));
        }
      }
    }

    for (final entry in weeksToSync.entries) {
      final weekString = entry.key;
      final range = entry.value;
      print(
          'Syncing ISO week $weekString (${DateFormat('yyyy-MM-dd HH:mm').format(range.since)} to ${DateFormat('yyyy-MM-dd HH:mm').format(range.until)} UTC)...');

      final stats = await fetchActivityForRange(
        client,
        since: range.since,
        until: range.until,
        maintainers: maintainers,
      );

      final weekFile = File('data/activity/$weekString.json');
      final sortedStats = SplayTreeMap<String, Map<String, int>>.from(stats);
      weekFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(sortedStats)}\n');
      print('Wrote ${stats.length} active contributors to ${weekFile.path}.');
    }

    // 4. Prune files older than 52 weeks based on filename ISO week
    pruneOldActivityFiles(activityDir, referenceDate: now);

    // 5. Recompute and update data/activity_summary.json
    recomputeActivitySummary(activityDir);
  } finally {
    client.close();
  }
}
