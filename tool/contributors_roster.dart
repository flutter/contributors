// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';
import 'package:yaml/yaml.dart';

part 'contributors_roster.g.dart';

String _trimString(Object? value) => (value == null ? '' : '$value').trim();

String? _trimNullableString(Object? value) {
  if (value == null) return null;
  final trimmed = '$value'.trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

/// Immutable contributor entry parsed from `data/contributors.yaml`.
@JsonSerializable(fieldRename: FieldRename.snake)
final class ContributorEntry {
  const ContributorEntry({
    this.username = '',
    this.role,
    this.team,
    this.discord,
    this.graceUntil,
  });

  factory ContributorEntry.fromJson(Map<String, Object?> json) =>
      _$ContributorEntryFromJson(json);

  @JsonKey(fromJson: _trimString)
  final String username;

  @JsonKey(fromJson: _trimNullableString)
  final String? role;

  @JsonKey(fromJson: _trimNullableString)
  final String? team;

  @JsonKey(fromJson: _trimNullableString)
  final String? discord;

  @JsonKey(fromJson: _trimNullableString)
  final String? graceUntil;

  Map<String, Object?> toJson() => _$ContributorEntryToJson(this);

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
@JsonSerializable(explicitToJson: true)
final class MaintainersRoster {
  const MaintainersRoster({
    this.googlers = const [],
    this.partners = const [],
  });

  factory MaintainersRoster.fromJson(Map<String, Object?> json) =>
      _$MaintainersRosterFromJson(json);

  final List<ContributorEntry> googlers;
  final List<ContributorEntry> partners;

  Map<String, Object?> toJson() => _$MaintainersRosterToJson(this);
}

/// Strongly-typed immutable representation of `data/contributors.yaml`.
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
final class ContributorsRoster {
  const ContributorsRoster({
    this.maintainers = const MaintainersRoster(),
    this.committers = const [],
    this.reviewers = const [],
    this.dashEmeritus = const [],
  });

  factory ContributorsRoster.fromJson(Map<String, Object?> json) =>
      _$ContributorsRosterFromJson(json);

  factory ContributorsRoster.fromYaml(YamlMap? yaml) =>
      ContributorsRoster.fromJson(yaml?.asMap ?? const {});

  factory ContributorsRoster.parse(String yamlContent) {
    final dynamic parsed = loadYaml(yamlContent);
    if (parsed is! YamlMap) {
      return const ContributorsRoster();
    }
    return ContributorsRoster.fromYaml(parsed);
  }

  final MaintainersRoster maintainers;
  final List<ContributorEntry> committers;
  final List<ContributorEntry> reviewers;
  final List<ContributorEntry> dashEmeritus;

  Map<String, Object?> toJson() => _$ContributorsRosterToJson(this);

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

extension _YamlMapToMap on YamlMap {
  Map<String, Object?> get asMap => <String, Object?>{
        for (final MapEntry(:key, :value) in entries)
          if (value is YamlMap)
            '$key': value.asMap
          else if (value is YamlList)
            '$key': value.asList
          else if (value is YamlScalar)
            '$key': value.value
          else
            '$key': value,
      };
}

extension _YamlListToList on YamlList {
  List<Object?> get asList => <Object?>[
        for (final node in nodes)
          if (node is YamlMap)
            node.asMap
          else if (node is YamlList)
            node.asList
          else if (node is YamlScalar)
            node.value
          else
            node,
      ];
}
