// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:yaml/yaml.dart';

/// Immutable contributor entry parsed from `data/contributors.yaml`.
final class ContributorEntry {
  const ContributorEntry({
    required this.username,
    this.role,
    this.team,
    this.discord,
    this.graceUntil,
  });

  factory ContributorEntry.fromYaml(YamlMap map) {
    final username = (map['username'] as String? ?? '').trim();
    final role = (map['role'] as String?)?.trim();
    final team = (map['team'] as String?)?.trim();
    final discord = (map['discord'] as String?)?.trim();
    final graceUntil = (map['grace_until'] as String?)?.trim();
    return ContributorEntry(
      username: username,
      role: (role != null && role.isNotEmpty) ? role : null,
      team: (team != null && team.isNotEmpty) ? team : null,
      discord: (discord != null && discord.isNotEmpty) ? discord : null,
      graceUntil:
          (graceUntil != null && graceUntil.isNotEmpty) ? graceUntil : null,
    );
  }

  final String username;
  final String? role;
  final String? team;
  final String? discord;
  final String? graceUntil;

  /// Formats this entry as a YAML list item at [indent] spaces.
  String toYamlEntry({required int indent, required String defaultRole}) {
    final pad = ' ' * indent;
    final fieldPad = ' ' * (indent + 2);
    final lines = <String>[
      '$pad- username: $username',
      if (team != null) '${fieldPad}team: "$team"',
      if (discord != null) '${fieldPad}discord: "$discord"',
      if (graceUntil != null) '${fieldPad}grace_until: "$graceUntil"',
      '${fieldPad}role: ${role ?? defaultRole}',
    ];
    return lines.join('\n');
  }
}

/// Immutable `maintainers` section (`googlers` and `partners`) of
/// `data/contributors.yaml`.
final class MaintainersRoster {
  const MaintainersRoster({
    this.googlers = const [],
    this.partners = const [],
  });

  factory MaintainersRoster.fromYaml(YamlMap? map) {
    if (map == null) return const MaintainersRoster();
    return MaintainersRoster(
      googlers: ContributorsRoster._parseEntries(map['googlers']),
      partners: ContributorsRoster._parseEntries(map['partners']),
    );
  }

  final List<ContributorEntry> googlers;
  final List<ContributorEntry> partners;
}

/// Strongly-typed immutable representation of `data/contributors.yaml`.
final class ContributorsRoster {
  const ContributorsRoster({
    this.maintainers = const MaintainersRoster(),
    this.committers = const [],
    this.reviewers = const [],
    this.dashEmeritus = const [],
  });

  factory ContributorsRoster.parse(String yamlContent) {
    final dynamic parsed = loadYaml(yamlContent);
    if (parsed is! YamlMap) {
      return const ContributorsRoster();
    }
    return ContributorsRoster.fromYaml(parsed);
  }

  factory ContributorsRoster.fromYaml(YamlMap doc) {
    return ContributorsRoster(
      maintainers: MaintainersRoster.fromYaml(doc['maintainers'] as YamlMap?),
      committers: _parseEntries(doc['committers']),
      reviewers: _parseEntries(doc['reviewers']),
      dashEmeritus: _parseEntries(doc['dash_emeritus']),
    );
  }

  final MaintainersRoster maintainers;
  final List<ContributorEntry> committers;
  final List<ContributorEntry> reviewers;
  final List<ContributorEntry> dashEmeritus;

  static List<ContributorEntry> _parseEntries(Object? rawList) {
    if (rawList is! YamlList) return const [];
    return List<ContributorEntry>.unmodifiable([
      for (final item in rawList)
        if (item is YamlMap) ContributorEntry.fromYaml(item),
    ]);
  }

  static String _formatBlock(
    List<ContributorEntry> entries, {
    required int indent,
    required String defaultRole,
  }) {
    if (entries.isEmpty) return '';
    final formatted = [
      for (final entry in entries)
        entry.toYamlEntry(indent: indent, defaultRole: defaultRole),
    ].join('\n');
    return '\n$formatted';
  }

  /// Serializes this roster into the canonical `data/contributors.yaml` format.
  String toYamlString({required String lastUpdated}) {
    final googlerBlock = _formatBlock(
      maintainers.googlers,
      indent: 4,
      defaultRole: 'maintainer',
    );
    final partnerBlock = _formatBlock(
      maintainers.partners,
      indent: 4,
      defaultRole: 'maintainer',
    );
    final committerBlock = _formatBlock(
      committers,
      indent: 2,
      defaultRole: 'committer',
    );
    final reviewerBlock = _formatBlock(
      reviewers,
      indent: 2,
      defaultRole: 'reviewer',
    );
    final emeritusBlock = _formatBlock(
      dashEmeritus,
      indent: 2,
      defaultRole: 'emeritus',
    );

    return '''
# Flutter Contributor Ladder Roster
# Source of truth for Flutter contributor roles and permissions.
# Last updated: $lastUpdated

maintainers:
  # Maintainers on the Flutter team (@flutter/googlers and @flutter/partners)
  # Granted Write access + Org Moderation
  googlers:$googlerBlock
  partners:$partnerBlock

committers:
  # Members of @flutter/committers (Child of @flutter/flutter-hackers)
  # Granted GitHub Write role / merge access$committerBlock

reviewers:
  # Members of @flutter/reviewers (Child of @flutter/flutter-hackers)
  # Granted GitHub Triage role$reviewerBlock

dash_emeritus:
  # Honored alumni (External, non-org members on GitHub)$emeritusBlock
''';
  }
}
