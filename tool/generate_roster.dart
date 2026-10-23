// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addFlag('check',
        help:
            'Verify that ROSTER.md and EMERITUS.md match data/contributors.yaml without modifying files',
        defaultsTo: false)
    ..addOption('contributors',
        help: 'Path to contributors.yaml', defaultsTo: 'data/contributors.yaml')
    ..addOption('summary',
        help: 'Path to activity_summary.json',
        defaultsTo: 'data/activity_summary.json')
    ..addOption('roster', help: 'Path to ROSTER.md', defaultsTo: 'ROSTER.md')
    ..addOption('emeritus',
        help: 'Path to EMERITUS.md', defaultsTo: 'EMERITUS.md');

  final results = parser.parse(args);
  final isCheck = results['check'] as bool;
  final contributorsPath = results['contributors'] as String;
  final summaryPath = results['summary'] as String;
  final rosterPath = results['roster'] as String;
  final emeritusPath = results['emeritus'] as String;

  final yamlFile = File(contributorsPath);
  if (!yamlFile.existsSync()) {
    print('Error: $contributorsPath not found.');
    exit(1);
  }

  final doc = loadYaml(yamlFile.readAsStringSync()) as YamlMap;

  final summaryFile = File(summaryPath);
  var summary = <String, dynamic>{};
  if (summaryFile.existsSync()) {
    try {
      summary =
          jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
  }

  String preservePendingAuditBanner(File targetFile, String generated) {
    if (!targetFile.existsSync()) return generated;
    final existing = targetFile.readAsStringSync();
    final match = RegExp(
      r'\n(> \[!IMPORTANT\]\n> \*\*Pending Q4 Audit:\*\*[^\n]*\n)',
    ).firstMatch(existing);
    if (match == null) return generated;
    final firstNewline = generated.indexOf('\n');
    if (firstNewline == -1) return generated;
    return '${generated.substring(0, firstNewline + 1)}${match.group(0)}${generated.substring(firstNewline + 1)}';
  }

  final rosterFile = File(rosterPath);
  final emeritusFile = File(emeritusPath);
  final rosterContent =
      preservePendingAuditBanner(rosterFile, buildRosterMarkdown(doc, summary));
  final emeritusContent =
      preservePendingAuditBanner(emeritusFile, buildEmeritusMarkdown(doc));

  if (isCheck) {
    final rosterOutOfSync = !rosterFile.existsSync() ||
        rosterFile.readAsStringSync() != rosterContent;
    final emeritusOutOfSync = !emeritusFile.existsSync() ||
        emeritusFile.readAsStringSync() != emeritusContent;
    if (rosterOutOfSync || emeritusOutOfSync) {
      print(
          'Error: ROSTER.md or EMERITUS.md is out of sync with data/contributors.yaml.');
      print('Run `dart run tool/generate_roster.dart` to update them.');
      exit(1);
    }
    print('ROSTER.md and EMERITUS.md are in sync with data/contributors.yaml.');
  } else {
    rosterFile.writeAsStringSync(rosterContent);
    emeritusFile.writeAsStringSync(emeritusContent);
    print(
        'Generated ${rosterFile.path} and ${emeritusFile.path} successfully.');
  }
}

List<String> _formatGridRows(List<String> usernames, {int columns = 4}) {
  final rows = <String>[];
  for (var i = 0; i < usernames.length; i += columns) {
    final row = <String>[
      for (var j = 0; j < columns && i + j < usernames.length; j++)
        '[@${usernames[i + j]}](https://github.com/${usernames[i + j]})',
    ];
    rows.add(row.join(' • '));
  }
  return rows;
}

String buildRosterMarkdown(YamlMap doc, Map<String, dynamic> summary) {
  final maintainers = doc['maintainers'] as YamlMap?;
  final allMaintainers = <String>{
    if (maintainers != null) ...[
      for (final g in maintainers['googlers'] as YamlList? ?? [])
        g['username'] as String,
      for (final p in maintainers['partners'] as YamlList? ?? [])
        p['username'] as String,
    ],
  };
  final sortedMaintainers = allMaintainers.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final maintainerRows = _formatGridRows(sortedMaintainers);

  final committers = doc['committers'] as YamlList? ?? [];
  final committerRows = <String>[
    for (final c in committers)
      () {
        final username = c['username'] as String;
        final stats = summary[username] as Map<String, dynamic>?;
        final prs = stats?['merged_prs'] ?? '-';
        final total = stats?['total'] ?? '-';
        return '| @$username | [github.com/$username](https://github.com/$username) | $prs | $total |';
      }(),
  ];

  final reviewers = doc['reviewers'] as YamlList? ?? [];
  final reviewerRows = <String>[
    for (final r in reviewers)
      () {
        final username = r['username'] as String;
        final stats = summary[username] as Map<String, dynamic>?;
        final prs = stats?['merged_prs'] ?? '-';
        final total = stats?['total'] ?? '-';
        return '| @$username | [github.com/$username](https://github.com/$username) | $prs | $total |';
      }(),
  ];

  return '''
# Contributor Roster

This directory lists active Flutter Contributor Ladder members.
Honorary alumni who have stepped back from active contribution and exited the GitHub organization are listed in [EMERITUS.md](EMERITUS.md).
Governance details and tier qualifications are specified in [docs/LADDER.md](docs/LADDER.md).

> [!NOTE]
> This file is automatically generated from `data/contributors.yaml`.
> To update, edit `data/contributors.yaml` and run `dart run tool/generate_roster.dart`.

## Maintainers (`@flutter/maintainers`)

Maintainers hold GitHub Write permissions and organization moderation privileges, and belong to `@flutter/maintainers` (a child team of `@flutter/flutter-hackers`).

${maintainerRows.join('\n')}

## Committers (`@flutter/committers`)

Committers hold GitHub Write permissions (merge rights) and provide authoritative code reviews.

| Contributor | GitHub profile | 12m merged PRs | 12m total activity |
| :--- | :--- | :--- | :--- |
${committerRows.join('\n')}

## Reviewers (`@flutter/reviewers`)

Reviewers hold GitHub Triage permissions, triage issues, and conduct first-pass code reviews.

| Contributor | GitHub profile | 12m merged PRs | 12m total activity |
| :--- | :--- | :--- | :--- |
${reviewerRows.join('\n')}

## Dasher Emeritus

Former ladder members who have stepped back from active contribution do not remain in the GitHub organization and are honored in [EMERITUS.md](EMERITUS.md).
''';
}

String buildEmeritusMarkdown(YamlMap doc) {
  final emeriti = doc['dash_emeritus'] as YamlList? ?? [];
  final sortedEmeriti = emeriti.map((e) => e['username'] as String).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final emeritusRows = _formatGridRows(sortedEmeriti);

  return '''
# Dasher Emeritus

This directory honors **Dasher Emeritus** alumni—former Flutter Reviewers, Committers, and Maintainers who previously held roles on the contributor ladder and have stepped back from active contribution (< 10 contributions over the preceding 12 months).

To maintain repository security, Dasher Emeriti do not remain members of the `flutter` GitHub organization. Instead, their contributions are recognized here, and they retain access to Flutter contributor channels on Discord (including `#hidden-chat`) and the announcement-only `flutter-contributors` Google Group (for project announcements and calendar invites to our recurring Flutter Contributor Roundtable and the Dash Forum, where contributors can present and get feedback on their [RFCs](https://github.com/flutter/rfc); the registration form is pinned in `#hidden-chat` on Discord) so they can stay in touch and more easily ramp back up onto the project if and when they choose to return.

Returning Emeriti who resume contributing are automatically identified during quarterly reviews (where they can reply directly on the public tracking issue). For off-cycle reinstatement, because creating new issues and pull requests in `flutter/contributors` is restricted to organization members (`collaborators`), returning Emeriti can reach out in `#hidden-chat` on Discord (or to an active organization member) to have an active org member sponsor and open a [Dasher Emeritus Reinstatement request](.github/ISSUE_TEMPLATE/2_emeritus_reinstatement.yml) on their behalf (where they can also share an updated Discord username if needed). See [docs/LADDER.md](docs/LADDER.md) for details.

> [!NOTE]
> This file is automatically generated from `data/contributors.yaml`.
> To update, edit `data/contributors.yaml` and run `dart run tool/generate_roster.dart`.

## Honored Alumni

${emeritusRows.join('\n')}
''';
}
