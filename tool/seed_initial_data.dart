// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'bots.dart';
import 'github.dart';
import 'validate_roster.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('live',
        help:
            'Fetch live org membership from GitHub API instead of using historical baseline',
        defaultsTo: false)
    ..addOption('token', help: 'GitHub personal access token');

  final results = parser.parse(args);
  final isLive = results['live'] as bool;
  final token = results['token'] as String?;

  print('=== Flutter Contributor Ladder Bootstrap & Seeding Tool ===');

  final dataDir = Directory('data');
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }
  final activityDir = Directory('data/activity');
  if (!activityDir.existsSync()) {
    activityDir.createSync(recursive: true);
  }

  if (isLive) {
    await _runLiveBootstrap(token);
  } else {
    _runHistoricalBootstrap();
  }

  print(
      '\nBootstrap complete! Run `dart run tool/generate_roster.dart` to generate ROSTER.md and EMERITUS.md.');
}

/// Runs bootstrap against live GitHub organization data.
Future<void> _runLiveBootstrap(String? token) async {
  final client = GitHubClient(token: token);
  print('Querying Flutter GitHub organization members...');

  try {
    await loadRobotTeams(client);
    // 1. Fetch all members of flutter org
    final allOrgMembers = await client.getOrgMembers('flutter');
    print(
        'Found ${allOrgMembers.length} total members in flutter organization.');

    // 2. Fetch Googlers and Partners teams (merged with known exception Maintainers)
    print('Querying @flutter/googlers and @flutter/partners teams...');
    final googlers = {
      ...await client.getTeamMembers('flutter', 'googlers'),
      ...loadKnownExceptionMaintainers(),
    };
    final partners = await client.getTeamMembers('flutter', 'partners');
    print('Found ${googlers.length} Googlers and ${partners.length} Partners.');

    // Query child teams of @flutter/partners to resolve exact child team / POC handles
    print('Resolving child teams of @flutter/partners...');
    final partnerTeamMap = <String, String>{};
    try {
      final childTeamSlugs = await client.getChildTeams('flutter', 'partners');
      for (final childSlug in childTeamSlugs) {
        final childMembers = await client.getTeamMembers('flutter', childSlug);
        for (final m in childMembers) {
          partnerTeamMap[m] = '@flutter/$childSlug';
        }
      }
      print(
          'Resolved child teams for ${partnerTeamMap.length} partner members.');
    } catch (e) {
      print('Notice: Could not resolve child teams: $e');
    }

    // 3. Separate Maintainers from Community Candidates
    final maintainers = <String>{...googlers, ...partners};
    final communityCandidates = allOrgMembers.difference(maintainers).toList()
      ..sort();

    print('Maintainers (Googlers + Partners): ${maintainers.length}');
    print(
        'Non-Googler/Non-Partner org members to evaluate: ${communityCandidates.length}');
    print(
        'API Optimization: Skipping activity queries for all ${maintainers.length} Maintainers!');

    final now = DateTime.now().toUtc();
    final oneYearAgo = now.subtract(const Duration(days: 365));

    print(
        '\nEvaluating 12-month rolling activity (${oneYearAgo.toIso8601String().split('T').first} to ${now.toIso8601String().split('T').first}) using batched GraphQL queries...');

    final activitySummary = await client.getBatchUserActivity(
        communityCandidates,
        since: oneYearAgo,
        until: now);

    final committers = <String>[];
    final reviewers = <String>[];
    final emeriti = <String>[];

    for (final member in communityCandidates) {
      if (isExcludedAccount(member)) continue;
      final activity = activitySummary[member] ??
          {'total': 0, 'merged_prs': 0, 'issues': 0, 'reviews': 0};
      final total = activity['total'] ?? 0;
      final prs = activity['merged_prs'] ?? 0;

      if (total >= 30 && prs >= 10) {
        committers.add(member);
      } else if (total >= 10) {
        reviewers.add(member);
      } else {
        emeriti.add(member);
      }
    }

    print('Results for current org members:');
    print('  • Maintainers: ${maintainers.length}');
    print('  • Committers:  ${committers.length}');
    print('  • Reviewers:   ${reviewers.length}');
    print('  • Dasher Emeritus (Inactive): ${emeriti.length}');

    // 4. External candidate discovery (non-org contributors with high activity)
    print('\nDiscovering active external community candidates...');
    final prospective = <String>[];
    try {
      final externalList = [
        'Mairramer',
        'koji-1009',
      ];
      final externalStats = await client.getBatchUserActivity(externalList,
          since: oneYearAgo, until: now);
      for (final entry in externalStats.entries) {
        activitySummary[entry.key] = entry.value;
        if ((entry.value['total'] ?? 0) >= 10) {
          prospective.add(entry.key);
        }
      }
      print(
          'Discovered ${prospective.length} active external candidates for invitation: $prospective');
    } catch (e) {
      print('Notice: External discovery completed with defaults: $e');
    }

    // 5. Save data/activity_summary.json
    final summaryFile = File('data/activity_summary.json');
    summaryFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(activitySummary));
    print('Saved ${summaryFile.path}');

    // 6. Write data/contributors.yaml
    writeContributorsYaml(
      googlers: googlers.toList()..sort(),
      partners: partners.toList()..sort(),
      partnerTeams: partnerTeamMap,
      committers: committers..sort(),
      reviewers: reviewers..sort(),
      emeriti: emeriti..sort(),
    );
  } finally {
    client.close();
  }
}

/// Runs bootstrap using the vetted historical analysis from the proposal.
void _runHistoricalBootstrap() {
  print(
      'Seeding Day 1 roster and baseline metrics from approved proposal data...');

  // Canonical engineers / Partners
  final partners = [
    'kenvandine',
    'robert-ancell',
  ];

  // Active Committers from proposal analysis (>= 30 total, >= 10 PRs)
  final committers = [
    'AbdeMohlbi',
    'AlexV525',
    'DanTup',
    'Jhon-Aires',
    'RobertOdrowaz',
    'ValentinVignal',
    'bleroux',
    'csells',
    'davidhicks980',
    'huycozy',
    'knopp',
    'ksokolovskyi',
    'mattkae',
    'navaronbracke',
    'parlough',
    'rkishan516',
    'schultek',
    'vickyduran',
  ];

  // Active Reviewers from proposal analysis (>= 10 total)
  final reviewers = [
    'bdero',
    'danagbemava-nc',
    'filiph',
    'gnprice',
    'nt4f04uNd',
    'pedromassango',
    'piedcipher',
    'tirth-patel-nc',
    'yiiim',
  ];

  // Dasher Emeriti (< 10 total in 12m historical analysis, bots filtered out)
  final emeriti = [
    '0xZOne',
    'AnnaPS',
    'AyushBherwani1998',
    'CareF',
    'ColdPaleLight',
    'DiegoGW',
    'Ehesp',
    'FXschwartz',
    'FirentisTFW',
    'Hari-07',
    'HidenoriMatsubayashi',
    'Hixie',
    'Jan-Stepien',
    'JsouLiang',
    'Kirpal',
    'KristinBi',
    'LinXunFeng',
    'MacarenaSantos',
    'Rexios80',
    'Salakar',
    'SofiaRey',
    'Swiftaxe',
    'Vanethos',
    'YeungKC',
    'a14n',
    'alestiago',
    'allisonryan0002',
    'atrope',
    'azchohfi',
    'bartekpacia',
    'bernaferrari',
    'brianegan',
    'bruno-garcia',
    'bselwe',
    'btobin',
    'chenglu',
    'chinmoy12c',
    'chriscraws',
    'collinjackson',
    'dam-ease',
    'darshankawar',
    'eggfly',
    'ened',
    'erickzanardo',
    'eseidel',
    'exaby73',
    'felangel',
    'fluttercerberus',
    'gastonliz',
    'guoguo338',
    'hamdikahloun',
    'harri35',
    'hbatagelo',
    'helinanever',
    'hgraceb',
    'horiaciu',
    'jingshao-code',
    'jnschulze',
    'jokerttu',
    'jpnurmi',
    'jwinarske',
    'kaiceyd',
    'kevinburns426',
    'kmillikin',
    'linxuebin1990',
    'luckysmg',
    'magicianA',
    'martinduva',
    'marwfair',
    'matiasleyba',
    'matthew-carroll',
    'mbcorona',
    'mchudy',
    'milezabaleta',
    'miquelbeltran',
    'moffatman',
    'mvanbeusekom',
    'omartinma',
    'pingbird',
    'puneetkukreja98',
    'renefloor',
    'rzambroni',
    'saurabh-mirajkar',
    'scarletteliza',
    'scutlight',
    'simpson-peter',
    'slightfoot',
    'tgucio',
    'tpiaggio',
    'vaind',
    'valentinallavayol',
    'wangying3426',
    'werainkhatri',
    'whesse',
    'wolfenrain',
    'xu-baolin',
    'zhongwuzw',
  ]..removeWhere(isBot);

  // Googlers placeholder list for baseline (managed via @flutter/googlers on GitHub)
  final googlers = [
    'Piinks',
  ];

  // Seed baseline metrics dictionary
  final activitySummary = <String, Map<String, int>>{
    'AbdeMohlbi': {
      'merged_prs': 158,
      'issues': 10,
      'reviews': 12,
      'total': 180
    },
    'parlough': {
      'merged_prs': 223,
      'issues': 155,
      'reviews': 300,
      'total': 678
    },
    'bleroux': {'merged_prs': 78, 'issues': 20, 'reviews': 27, 'total': 125},
    'ksokolovskyi': {
      'merged_prs': 54,
      'issues': 10,
      'reviews': 21,
      'total': 85
    },
    'robert-ancell': {
      'merged_prs': 57,
      'issues': 12,
      'reviews': 15,
      'total': 84
    },
    'ValentinVignal': {
      'merged_prs': 53,
      'issues': 10,
      'reviews': 20,
      'total': 83
    },
    'navaronbracke': {
      'merged_prs': 24,
      'issues': 20,
      'reviews': 35,
      'total': 79
    },
    'rkishan516': {'merged_prs': 69, 'issues': 2, 'reviews': 2, 'total': 73},
    'DanTup': {'merged_prs': 16, 'issues': 20, 'reviews': 36, 'total': 72},
    'huycozy': {'merged_prs': 34, 'issues': 15, 'reviews': 20, 'total': 69},
    'csells': {'merged_prs': 29, 'issues': 16, 'reviews': 20, 'total': 65},
    'schultek': {'merged_prs': 46, 'issues': 8, 'reviews': 10, 'total': 64},
    'Jhon-Aires': {'merged_prs': 47, 'issues': 5, 'reviews': 4, 'total': 56},
    'RobertOdrowaz': {'merged_prs': 35, 'issues': 5, 'reviews': 5, 'total': 45},
    'AlexV525': {'merged_prs': 18, 'issues': 10, 'reviews': 10, 'total': 38},
    'knopp': {'merged_prs': 22, 'issues': 6, 'reviews': 10, 'total': 38},
    'davidhicks980': {
      'merged_prs': 11,
      'issues': 10,
      'reviews': 12,
      'total': 33
    },
    'vickyduran': {'merged_prs': 24, 'issues': 4, 'reviews': 5, 'total': 33},
    'mattkae': {'merged_prs': 29, 'issues': 30, 'reviews': 36, 'total': 95},
    'tirth-patel-nc': {
      'merged_prs': 5,
      'issues': 15,
      'reviews': 10,
      'total': 30
    },
    'gnprice': {'merged_prs': 5, 'issues': 12, 'reviews': 10, 'total': 27},
    'danagbemava-nc': {
      'merged_prs': 0,
      'issues': 15,
      'reviews': 8,
      'total': 23
    },
    'Mairramer': {'merged_prs': 13, 'issues': 4, 'reviews': 4, 'total': 21},
    'piedcipher': {'merged_prs': 9, 'issues': 5, 'reviews': 5, 'total': 19},
    'yiiim': {'merged_prs': 14, 'issues': 1, 'reviews': 2, 'total': 17},
    'filiph': {'merged_prs': 5, 'issues': 6, 'reviews': 5, 'total': 16},
    'koji-1009': {'merged_prs': 13, 'issues': 1, 'reviews': 1, 'total': 15},
    'nate-thegrate': {'merged_prs': 5, 'issues': 4, 'reviews': 4, 'total': 13},
    'nt4f04uNd': {'merged_prs': 1, 'issues': 5, 'reviews': 5, 'total': 11},
    'pedromassango': {'merged_prs': 6, 'issues': 3, 'reviews': 2, 'total': 11},
    'bdero': {'merged_prs': 5, 'issues': 3, 'reviews': 2, 'total': 10},
  };

  final summaryFile = File('data/activity_summary.json');
  summaryFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(activitySummary));
  print('Wrote ${summaryFile.path}');

  writeContributorsYaml(
    googlers: googlers,
    partners: partners,
    committers: committers,
    reviewers: reviewers,
    emeriti: emeriti,
  );
}

void writeContributorsYaml({
  required List<String> googlers,
  required List<String> partners,
  Map<String, String>? partnerTeams,
  required List<String> committers,
  required List<String> reviewers,
  required List<String> emeriti,
  File? outputFile,
}) {
  final today = DateTime.now().toUtc().toIso8601String().split('T').first;
  final googlerEntries = [
    for (final g in googlers) '    - username: $g\n      role: maintainer',
  ].join('\n');
  final partnerEntries = [
    for (final p in partners)
      '    - username: $p\n'
          '      team: "${partnerTeams?[p] ?? '@flutter/partners'}"\n'
          '      role: maintainer',
  ].join('\n');
  final committerEntries = [
    for (final c in committers) '  - username: $c\n    role: committer',
  ].join('\n');
  final reviewerEntries = [
    for (final r in reviewers) '  - username: $r\n    role: reviewer',
  ].join('\n');
  final emeritusEntries = [
    for (final e in emeriti) '  - username: $e\n    role: emeritus',
  ].join('\n');

  final content = '''
# Flutter Contributor Ladder Roster
# Source of truth for Flutter contributor roles and permissions.
# Last updated: $today

maintainers:
  # Maintainers on the Flutter team (@flutter/googlers and @flutter/partners)
  # Granted Write access + Org Moderation
  googlers:
$googlerEntries
  partners:
$partnerEntries

committers:
  # Members of @flutter/committers (Child of @flutter/flutter-hackers)
  # Granted GitHub Write role / merge access
$committerEntries

reviewers:
  # Members of @flutter/reviewers (Child of @flutter/flutter-hackers)
  # Granted GitHub Triage role
$reviewerEntries

dash_emeritus:
  # Honored alumni (External, non-org members on GitHub)
$emeritusEntries
''';

  final file = outputFile ?? File('data/contributors.yaml');
  file.writeAsStringSync(content);
  print(
      'Wrote ${file.path} (${committers.length} Committers, ${reviewers.length} Reviewers, ${emeriti.length} Emeriti).');
}
