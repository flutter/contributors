import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:intl/intl.dart';
import 'bots.dart';
import 'github.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('days',
        abbr: 'd',
        help: 'Number of past days of activity to sync (default: 1 for daily sync)',
        defaultsTo: '1');

  final results = parser.parse(args);
  final days = int.tryParse(results['days'] as String) ?? 1;

  print('=== Contributor Activity Sync ===');

  final now = DateTime.now().toUtc();
  final sinceDate = now.subtract(Duration(days: days));
  final weekString = _formatIsoWeek(now);
  print('Syncing activity for past $days day(s) (${DateFormat('yyyy-MM-dd HH:mm').format(sinceDate)} to ${DateFormat('yyyy-MM-dd HH:mm').format(now)} UTC)...');

  final client = GitHubClient();

  try {
    // 1. Fetch team members to exclude Googlers, Partners, and Robots from activity queries
    Set<String> googlers = {};
    Set<String> partners = {};
    try {
      googlers = await client.getTeamMembers('flutter', 'googlers');
      partners = await client.getTeamMembers('flutter', 'partners');
      await loadRobotsTeam(client);
    } catch (_) {
      // Fallback if running without elevated team read token
    }
    final maintainers = {...googlers, ...partners};
    print('Loaded Maintainer exclusions (${maintainers.length} members) and @flutter/robots team.');

    // 2. Fetch merged PRs, reviews, and issues across all public repositories in org:flutter
    final activeStats = <String, Map<String, int>>{};

    final sinceIso = sinceDate.toIso8601String().split('T').first;
    final untilIso = now.toIso8601String().split('T').first;

    stdout.write('Scanning all public repositories in org:flutter... ');
    final prQuery = 'org:flutter is:public is:pr is:merged merged:$sinceIso..$untilIso';
    final issueQuery = 'org:flutter is:public is:issue created:$sinceIso..$untilIso';

    // Paged PR search
    String? prCursor;
    var hasNextPrPage = true;
    while (hasNextPrPage) {
      try {
        final prData = await client.queryGraphQL('''
query(\$query: String!, \$cursor: String) {
  search(query: \$query, type: ISSUE, first: 100, after: \$cursor) {
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on PullRequest {
        author { login }
        reviews(first: 20) {
          nodes {
            author { login }
            state
          }
        }
      }
    }
  }
}
''', variables: {'query': prQuery, 'cursor': prCursor});

        final search = prData['search'] as Map<String, dynamic>?;
        final prNodes = search?['nodes'] as List? ?? [];
        for (final node in prNodes) {
          final author = node['author']?['login'] as String?;
          if (author != null && !isBot(author) && !maintainers.contains(author)) {
            activeStats.putIfAbsent(author, () => {'merged_prs': 0, 'issues': 0, 'reviews': 0, 'total': 0});
            activeStats[author]!['merged_prs'] = (activeStats[author]!['merged_prs'] ?? 0) + 1;
            activeStats[author]!['total'] = (activeStats[author]!['total'] ?? 0) + 1;
          }

          final reviews = node['reviews']?['nodes'] as List? ?? [];
          for (final rev in reviews) {
            final revAuthor = rev['author']?['login'] as String?;
            if (revAuthor != null &&
                revAuthor != author &&
                !isBot(revAuthor) &&
                !maintainers.contains(revAuthor)) {
              activeStats.putIfAbsent(revAuthor, () => {'merged_prs': 0, 'issues': 0, 'reviews': 0, 'total': 0});
              activeStats[revAuthor]!['reviews'] = (activeStats[revAuthor]!['reviews'] ?? 0) + 1;
              activeStats[revAuthor]!['total'] = (activeStats[revAuthor]!['total'] ?? 0) + 1;
            }
          }
        }

        final pageInfo = search?['pageInfo'] as Map<String, dynamic>?;
        hasNextPrPage = pageInfo?['hasNextPage'] as bool? ?? false;
        prCursor = pageInfo?['endCursor'] as String?;
      } catch (e) {
        print('Warning: Search query error for PRs: $e');
        hasNextPrPage = false;
      }
    }

    // Paged Issue search
    String? issueCursor;
    var hasNextIssuePage = true;
    while (hasNextIssuePage) {
      try {
        final issueData = await client.queryGraphQL('''
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

        final search = issueData['search'] as Map<String, dynamic>?;
        final issueNodes = search?['nodes'] as List? ?? [];
        for (final node in issueNodes) {
          final author = node['author']?['login'] as String?;
          if (author != null && !isBot(author) && !maintainers.contains(author)) {
            activeStats.putIfAbsent(author, () => {'merged_prs': 0, 'issues': 0, 'reviews': 0, 'total': 0});
            activeStats[author]!['issues'] = (activeStats[author]!['issues'] ?? 0) + 1;
            activeStats[author]!['total'] = (activeStats[author]!['total'] ?? 0) + 1;
          }
        }

        final pageInfo = search?['pageInfo'] as Map<String, dynamic>?;
        hasNextIssuePage = pageInfo?['hasNextPage'] as bool? ?? false;
        issueCursor = pageInfo?['endCursor'] as String?;
      } catch (e) {
        print('Warning: Search query error for Issues: $e');
        hasNextIssuePage = false;
      }
    }
    print('Done.');

    // 3. Save weekly activity file data/activity/YYYY-Wxx.json
    final activityDir = Directory('data/activity');
    if (!activityDir.existsSync()) {
      activityDir.createSync(recursive: true);
    }
    final weekFile = File('data/activity/$weekString.json');
    Map<String, dynamic> existingWeekStats = {};
    if (weekFile.existsSync()) {
      try {
        existingWeekStats = jsonDecode(weekFile.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }

    // Merge new activeStats into existing week
    for (final entry in activeStats.entries) {
      final user = entry.key;
      final stats = entry.value;
      if (!existingWeekStats.containsKey(user)) {
        existingWeekStats[user] = stats;
      } else {
        final current = existingWeekStats[user] as Map<String, dynamic>;
        current['merged_prs'] = (current['merged_prs'] as int? ?? 0) + (stats['merged_prs'] ?? 0);
        current['issues'] = (current['issues'] as int? ?? 0) + (stats['issues'] ?? 0);
        current['reviews'] = (current['reviews'] as int? ?? 0) + (stats['reviews'] ?? 0);
        current['total'] = (current['total'] as int? ?? 0) + (stats['total'] ?? 0);
      }
    }

    weekFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(existingWeekStats));
    print('Recorded activity in ${weekFile.path} (${activeStats.length} active contributors today).');

    // 4. Prune files older than 52 weeks
    _pruneOldActivityFiles(activityDir, now);

    // 5. Recompute and update data/activity_summary.json
    _recomputeActivitySummary(activityDir);
  } finally {
    client.close();
  }
}

String _formatIsoWeek(DateTime date) {
  final year = date.year;
  final dayOfYear = int.parse(DateFormat('D').format(date));
  final weekNumber = ((dayOfYear - date.weekday + 10) / 7).floor();
  final weekPad = weekNumber.toString().padLeft(2, '0');
  return '$year-W$weekPad';
}

void _pruneOldActivityFiles(Directory activityDir, DateTime now) {
  final files = activityDir.listSync().whereType<File>().toList();
  var pruned = 0;
  for (final file in files) {
    if (!file.path.endsWith('.json')) continue;
    final stat = file.statSync();
    final ageInDays = now.difference(stat.modified).inDays;
    if (ageInDays > 365) {
      file.deleteSync();
      pruned++;
    }
  }
  if (pruned > 0) {
    print('Pruned $pruned activity files older than 52 weeks.');
  }
}

void _recomputeActivitySummary(Directory activityDir) {
  final files = activityDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) return;

  final summary = <String, Map<String, int>>{};

  // Compute summary purely from the active weekly snapshot files in data/activity/
  for (final file in files) {
    if (!file.path.endsWith('.json')) continue;
    try {
      final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in content.entries) {
        final user = entry.key;
        final stats = entry.value as Map<String, dynamic>;
        summary.putIfAbsent(user, () => {'merged_prs': 0, 'issues': 0, 'reviews': 0, 'total': 0});
        summary[user]!['merged_prs'] = (summary[user]!['merged_prs'] ?? 0) + (stats['merged_prs'] as int? ?? 0);
        summary[user]!['issues'] = (summary[user]!['issues'] ?? 0) + (stats['issues'] as int? ?? 0);
        summary[user]!['reviews'] = (summary[user]!['reviews'] ?? 0) + (stats['reviews'] as int? ?? 0);
        summary[user]!['total'] = (summary[user]!['total'] ?? 0) + (stats['total'] as int? ?? 0);
      }
    } catch (_) {}
  }

  final summaryFile = File('data/activity_summary.json');
  summaryFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary));
  print('Updated ${summaryFile.path} from ${files.length} weekly snapshot files.');
}
