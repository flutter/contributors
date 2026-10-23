// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import '../tool/generate_roster.dart';
import '../tool/seed_initial_data.dart';
import '../tool/validate_roster.dart';

void main() {
  group('Roster Schema & Integrity Tests', () {
    late String yamlContent;
    late YamlMap doc;

    setUpAll(() {
      final file = File('data/contributors.yaml');
      expect(file.existsSync(), isTrue,
          reason: 'data/contributors.yaml must exist');
      yamlContent = file.readAsStringSync();
      final loaded = loadYaml(yamlContent);
      expect(loaded, isA<YamlMap>());
      doc = loaded as YamlMap;
    });

    test('contributors.yaml contains all required root sections', () {
      expect(doc.containsKey('maintainers'), isTrue);
      expect(doc.containsKey('committers'), isTrue);
      expect(doc.containsKey('reviewers'), isTrue);
      expect(doc.containsKey('dash_emeritus'), isTrue);
    });

    test('maintainers contains strictly googlers and partners', () {
      final maintainers = doc['maintainers'] as YamlMap;
      expect(maintainers.keys.toSet(), equals({'googlers', 'partners'}));

      final googlers = maintainers['googlers'] as YamlList;
      final partners = maintainers['partners'] as YamlList;

      expect(googlers, isNotEmpty);
      expect(partners, isNotEmpty);
    });

    test('all member handles across the entire roster are unique', () {
      final seen = <String, String>{};

      void checkUser(dynamic entry, String section) {
        expect(entry, isA<YamlMap>());
        final username = (entry as YamlMap)['username'] as String?;
        expect(username, isNotNull);
        expect(username!.trim(), isNotEmpty);

        final lower = username.toLowerCase();
        expect(seen.containsKey(lower), isFalse,
            reason:
                'Duplicate username "@$username" in $section (already in ${seen[lower]})');
        seen[lower] = section;
      }

      final maintainers = doc['maintainers'] as YamlMap;
      for (final g in maintainers['googlers'] as YamlList) {
        checkUser(g, 'maintainers.googlers');
      }
      for (final p in maintainers['partners'] as YamlList) {
        checkUser(p, 'maintainers.partners');
      }
      for (final c in doc['committers'] as YamlList) {
        checkUser(c, 'committers');
      }
      for (final r in doc['reviewers'] as YamlList) {
        checkUser(r, 'reviewers');
      }
      for (final e in doc['dash_emeritus'] as YamlList) {
        checkUser(e, 'dash_emeritus');
      }
    });

    test('all roles belong to the allowed set of ladder roles', () {
      const allowedRoles = {'maintainer', 'committer', 'reviewer', 'emeritus'};

      void verifyRole(dynamic entry) {
        final map = entry as YamlMap;
        final role = map['role'] as String? ?? map['suggested_role'] as String?;
        if (role != null) {
          expect(allowedRoles.contains(role.toLowerCase()), isTrue,
              reason: 'Invalid role "$role" for user ${map['username']}');
        }
      }

      final maintainers = doc['maintainers'] as YamlMap;
      (maintainers['googlers'] as YamlList).forEach(verifyRole);
      (maintainers['partners'] as YamlList).forEach(verifyRole);
      (doc['committers'] as YamlList).forEach(verifyRole);
      (doc['reviewers'] as YamlList).forEach(verifyRole);
      (doc['dash_emeritus'] as YamlList).forEach(verifyRole);
    });

    test('validateContributorsYaml passes on production data/contributors.yaml',
        () {
      expect(validateContributorsYaml(doc), isEmpty);
    });

    test(
        'validateContributorsYaml detects invalid schemas, duplicate users, invalid roles, and invalid maintainer groups',
        () {
      expect(
        validateContributorsYaml(loadYaml('- not_a_map')),
        contains(contains('root must be a YAML mapping')),
      );

      final invalidDoc = loadYaml('''
maintainers:
  googlers:
    - username: alice
      role: maintainer
      discord: "alice_discord"
  partners:
    - username: bob
      role: maintainer
  community:
    - username: invalidGroupUser
      role: maintainer
committers:
  - "not_a_map_entry"
  - role: committer
  - username: ALICE
    role: committer
  - username: charlie
    role: superadmin
  - username: dave
    role: committer
    discord: "   "
reviewers: []
dash_emeritus: []
''');

      final errors = validateContributorsYaml(invalidDoc);
      expect(
          errors,
          contains(
              contains('invalid group "community"'))); // non-googler/partner
      expect(errors, contains(contains('entry is not a map')));
      expect(errors, contains(contains('missing username')));
      expect(errors,
          contains(contains('duplicate username "@ALICE" in committers')));
      expect(errors, contains(contains('invalid role "superadmin"')));
      expect(
          errors,
          contains(
              contains('invalid or empty discord username for user @dave')));
    });

    test(
        'known_maintainers.txt single source of truth enforces Maintainer placement',
        () {
      final known = loadKnownExceptionMaintainers();
      expect(
          known,
          containsAll([
            'CarlosMendonca',
            'LouiseHsu',
            'abdallahshaban557',
            'andywolff',
            'gaaclarke',
            'gmackall',
            'jesswrd',
          ]));

      final badPlacementDoc = loadYaml('''
maintainers:
  googlers:
    - username: Piinks
      role: maintainer
  partners: []
committers:
  - username: gaaclarke
    role: committer
reviewers: []
dash_emeritus:
  - username: CarlosMendonca
    role: emeritus
''');
      final errors = validateContributorsYaml(badPlacementDoc);
      expect(
          errors,
          contains(contains(
              '"@gaaclarke" is a known Maintainer and must be listed under maintainers.googlers')));
      expect(
          errors,
          contains(contains(
              '"@CarlosMendonca" is a known Maintainer and must be listed under maintainers.googlers')));
    });

    test(
        'buildRosterMarkdown, buildEmeritusMarkdown, and generate_roster CLI --check',
        () {
      final tempDir = Directory.systemTemp.createTempSync('roster_gen_test_');
      try {
        final yamlFile = File('${tempDir.path}/contributors.yaml');
        final summaryFile = File('${tempDir.path}/activity_summary.json');
        final rosterFile = File('${tempDir.path}/ROSTER.md');
        final emeritusFile = File('${tempDir.path}/EMERITUS.md');

        writeContributorsYaml(
          googlers: ['Piinks'],
          partners: ['robert-ancell'],
          partnerTeams: {'robert-ancell': '@flutter/canonical'},
          committers: ['alice'],
          reviewers: ['bob'],
          emeriti: ['formerDasher'],
          outputFile: yamlFile,
        );
        summaryFile.writeAsStringSync(
            '{"alice": {"merged_prs": 15, "total": 40}, "bob": {"merged_prs": 3, "total": 12}}');

        final parsedYaml = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
        expect(validateContributorsYaml(parsedYaml), isEmpty);
        expect(buildRosterMarkdown(parsedYaml, {}),
            contains('## Committers (`@flutter/committers`)'));
        expect(
            buildEmeritusMarkdown(parsedYaml), contains('# Dasher Emeritus'));

        // --check should fail before ROSTER.md and EMERITUS.md exist
        final checkBefore = Process.runSync('dart', [
          'run',
          'tool/generate_roster.dart',
          '--check',
          '--contributors',
          yamlFile.path,
          '--summary',
          summaryFile.path,
          '--roster',
          rosterFile.path,
          '--emeritus',
          emeritusFile.path,
        ]);
        expect(checkBefore.exitCode, equals(1));

        // Generate ROSTER.md and EMERITUS.md
        final genResult = Process.runSync('dart', [
          'run',
          'tool/generate_roster.dart',
          '--contributors',
          yamlFile.path,
          '--summary',
          summaryFile.path,
          '--roster',
          rosterFile.path,
          '--emeritus',
          emeritusFile.path,
        ]);
        expect(genResult.exitCode, equals(0));
        expect(rosterFile.existsSync(), isTrue);
        expect(emeritusFile.existsSync(), isTrue);

        final rosterMd = rosterFile.readAsStringSync();
        expect(rosterMd, contains('[@Piinks](https://github.com/Piinks)'));
        expect(rosterMd,
            contains('[@robert-ancell](https://github.com/robert-ancell)'));
        expect(
            rosterMd,
            contains(
                '| @alice | [github.com/alice](https://github.com/alice) | 15 | 40 |'));
        expect(rosterMd, isNot(contains('Prospective new joiners')));

        final emeritusMd = emeritusFile.readAsStringSync();
        expect(emeritusMd,
            contains('[@formerDasher](https://github.com/formerDasher)'));
        expect(emeritusMd, contains('https://github.com/flutter/rfc'));

        // --check should now pass
        final checkAfter = Process.runSync('dart', [
          'run',
          'tool/generate_roster.dart',
          '--check',
          '--contributors',
          yamlFile.path,
          '--summary',
          summaryFile.path,
          '--roster',
          rosterFile.path,
          '--emeritus',
          emeritusFile.path,
        ]);
        expect(checkAfter.exitCode, equals(0));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
