import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'github.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('user', abbr: 'u', help: 'GitHub username to evaluate')
    ..addFlag('live',
        abbr: 'l',
        help: 'Query live GitHub API instead of cache',
        defaultsTo: false);

  final results = parser.parse(args);
  final username = results['user'] as String? ??
      (results.rest.isNotEmpty ? results.rest.first : null);
  final isLive = results['live'] as bool;

  if (username == null || username.isEmpty) {
    print('Usage: dart run tool/check_user.dart <username> [--live]');
    exit(1);
  }

  print('=== Contributor Activity Lookup: @$username ===\n');

  // 1. Check current roster status
  String? currentRole;
  String? discordHandle;
  final contributorsYamlFile = File('data/contributors.yaml');
  if (contributorsYamlFile.existsSync()) {
    final doc = loadYaml(contributorsYamlFile.readAsStringSync()) as YamlMap;
    final info = findUserInfo(doc, username);
    currentRole = info.role;
    discordHandle = info.discord;
  }

  if (currentRole != null) {
    print('Current Roster Status: $currentRole');
    if (discordHandle != null && discordHandle.isNotEmpty) {
      print('Discord Username:      $discordHandle');
    }
  } else {
    print('Current Roster Status: External Contributor (Not enrolled in org)');
  }

  // 2. Fetch or retrieve activity stats
  var stats = <String, int>{};

  if (isLive) {
    print('Querying live GitHub API for @$username over the last 12 months...');
    final client = GitHubClient();
    try {
      final now = DateTime.now().toUtc();
      final oneYearAgo = now.subtract(const Duration(days: 365));
      stats =
          await client.getUserActivity(username, since: oneYearAgo, until: now);
    } finally {
      client.close();
    }
  } else {
    final summaryFile = File('data/activity_summary.json');
    if (summaryFile.existsSync()) {
      try {
        final summary =
            jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
        if (summary.containsKey(username)) {
          stats = Map<String, int>.from(summary[username] as Map);
        }
      } catch (_) {}
    }
  }

  final total = stats['total'] ?? 0;
  final prs = stats['merged_prs'] ?? 0;
  final issues = stats['issues'] ?? 0;
  final reviews = stats['reviews'] ?? 0;

  print('\n12-Month Activity Summary:');
  print('  • Merged PRs Authored: $prs');
  print('  • Issues Created:      $issues');
  print('  • Merged PR Reviews:   $reviews');
  print('  • Total Contributions: $total');

  print('\nQualification Assessment:');
  print('  ${assessQualification(total: total, mergedPrs: prs)}');
}

/// Evaluates 12-month activity counts against Contributor Ladder tier thresholds.
String assessQualification({required int total, required int mergedPrs}) {
  if (total >= 30 && mergedPrs >= 10) {
    return '🎉 Qualifies for: Committer (≥ 30 contributions, ≥ 10 merged PRs)';
  } else if (total >= 10) {
    return '✅ Qualifies for: Reviewer (≥ 10 qualifying contributions)';
  } else if (total > 0) {
    return '🌱 Qualifies for: Contributor (< 10 contributions)';
  } else {
    return '⏳ Inactive over the last 12 months (Dasher Emeritus candidate if currently on ladder)';
  }
}

({String? role, String? discord}) findUserInfo(YamlMap doc, String username) {
  final maintainers = doc['maintainers'] as YamlMap?;
  if (maintainers != null) {
    final googlers = maintainers['googlers'] as YamlList? ?? [];
    for (final g in googlers) {
      if ((g['username'] as String).toLowerCase() == username.toLowerCase()) {
        return (
          role: 'Maintainer (Google)',
          discord: g['discord'] as String?,
        );
      }
    }
    final partners = maintainers['partners'] as YamlList? ?? [];
    for (final p in partners) {
      if ((p['username'] as String).toLowerCase() == username.toLowerCase()) {
        return (
          role: 'Maintainer (Partner)',
          discord: p['discord'] as String?,
        );
      }
    }
  }

  final committers = doc['committers'] as YamlList? ?? [];
  for (final c in committers) {
    if ((c['username'] as String).toLowerCase() == username.toLowerCase()) {
      return (
        role: 'Committer (@flutter/committers)',
        discord: c['discord'] as String?,
      );
    }
  }

  final reviewers = doc['reviewers'] as YamlList? ?? [];
  for (final r in reviewers) {
    if ((r['username'] as String).toLowerCase() == username.toLowerCase()) {
      return (
        role: 'Reviewer (@flutter/reviewers)',
        discord: r['discord'] as String?,
      );
    }
  }

  final emeriti = doc['dash_emeritus'] as YamlList? ?? [];
  for (final e in emeriti) {
    if ((e['username'] as String).toLowerCase() == username.toLowerCase()) {
      return (
        role: 'Dasher Emeritus',
        discord: e['discord'] as String?,
      );
    }
  }

  return (role: null, discord: null);
}
