// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:yaml/yaml.dart';
import 'bots.dart';

const validRoles = {'maintainer', 'committer', 'reviewer', 'emeritus'};

const knownMaintainersPath =
    '.agents/skills/quarterly-ladder-analysis/references/known_maintainers.txt';
const knownBotsPath =
    '.agents/skills/quarterly-ladder-analysis/references/bots.txt';

/// Loads known bot/automation accounts from [knownBotsPath].
Set<String> loadKnownBotReferences({String path = knownBotsPath}) {
  final file = File(path);
  if (!file.existsSync()) return {};
  final result = <String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      result.add(trimmed.toLowerCase());
    }
  }
  return result;
}

/// Loads known exception Maintainers from the single source of truth file
/// ([knownMaintainersPath]).
Set<String> loadKnownExceptionMaintainers(
    {String path = knownMaintainersPath}) {
  final file = File(path);
  if (!file.existsSync()) return {};
  final result = <String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      result.add(trimmed);
    }
  }
  return result;
}

/// Returns true if [username] is listed in [knownMaintainersPath].
bool isKnownExceptionMaintainer(String username,
    {Set<String>? knownMaintainers}) {
  final lower = username.toLowerCase().trim();
  final set = knownMaintainers ?? loadKnownExceptionMaintainers();
  return set.any((m) => m.toLowerCase() == lower);
}

/// Validates a parsed `contributors.yaml` document and returns a list of
/// human-readable error strings (empty if valid).
List<String> validateContributorsYaml(dynamic doc) {
  if (doc is! YamlMap) {
    return ['Error: data/contributors.yaml root must be a YAML mapping.'];
  }

  final seenUsers = <String, String>{};
  final errors = <String>[];
  final knownExceptionMaintainers = loadKnownExceptionMaintainers();
  final knownExceptionLower =
      knownExceptionMaintainers.map((u) => u.toLowerCase()).toSet();
  final knownBotsLower = loadKnownBotReferences();

  void validateUser(dynamic entry, String section,
      {bool isMaintainer = false}) {
    if (entry is! YamlMap) {
      errors.add('Error in $section: entry is not a map: $entry');
      return;
    }

    final username = entry['username'] as String?;
    if (username == null || username.trim().isEmpty) {
      errors.add('Error in $section: missing username: $entry');
      return;
    }

    final lowerUser = username.toLowerCase();
    if (isExcludedAccount(username) || knownBotsLower.contains(lowerUser)) {
      errors.add(
          'Error in $section: "@$username" is a bot or excluded automation account and must not be listed in contributors.yaml.');
    }
    if (seenUsers.containsKey(lowerUser)) {
      errors.add(
          'Error: duplicate username "@$username" in $section (already defined in ${seenUsers[lowerUser]})');
    } else {
      seenUsers[lowerUser] = section;
    }

    if (!isMaintainer && knownExceptionLower.contains(lowerUser)) {
      errors.add(
          'Error in $section: "@$username" is a known Maintainer and must be listed under maintainers.googlers.');
    }

    final role = entry['role'] as String? ?? entry['suggested_role'] as String?;
    if (role != null && !validRoles.contains(role.toLowerCase())) {
      errors.add(
          'Error in $section: invalid role "$role" for user @$username. Valid roles: $validRoles');
    }

    if (entry.containsKey('discord')) {
      final discord = entry['discord'];
      if (discord is! String || discord.trim().isEmpty) {
        errors.add(
            'Error in $section: invalid or empty discord username for user @$username.');
      }
    }

    if (entry.containsKey('grace_until')) {
      final graceUntil = entry['grace_until'];
      if (graceUntil is! String ||
          DateTime.tryParse(graceUntil.trim()) == null) {
        errors.add(
            'Error in $section: invalid grace_until date "$graceUntil" for user @$username (expected YYYY-MM-DD).');
      }
    }
  }

  // Validate Maintainers (must strictly be googlers or partners)
  final maintainers = doc['maintainers'];
  if (maintainers is YamlMap) {
    for (final key in maintainers.keys) {
      if (key != 'googlers' && key != 'partners') {
        errors.add(
            'Error in maintainers: invalid group "$key". All Maintainers must be in "googlers" or "partners".');
      }
    }
    final googlers = maintainers['googlers'];
    if (googlers is YamlList) {
      for (final g in googlers) {
        validateUser(g, 'maintainers.googlers', isMaintainer: true);
      }
    }
    final partners = maintainers['partners'];
    if (partners is YamlList) {
      for (final p in partners) {
        validateUser(p, 'maintainers.partners', isMaintainer: true);
      }
    }
  }

  // Validate Committers
  final committers = doc['committers'];
  if (committers is YamlList) {
    for (final c in committers) {
      validateUser(c, 'committers');
    }
  }

  // Validate Reviewers
  final reviewers = doc['reviewers'];
  if (reviewers is YamlList) {
    for (final r in reviewers) {
      validateUser(r, 'reviewers');
    }
  }

  // Validate Dasher Emeritus
  final emeriti = doc['dash_emeritus'];
  if (emeriti is YamlList) {
    for (final e in emeriti) {
      validateUser(e, 'dash_emeritus');
    }
  }

  return errors;
}

void main(List<String> args) {
  final filePath = args.isNotEmpty ? args.first : 'data/contributors.yaml';
  final file = File(filePath);
  if (!file.existsSync()) {
    print('Error: $filePath does not exist.');
    exit(1);
  }

  print('Validating $filePath...');
  final content = file.readAsStringSync();
  final dynamic doc = loadYaml(content);

  final errors = validateContributorsYaml(doc);
  for (final err in errors) {
    print(err);
  }

  if (errors.isNotEmpty) {
    print('\nValidation FAILED with ${errors.length} errors.');
    exit(1);
  }

  print('Validation SUCCESS: $filePath is valid.');
}
