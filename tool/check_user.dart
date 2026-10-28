// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'contributors_roster.dart';
import 'github.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('user', abbr: 'u', help: 'GitHub username to evaluate')
    ..addFlag(
      'live',
      abbr: 'l',
      help: 'Query live GitHub API instead of cache',
      defaultsTo: false,
    );

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
    final roster =
        ContributorsRoster.parse(contributorsYamlFile.readAsStringSync());
    final info = findUserInfo(roster, username);
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

/// Looks up [username] in [roster] and returns their formatted ladder role and
/// Discord handle if present.
({String? role, String? discord}) findUserInfo(
  ContributorsRoster roster,
  String username,
) {
  final target = username.toLowerCase();
  for (final g in roster.maintainers.googlers) {
    if (g.username.toLowerCase() == target) {
      return (role: 'Maintainer (Google)', discord: g.discord);
    }
  }
  for (final p in roster.maintainers.partners) {
    if (p.username.toLowerCase() == target) {
      return (role: 'Maintainer (Partner)', discord: p.discord);
    }
  }
  for (final c in roster.committers) {
    if (c.username.toLowerCase() == target) {
      return (role: 'Committer (@flutter/committers)', discord: c.discord);
    }
  }
  for (final r in roster.reviewers) {
    if (r.username.toLowerCase() == target) {
      return (role: 'Reviewer (@flutter/reviewers)', discord: r.discord);
    }
  }
  for (final e in roster.dashEmeritus) {
    if (e.username.toLowerCase() == target) {
      return (role: 'Dasher Emeritus', discord: e.discord);
    }
  }
  return (role: null, discord: null);
}
