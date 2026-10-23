// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/check_grace_period.dart';
import '../tool/check_user.dart';
import '../tool/contributors_roster.dart';
import '../tool/quarterly_audit.dart';
import 'mock_process_runner.dart';

void main() {
  group('Quarterly Audit Report Generation', () {
    test('generate community audit report runs and produces valid markdown',
        () {
      final result = Process.runSync('dart', [
        'run',
        'tool/quarterly_audit.dart',
        '--community',
        '--offline',
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: 'quarterly_audit.dart --community should exit with 0',
      );
      final output = result.stdout as String;

      // Header and metadata
      expect(
        output,
        contains('# Quarterly Community Contributor Ladder Audit'),
      );
      expect(output, contains('Audit date:'));
      expect(output, contains('12-month evaluation window:'));
      expect(output, contains('30-day grace period deadline:'));

      // Section 1: Promotions and New Joiners
      expect(output, contains('## Recommended promotions and new joiners'));

      // Section 2: Active Role Retention
      expect(output, contains('## Active role retention'));

      // Section 3: 30-Day Grace Period
      expect(output, contains('## 30-day grace period'));

      // Section 4: Callout for Unscripted Contributions
      expect(output, contains('## Qualitative contributions'));
    });

    test(
        'generate partner verification report runs and produces valid markdown',
        () {
      final result = Process.runSync('dart', [
        'run',
        'tool/quarterly_audit.dart',
        '--partners',
        '--offline',
      ]);

      expect(
        result.exitCode,
        equals(0),
        reason: 'quarterly_audit.dart --partners should exit with 0',
      );
      final output = result.stdout as String;

      // Header and metadata
      expect(output, contains('# Quarterly Partner Team Verification Audit'));
      expect(output, contains('@flutter/partners'));
      expect(output, contains('## Active partner team members'));
      expect(output, contains('## Departures and offboarding'));
      expect(output, contains('[ ] Verified Active'));
    });

    test('ROSTER.md and EMERITUS.md exist and contain valid sections', () {
      final rosterFile = File('ROSTER.md');
      final emeritusFile = File('EMERITUS.md');
      expect(rosterFile.existsSync(), isTrue);
      expect(emeritusFile.existsSync(), isTrue);
      expect(rosterFile.readAsStringSync(), contains('# Contributor Roster'));
      expect(emeritusFile.readAsStringSync(), contains('# Dasher Emeritus'));
    });

    test(
        'discovers external candidates from summary and applies --finalize transitions',
        () {
      final tempDir = Directory.systemTemp.createTempSync('audit_finalize_');
      try {
        final contributorsFile = File('${tempDir.path}/contributors.yaml');
        final summaryFile = File('${tempDir.path}/activity_summary.json');

        contributorsFile.writeAsStringSync('''
maintainers:
  googlers:
    - username: Piinks
      role: maintainer
  partners:
    - username: robert-ancell
      team: "@flutter/canonical"
      role: maintainer

committers:
  - username: activeCommitter
    role: committer
  - username: inactiveCommitter
    role: committer

reviewers:
  - username: promotedReviewer
    role: reviewer
  - username: retainedReviewer
    role: reviewer
  - username: graceAppealedReviewer
    role: reviewer
  - username: recentJoinerReviewer
    grace_until: "2099-01-01"
    role: reviewer
  - username: inactiveReviewer
    role: reviewer

prospective_new_joiners:
  - username: Mairramer
    suggested_role: reviewer

dash_emeritus:
  - username: returningEmeritus
    role: emeritus
  - username: quietEmeritus
    role: emeritus
''');

        summaryFile.writeAsStringSync('''
{
  "activeCommitter": {"merged_prs": 12, "issues": 5, "reviews": 5, "total": 22},
  "inactiveCommitter": {"merged_prs": 1, "issues": 1, "reviews": 0, "total": 2},
  "promotedReviewer": {"merged_prs": 15, "issues": 10, "reviews": 10, "total": 35},
  "retainedReviewer": {"merged_prs": 4, "issues": 5, "reviews": 5, "total": 14},
  "graceAppealedReviewer": {"merged_prs": 2, "issues": 2, "reviews": 1, "total": 5},
  "recentJoinerReviewer": {"merged_prs": 1, "issues": 1, "reviews": 0, "total": 2},
  "inactiveReviewer": {"merged_prs": 0, "issues": 1, "reviews": 0, "total": 1},
  "returningEmeritus": {"merged_prs": 5, "issues": 4, "reviews": 3, "total": 12},
  "Mairramer": {"merged_prs": 10, "issues": 4, "reviews": 2, "total": 16},
  "discoveredExternal": {"merged_prs": 12, "issues": 10, "reviews": 12, "total": 34},
  "auto-submit": {"merged_prs": 50, "issues": 0, "reviews": 0, "total": 50}
}
''');

        // 1. Verify --community discovers returningEmeritus and discoveredExternal (and ignores auto-submit),
        // and omits excluded users so no one is singled out in the generated report.
        final communityResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--community',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
        ]);
        expect(communityResult.exitCode, equals(0));
        final report = communityResult.stdout as String;
        expect(
          report,
          contains('| @promotedReviewer | Reviewer | **Committer** |'),
        );
        expect(
          report,
          contains(
            '| @returningEmeritus | Dasher Emeritus | **Reviewer** (Reinstatement) |',
          ),
        );
        expect(
          report,
          contains(
            '| @discoveredExternal | External Contributor | **Committer** (Invitation) |',
          ),
        );
        expect(
          report,
          contains(
            '| @recentJoinerReviewer | Reviewer (12m recent-joiner carve-out) | 1 | 2 |',
          ),
        );
        expect(report, isNot(contains('auto-submit')));

        // Verify --exclude omits excluded users from the community report completely
        final filteredCommunityResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--community',
          '--exclude',
          'discoveredExternal,promotedReviewer',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
        ]);
        expect(filteredCommunityResult.exitCode, equals(0));
        final filteredReport = filteredCommunityResult.stdout as String;
        expect(filteredReport, isNot(contains('discoveredExternal')));
        expect(
          filteredReport,
          isNot(
            contains('| @promotedReviewer | Reviewer | **Committer** |'),
          ),
        );
        expect(
          filteredReport,
          contains('| @promotedReviewer | Reviewer | 15 | 35 |'),
        );

        // Verify live org reconciliation checks all current Flutter org members so no one slips through
        final parsedDoc =
            ContributorsRoster.parse(contributorsFile.readAsStringSync());
        final liveRoster = reconcileRosterState(
          parsedDoc,
          liveOrg: const LiveOrgSnapshot(
            orgMembers: {
              'Piinks',
              'gaaclarke',
              'LouiseHsu',
              'robert-ancell',
              'newPartner',
              'activeCommitter',
              'inactiveCommitter',
              'promotedReviewer',
              'retainedReviewer',
              'graceAppealedReviewer',
              'recentJoinerReviewer',
              'inactiveReviewer',
              'quietEmeritus', // still in GitHub org -> must be in 30-day grace period
              'untrackedOrgMemberLow', // in GitHub org (<10) -> must be in 30-day grace period
              'untrackedOrgMemberHigh', // in GitHub org (>=10) -> promoted/enrolled
            },
            googlers: {'Piinks'},
            collaborators: {
              'gaaclarke', // known exception Googler appearing in @flutter/collaborators
              'LouiseHsu', // known exception Googler appearing in @flutter/collaborators
              'robert-ancell',
              'newPartner',
              'activeCommitter',
              'untrackedOrgMemberLow',
            },
            partners: {'robert-ancell', 'newPartner'},
            partnerTeams: {
              'robert-ancell': '@flutter/canonical',
              'newpartner': '@flutter/cloudsufi',
            },
          ),
        );
        expect(
          liveRoster.googlers,
          containsAll(['Piinks', 'gaaclarke', 'LouiseHsu']),
        );
        expect(liveRoster.unassignedOrgMembers, isNot(contains('gaaclarke')));
        expect(liveRoster.unassignedOrgMembers, isNot(contains('LouiseHsu')));
        final liveSummary = {
          'activeCommitter': {
            'merged_prs': 12,
            'issues': 5,
            'reviews': 5,
            'total': 22,
          },
          'inactiveCommitter': {
            'merged_prs': 1,
            'issues': 1,
            'reviews': 0,
            'total': 2,
          },
          'promotedReviewer': {
            'merged_prs': 15,
            'issues': 10,
            'reviews': 10,
            'total': 35,
          },
          'retainedReviewer': {
            'merged_prs': 4,
            'issues': 5,
            'reviews': 5,
            'total': 14,
          },
          'graceAppealedReviewer': {
            'merged_prs': 2,
            'issues': 2,
            'reviews': 1,
            'total': 5,
          },
          'recentJoinerReviewer': {
            'merged_prs': 1,
            'issues': 1,
            'reviews': 0,
            'total': 2,
          },
          'inactiveReviewer': {
            'merged_prs': 0,
            'issues': 1,
            'reviews': 0,
            'total': 1,
          },
          'returningEmeritus': {
            'merged_prs': 5,
            'issues': 4,
            'reviews': 3,
            'total': 12,
          },
          'untrackedOrgMemberLow': {
            'merged_prs': 1,
            'issues': 1,
            'reviews': 0,
            'total': 2,
          },
          'untrackedOrgMemberHigh': {
            'merged_prs': 12,
            'issues': 5,
            'reviews': 3,
            'total': 20,
          },
          'newPartner': {
            'merged_prs': 4,
            'issues': 1,
            'reviews': 0,
            'total': 5,
          },
        };
        final liveCommunityReport =
            generateCommunityReport(liveRoster, liveSummary);
        expect(
          liveCommunityReport,
          contains('| @quietEmeritus | Org Member | 0 | In grace period |'),
        );
        expect(
          liveCommunityReport,
          contains(
            '| @untrackedOrgMemberLow | Org Member | 2 | In grace period |',
          ),
        );
        expect(
          liveCommunityReport,
          contains(
            '| @untrackedOrgMemberHigh | Org Member | **Reviewer** | 12 | 20 |',
          ),
        );
        expect(
          liveCommunityReport,
          contains(
            '| @returningEmeritus | Dasher Emeritus | **Reviewer** (Reinstatement) | 5 | 12 |',
          ),
        );

        final livePartnerReport =
            generatePartnersReport(liveRoster, liveSummary);
        expect(
          livePartnerReport,
          contains(
            '| @newPartner | `@flutter/cloudsufi` | Maintainer | 5 contributions | [ ] Verified Active |',
          ),
        );

        // Verify --draft-issues outputs ready-to-post issue bodies and gh commands
        final draftIssuesResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--draft-issues',
          '--pr',
          'https://github.com/flutter/contributors/pull/42',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
        ]);
        expect(draftIssuesResult.exitCode, equals(0));
        final draftOutput = draftIssuesResult.stdout as String;
        expect(draftOutput, contains('Drafted Quarterly Review Issues'));
        expect(
          draftOutput,
          contains(
            '> **Proposed roster & report PR:** <https://github.com/flutter/contributors/pull/42>',
          ),
        );
        expect(draftOutput, contains('gh issue create --title'));

        // 2. Verify --finalize applies promotions, reinstatements, grace period transitions, --retain, and --discord
        final finalizeResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--finalize',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
          '--retain',
          'graceAppealedReviewer',
          '--discord',
          'promotedReviewer=promoted_discord',
        ]);
        expect(finalizeResult.exitCode, equals(0));

        final updatedYaml = contributorsFile.readAsStringSync();
        expect(
          updatedYaml,
          contains(
            'committers:\n  # Members of @flutter/committers (Child of @flutter/flutter-hackers)\n  # Granted GitHub Write role / merge access\n  - username: activeCommitter\n    role: committer\n  - username: discoveredExternal\n    role: committer\n  - username: promotedReviewer\n    discord: "promoted_discord"\n    role: committer',
          ),
        );
        expect(
          updatedYaml,
          contains(
            '  - username: graceAppealedReviewer\n    role: reviewer',
          ),
        );
        expect(
          updatedYaml,
          contains(
            '  - username: recentJoinerReviewer\n    grace_until: "2099-01-01"\n    role: reviewer',
          ),
        );
        expect(
          updatedYaml,
          contains('  - username: returningEmeritus\n    role: reviewer'),
        );
        expect(
          updatedYaml,
          contains('  - username: Mairramer\n    role: reviewer'),
        );
        expect(updatedYaml, isNot(contains('prospective_new_joiners')));
        expect(
          updatedYaml,
          contains('  - username: inactiveCommitter\n    role: emeritus'),
        );
        expect(
          updatedYaml,
          contains('  - username: inactiveReviewer\n    role: emeritus'),
        );

        // 3. Verify --exclude prevents promotion/reinstatement and --dry-run does not modify files
        contributorsFile.writeAsStringSync('''
maintainers:
  googlers:
    - username: Piinks
      role: maintainer
  partners: []
committers: []
reviewers:
  - username: promotedReviewer
    role: reviewer
prospective_new_joiners: []
dash_emeritus:
  - username: returningEmeritus
    role: emeritus
''');
        final beforeDryRun = contributorsFile.readAsStringSync();
        final dryRunResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--finalize',
          '--dry-run',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
        ]);
        expect(dryRunResult.exitCode, equals(0));
        expect(contributorsFile.readAsStringSync(), equals(beforeDryRun));

        final excludeResult = Process.runSync('dart', [
          'run',
          'tool/quarterly_audit.dart',
          '--finalize',
          '--contributors',
          contributorsFile.path,
          '--summary',
          summaryFile.path,
          '--exclude',
          'promotedReviewer,returningEmeritus,discoveredExternal',
        ]);
        expect(excludeResult.exitCode, equals(0));
        final excludedYaml = contributorsFile.readAsStringSync();
        // promotedReviewer stays in reviewers instead of promoting to committers
        expect(excludedYaml, isNot(contains('role: committer')));
        expect(
          excludedYaml,
          contains('  - username: promotedReviewer\n    role: reviewer'),
        );
        // returningEmeritus stays in dash_emeritus
        expect(
          excludedYaml,
          contains(
            'dash_emeritus:\n  # Honored alumni (External, non-org members on GitHub)\n  - username: returningEmeritus',
          ),
        );
        // discoveredExternal is excluded
        expect(excludedYaml, isNot(contains('discoveredExternal')));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('handleReviewIssues creates labels and opens issues via ProcessRunner',
        () async {
      final mockRunner = MockProcessRunner(
        stdout: 'https://github.com/flutter/contributors/issues/99\n',
      );
      const roster = ResolvedRoster(
        googlers: ['Piinks'],
        partners: [(username: 'robert-ancell', team: '@flutter/canonical')],
        committers: ['activeCommitter'],
        reviewers: [],
        unassignedOrgMembers: [],
        externalEmeriti: [],
        discordByUserLower: {},
        graceUntilByUserLower: {},
      );

      await handleReviewIssues(
        roster,
        const {},
        quarter: 'Q4 2026',
        quarterSlug: '2099-Q4',
        excludedUsers: const {},
        retainedUsers: const {},
        prLink: 'https://github.com/flutter/contributors/pull/100',
        openOnGitHub: true,
        isDryRun: false,
        runProcess: mockRunner.call,
      );

      // 4 label creations + 2 issue creations
      expect(mockRunner.calls, hasLength(6));
      for (var i = 0; i < 4; i++) {
        expect(mockRunner.calls[i].executable, equals('gh'));
        expect(
            mockRunner.calls[i].arguments.take(2), equals(['label', 'create']));
      }
      expect(
        mockRunner.calls[4].arguments.take(2),
        equals(['issue', 'create']),
      );
      expect(
        mockRunner.calls[4].arguments,
        contains(
            '[Quarterly Review]: Q4 2026 Community Contributor Ladder Audit'),
      );
      expect(
        mockRunner.calls[5].arguments.take(2),
        equals(['issue', 'create']),
      );
      expect(
        mockRunner.calls[5].arguments,
        contains('[Quarterly Review]: Q4 2026 Partner Team Verification Audit'),
      );
    });

    test('quarterly_audit.dart exits with 1 when no mode flag is provided', () {
      final result = Process.runSync('dart', [
        'run',
        'tool/quarterly_audit.dart',
      ]);
      expect(result.exitCode, equals(1));
    });
  });

  group('Check User & Grace Period Tooling Tests', () {
    test('ContributorsRoster parses YAML and round-trips entries cleanly', () {
      final roster = ContributorsRoster.parse('''
maintainers:
  googlers:
    - username: Piinks
      discord: "piinks_discord"
      role: maintainer
  partners:
    - username: robert-ancell
      team: "@flutter/canonical"
      discord: "robert_discord"
      role: maintainer
committers:
  - username: AbdeMohlbi
    discord: "abde_discord"
    role: committer
reviewers:
  - username: bdero
    grace_until: "2027-01-01"
    role: reviewer
dash_emeritus:
  - username: Hixie
    discord: "hixie_discord"
    role: emeritus
''');

      expect(roster.maintainers.googlers.single.username, equals('Piinks'));
      expect(
        roster.maintainers.partners.single.team,
        equals('@flutter/canonical'),
      );
      expect(roster.reviewers.single.graceUntil, equals('2027-01-01'));

      final reparsed = ContributorsRoster.parse(
        roster.toYamlString(lastUpdated: '2026-10-23'),
      );
      expect(reparsed.committers.single.username, equals('AbdeMohlbi'));
      expect(reparsed.committers.single.discord, equals('abde_discord'));
      expect(reparsed.dashEmeritus.single.username, equals('Hixie'));
    });

    test('findUserInfo and assessQualification evaluate all ladder tiers', () {
      final roster = ContributorsRoster.parse('''
maintainers:
  googlers:
    - username: Piinks
      discord: "piinks_discord"
      role: maintainer
  partners:
    - username: robert-ancell
      team: "@flutter/canonical"
      discord: "robert_discord"
      role: maintainer
committers:
  - username: AbdeMohlbi
    discord: "abde_discord"
    role: committer
reviewers:
  - username: bdero
    role: reviewer
dash_emeritus:
  - username: Hixie
    discord: "hixie_discord"
    role: emeritus
''');

      expect(
        findUserInfo(roster, 'piinks'),
        equals((role: 'Maintainer (Google)', discord: 'piinks_discord')),
      );
      expect(
        findUserInfo(roster, 'ROBERT-ANCELL'),
        equals((role: 'Maintainer (Partner)', discord: 'robert_discord')),
      );
      expect(
        findUserInfo(roster, 'AbdeMohlbi'),
        equals((
          role: 'Committer (@flutter/committers)',
          discord: 'abde_discord',
        )),
      );
      expect(
        findUserInfo(roster, 'bdero'),
        equals((role: 'Reviewer (@flutter/reviewers)', discord: null)),
      );
      expect(
        findUserInfo(roster, 'hixie'),
        equals((role: 'Dasher Emeritus', discord: 'hixie_discord')),
      );
      expect(
        findUserInfo(roster, 'unenrolled_user'),
        equals((role: null, discord: null)),
      );

      expect(
        assessQualification(total: 30, mergedPrs: 10),
        contains('Qualifies for: Committer'),
      );
      expect(
        assessQualification(total: 35, mergedPrs: 5),
        contains('Qualifies for: Reviewer'),
      );
      expect(
        assessQualification(total: 10, mergedPrs: 0),
        contains('Qualifies for: Reviewer'),
      );
      expect(
        assessQualification(total: 5, mergedPrs: 2),
        contains('Qualifies for: Contributor'),
      );
      expect(
        assessQualification(total: 0, mergedPrs: 0),
        contains('Inactive over the last 12 months'),
      );
    });

    test('check_user.dart CLI evaluates existing and missing arguments', () {
      final missingUser = Process.runSync('dart', [
        'run',
        'tool/check_user.dart',
      ]);
      expect(missingUser.exitCode, equals(1));

      final validUser = Process.runSync('dart', [
        'run',
        'tool/check_user.dart',
        'Piinks',
      ]);
      expect(validUser.exitCode, equals(0));
      expect(
        validUser.stdout as String,
        contains('Current Roster Status: Maintainer (Google)'),
      );
    });

    test(
        'evaluateGracePeriodIssue, buildWeeklyGracePeriodUpdateComment, and buildGracePeriodConclusionComment handle 30-day window and assignee pings',
        () {
      final now = DateTime.utc(2026, 9, 1);

      final activeIssue = {
        'number': 10,
        'title': 'Quarterly Contributor Ladder Review - Q3 2026',
        'createdAt': '2026-08-15T00:00:00Z',
        'labels': [
          {'name': 'quarterly-review'},
        ],
        'assignees': [
          {'login': 'Piinks'},
        ],
      };

      final activeEval = evaluateGracePeriodIssue(activeIssue, now: now);
      expect(activeEval.shouldRemind, isFalse);
      expect(activeEval.shouldPostWeeklyUpdate, isTrue);
      expect(activeEval.daysElapsed, equals(17));
      expect(activeEval.daysRemaining, equals(13));
      expect(activeEval.alreadyConcluded, isFalse);
      expect(activeEval.assignees, equals(['Piinks']));

      final weeklyComment = buildWeeklyGracePeriodUpdateComment(
        title: activeIssue['title'] as String,
        daysElapsed: activeEval.daysElapsed,
        createdAt: DateTime.parse(activeIssue['createdAt'] as String).toUtc(),
      );
      expect(weeklyComment, contains('## Weekly review period status update'));
      expect(weeklyComment, contains('17 day(s) (opened 2026-08-15)'));
      expect(
        weeklyComment,
        contains(
          '13 day(s) until the 30-day review window concludes on **2026-09-14**',
        ),
      );
      expect(weeklyComment, contains('If you were tagged above'));

      final expiredIssue = {
        'number': 11,
        'title': 'Quarterly Contributor Ladder Review - Q3 2026',
        'createdAt': '2026-07-31T00:00:00Z',
        'labels': [
          {'name': 'quarterly-review'},
        ],
        'assignees': [
          {'login': 'Piinks'},
        ],
      };
      final expiredEval = evaluateGracePeriodIssue(expiredIssue, now: now);
      expect(expiredEval.shouldRemind, isTrue);
      expect(expiredEval.shouldPostWeeklyUpdate, isFalse);
      expect(expiredEval.daysElapsed, equals(32));
      expect(expiredEval.daysRemaining, equals(0));
      expect(expiredEval.alreadyConcluded, isFalse);

      final concludedIssue = {
        'number': 12,
        'title': 'Quarterly Contributor Ladder Review - Q3 2026',
        'createdAt': '2026-07-31T00:00:00Z',
        'labels': [
          {'name': 'quarterly-review'},
          {'name': 'grace-period-concluded'},
        ],
      };
      final concludedEval = evaluateGracePeriodIssue(concludedIssue, now: now);
      expect(concludedEval.shouldRemind, isFalse);
      expect(concludedEval.shouldPostWeeklyUpdate, isFalse);
      expect(concludedEval.alreadyConcluded, isTrue);

      final comment = buildGracePeriodConclusionComment(
        title: 'Quarterly Contributor Ladder Review - Q3 2026',
        daysElapsed: 32,
        assignees: expiredEval.assignees,
      );
      expect(comment, contains('## 30-day review period concluded'));
      expect(comment, contains('cc @Piinks'));
      expect(comment, contains('32 days since opening'));
      expect(comment, contains('[EMERITUS.md](EMERITUS.md)'));
      expect(comment, contains('Discord usernames'));
    });

    test(
        'runGracePeriodCheck invokes gh commands via ProcessRunner for weekly updates, conclusion reminders, and dry-run',
        () async {
      final now = DateTime.utc(2026, 9, 1);
      final issuesPayload = jsonEncode([
        {
          'number': 10,
          'title': 'Community Audit Q3 2026',
          'createdAt': '2026-08-15T00:00:00Z',
          'labels': [
            {'name': 'quarterly-review'},
          ],
          'assignees': [
            {'login': 'Piinks'},
          ],
        },
        {
          'number': 11,
          'title': 'Partner Audit Q3 2026',
          'createdAt': '2026-07-31T00:00:00Z',
          'labels': [
            {'name': 'quarterly-review'},
          ],
          'assignees': [
            {'login': 'Piinks'},
          ],
        },
        {
          'number': 12,
          'title': 'Concluded Audit Q2 2026',
          'createdAt': '2026-05-01T00:00:00Z',
          'labels': [
            {'name': 'quarterly-review'},
            {'name': 'grace-period-concluded'},
          ],
          'assignees': [
            {'login': 'Piinks'},
          ],
        },
      ]);

      // 1. Live mode: lists issues, posts weekly update to #10, creates label + posts conclusion + adds label to #11, skips #12
      final liveRunner = MockProcessRunner(
        handler: (executable, arguments) async {
          if (arguments.length >= 2 &&
              arguments[0] == 'issue' &&
              arguments[1] == 'list') {
            return ProcessResult(1, 0, issuesPayload, '');
          }
          return ProcessResult(1, 0, '', '');
        },
      );

      await runGracePeriodCheck(
        isDryRun: false,
        now: now,
        runProcess: liveRunner.call,
      );

      expect(liveRunner.calls, hasLength(5));
      expect(liveRunner.calls[0].arguments.take(2), equals(['issue', 'list']));
      expect(
        liveRunner.calls[1].arguments.take(3),
        equals(['issue', 'comment', '10']),
      );
      expect(
        liveRunner.calls[1].arguments[4],
        contains('## Weekly review period status update'),
      );
      expect(
        liveRunner.calls[2].arguments.take(3),
        equals(['label', 'create', 'grace-period-concluded']),
      );
      expect(
        liveRunner.calls[3].arguments.take(3),
        equals(['issue', 'comment', '11']),
      );
      expect(
        liveRunner.calls[3].arguments[4],
        contains('## 30-day review period concluded'),
      );
      expect(
        liveRunner.calls[4].arguments,
        equals(
            ['issue', 'edit', '11', '--add-label', 'grace-period-concluded']),
      );

      // 2. Dry-run mode: lists issues only and performs zero mutations
      final dryRunner = MockProcessRunner(stdout: issuesPayload);
      await runGracePeriodCheck(
        isDryRun: true,
        now: now,
        runProcess: dryRunner.call,
      );
      expect(dryRunner.calls, hasLength(1));
      expect(
          dryRunner.calls.single.arguments.take(2), equals(['issue', 'list']));

      // 3. Error / non-zero exit handling in getOpenQuarterlyIssues
      final errorRunner = MockProcessRunner(exitCode: 1, stderr: 'auth error');
      final emptyOnFailure =
          await getOpenQuarterlyIssues(runProcess: errorRunner.call);
      expect(emptyOnFailure, isEmpty);

      final throwingRunner = MockProcessRunner(
        exceptionToThrow: const ProcessException('gh', ['issue', 'list']),
      );
      final emptyOnException =
          await getOpenQuarterlyIssues(runProcess: throwingRunner.call);
      expect(emptyOnException, isEmpty);
    });
  });
}
