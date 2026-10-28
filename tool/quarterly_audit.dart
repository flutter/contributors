// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:intl/intl.dart';

import 'bots.dart';
import 'contributors_roster.dart';
import 'github.dart';
import 'process_runner.dart';
import 'validate_roster.dart';

/// Snapshot of live `flutter` GitHub organization and team membership.
final class LiveOrgSnapshot {
  const LiveOrgSnapshot({
    required this.orgMembers,
    required this.googlers,
    required this.partners,
    required this.partnerTeams,
    this.collaborators = const {},
    this.committers = const {},
    this.reviewers = const {},
  });

  final Set<String> orgMembers;
  final Set<String> googlers;
  final Set<String> partners;
  final Map<String, String> partnerTeams;

  /// `@flutter/collaborators` is automatically managed by internal tooling and
  /// contains all organization members who are not Googlers.
  final Set<String> collaborators;
  final Set<String> committers;
  final Set<String> reviewers;
}

/// Reconciled roster combining `data/contributors.yaml` with live `flutter`
/// GitHub organization membership so every current org member is audited.
final class ResolvedRoster {
  const ResolvedRoster({
    required this.googlers,
    required this.partners,
    required this.committers,
    required this.reviewers,
    required this.unassignedOrgMembers,
    required this.externalEmeriti,
    this.formerMaintainers = const {},
    required this.discordByUserLower,
    required this.graceUntilByUserLower,
  });

  final List<String> googlers;
  final List<({String username, String team})> partners;
  final List<String> committers;
  final List<({String username, String? graceUntil})> reviewers;

  /// Current `flutter` GitHub org members who are not Maintainers, Committers,
  /// Reviewers, or bots (e.g. legacy org members pending Emeritus removal or
  /// members added to the org outside `committers`/`reviewers`).
  final List<String> unassignedOrgMembers;

  /// Dasher Emeriti in `data/contributors.yaml` who are no longer members of
  /// the `flutter` GitHub organization.
  final List<String> externalEmeriti;

  /// Former Maintainers from `data/contributors.yaml` who have left
  /// `@flutter/googlers` or `@flutter/partners` and exited the GitHub org.
  final Set<String> formerMaintainers;

  final Map<String, String> discordByUserLower;
  final Map<String, String> graceUntilByUserLower;
}

/// Queries live `flutter` GitHub organization and team membership so no current
/// org member slips through an audit.
Future<LiveOrgSnapshot?> fetchLiveOrgSnapshot(GitHubClient client) async {
  try {
    await loadRobotTeams(client);
    final orgMembers = await client.getOrgMembers('flutter');
    if (orgMembers.isEmpty) return null;
    final googlers = await client.getTeamMembers('flutter', 'googlers');
    final partners = await client.getTeamMembers('flutter', 'partners');
    final collaborators =
        await client.getTeamMembers('flutter', 'collaborators');
    final partnerTeams = <String, String>{};
    try {
      final childSlugs = await client.getChildTeams('flutter', 'partners');
      for (final slug in childSlugs) {
        final members = await client.getTeamMembers('flutter', slug);
        for (final m in members) {
          partnerTeams[m.toLowerCase()] = '@flutter/$slug';
        }
      }
    } catch (e) {
      stderr.writeln(
          'Notice: Could not resolve @flutter/partners child teams: $e');
    }
    final committers = await client.getTeamMembers('flutter', 'committers');
    final reviewers = await client.getTeamMembers('flutter', 'reviewers');
    return LiveOrgSnapshot(
      orgMembers: orgMembers,
      googlers: googlers,
      partners: partners,
      partnerTeams: partnerTeams,
      collaborators: collaborators,
      committers: committers,
      reviewers: reviewers,
    );
  } catch (e) {
    stderr.writeln(
        'Notice: Could not query live Flutter GitHub org ($e); falling back to data/contributors.yaml.');
    return null;
  }
}

/// Reconciles `data/contributors.yaml` ([doc]) with [liveOrg] so that 100% of
/// current `flutter` GitHub organization members are categorized and evaluated.
ResolvedRoster reconcileRosterState(
  ContributorsRoster doc, {
  LiveOrgSnapshot? liveOrg,
  DateTime? referenceDate,
}) {
  final now = (referenceDate ?? DateTime.now()).toUtc();
  final todayUtc = DateTime.utc(now.year, now.month, now.day);

  final discordByUserLower = <String, String>{};
  final graceUntilByUserLower = <String, String>{};
  final yamlPartnerTeamsLower = <String, String>{};
  final canonicalNameLower = <String, String>{};

  void recordMetadata(ContributorEntry entry) {
    final u = entry.username;
    if (u.isEmpty) return;
    final lower = u.toLowerCase();
    canonicalNameLower.putIfAbsent(lower, () => u);
    final d = entry.discord;
    final g = entry.graceUntil;
    if (d != null && d.isNotEmpty) {
      discordByUserLower[lower] = d;
    }
    if (g != null && g.isNotEmpty) {
      final parsed = DateTime.tryParse(g);
      if (parsed != null && !parsed.isBefore(todayUtc)) {
        graceUntilByUserLower[lower] = g;
      }
    }
  }

  final yamlMaintainersLower = <String>{};
  for (final g in doc.maintainers.googlers) {
    recordMetadata(g);
    if (g.username.isNotEmpty) {
      yamlMaintainersLower.add(g.username.toLowerCase());
    }
  }
  for (final p in doc.maintainers.partners) {
    recordMetadata(p);
    if (p.username.isNotEmpty) {
      final lower = p.username.toLowerCase();
      yamlMaintainersLower.add(lower);
      if (p.team != null) {
        yamlPartnerTeamsLower[lower] = p.team!;
      }
    }
  }
  for (final entry in [
    ...doc.committers,
    ...doc.reviewers,
    ...doc.dashEmeritus,
  ]) {
    recordMetadata(entry);
  }

  final seenMaintainersLower = <String>{};

  // 1. Partners (@flutter/partners)
  final partners = <({String username, String team})>[];
  if (liveOrg != null && liveOrg.partners.isNotEmpty) {
    for (final u in liveOrg.partners) {
      if (isExcludedAccount(u)) continue;
      final lower = u.toLowerCase();
      if (!seenMaintainersLower.add(lower)) continue;
      final team = liveOrg.partnerTeams[lower] ??
          yamlPartnerTeamsLower[lower] ??
          '@flutter/partners';
      partners.add((username: canonicalNameLower[lower] ?? u, team: team));
    }
  } else {
    for (final p in doc.maintainers.partners) {
      final u = p.username;
      if (u.isEmpty || isExcludedAccount(u)) continue;
      final lower = u.toLowerCase();
      if (!seenMaintainersLower.add(lower)) continue;
      partners.add((
        username: u,
        team: p.team ?? '@flutter/partners',
      ));
    }
  }
  partners.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));

  // 2. Googlers (@flutter/googlers + known_maintainers.txt, excluding Partners)
  final googlers = <String>[];
  final googlerCandidates = <String>[
    if (liveOrg != null && liveOrg.googlers.isNotEmpty)
      ...liveOrg.googlers
    else
      for (final g in doc.maintainers.googlers) g.username,
    ...loadKnownExceptionMaintainers(),
  ];
  for (final u in googlerCandidates) {
    if (u.isEmpty || isExcludedAccount(u)) continue;
    final lower = u.toLowerCase();
    if (seenMaintainersLower.add(lower)) {
      googlers.add(canonicalNameLower[lower] ?? u);
    }
  }
  googlers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  // 3. Committers & Reviewers
  final seenCommunityLower = <String>{};
  final committers = <String>[];
  final committerCandidates = <String>[
    for (final c in doc.committers) c.username,
    if (liveOrg != null) ...liveOrg.committers,
  ];
  for (final u in committerCandidates) {
    if (u.isEmpty || isExcludedAccount(u)) continue;
    final lower = u.toLowerCase();
    if (seenMaintainersLower.contains(lower)) continue;
    if (seenCommunityLower.add(lower)) {
      committers.add(canonicalNameLower[lower] ?? u);
    }
  }
  committers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final reviewers = <({String username, String? graceUntil})>[];
  final reviewerCandidates = <String>[
    for (final r in doc.reviewers) r.username,
    if (liveOrg != null) ...liveOrg.reviewers,
  ];
  for (final u in reviewerCandidates) {
    if (u.isEmpty || isExcludedAccount(u)) continue;
    final lower = u.toLowerCase();
    if (seenMaintainersLower.contains(lower) ||
        seenCommunityLower.contains(lower)) {
      continue;
    }
    if (seenCommunityLower.add(lower)) {
      reviewers.add((
        username: canonicalNameLower[lower] ?? u,
        graceUntil: graceUntilByUserLower[lower],
      ));
    }
  }
  reviewers.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));

  // 4. All other non-Maintainer, non-bot members currently in the `flutter` GitHub org
  // Note: `@flutter/collaborators` is automatically managed by internal tooling for
  // non-Googler org members, though due to an internal sync issue the known exception
  // Googlers in `known_maintainers.txt` also appear in `@flutter/collaborators` and
  // are already excluded via `seenMaintainersLower` above.
  final unassignedOrgMembers = <String>[];
  if (liveOrg != null &&
      (liveOrg.orgMembers.isNotEmpty || liveOrg.collaborators.isNotEmpty)) {
    for (final u in [...liveOrg.orgMembers, ...liveOrg.collaborators]) {
      if (isExcludedAccount(u)) continue;
      final lower = u.toLowerCase();
      if (seenMaintainersLower.contains(lower) ||
          seenCommunityLower.contains(lower)) {
        continue;
      }
      if (seenCommunityLower.add(lower)) {
        unassignedOrgMembers.add(canonicalNameLower[lower] ?? u);
      }
    }
  }
  unassignedOrgMembers
      .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  // 5. External Dasher Emeriti (no longer in the `flutter` GitHub org)
  final externalEmeriti = <String>[];
  for (final e in doc.dashEmeritus) {
    final u = e.username;
    if (u.isEmpty || isExcludedAccount(u)) continue;
    final lower = u.toLowerCase();
    if (seenMaintainersLower.contains(lower) ||
        seenCommunityLower.contains(lower)) {
      continue;
    }
    // If liveOrg is present and this dash_emeritus entry is no longer in the
    // live org and has 0 activity, check if they were a renamed account or
    // genuine Emeritus alumni.
    if (seenCommunityLower.add(lower)) {
      externalEmeriti.add(u);
    }
  }
  externalEmeriti.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final formerMaintainers = yamlMaintainersLower
      .difference(seenMaintainersLower)
      .difference(seenCommunityLower);

  return ResolvedRoster(
    googlers: googlers,
    partners: partners,
    committers: committers,
    reviewers: reviewers,
    unassignedOrgMembers: unassignedOrgMembers,
    externalEmeriti: externalEmeriti,
    formerMaintainers: formerMaintainers,
    discordByUserLower: discordByUserLower,
    graceUntilByUserLower: graceUntilByUserLower,
  );
}

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('prepare',
        help:
            'Run the full local kickoff: vet nominated candidates against the ban list, generate reports, and update the roster for a single PR',
        defaultsTo: false)
    ..addFlag('community',
        help: 'Generate Community Contributor Ladder Audit Report',
        defaultsTo: false)
    ..addFlag('partners',
        help: 'Generate Partner Affiliation Verification Audit Report',
        defaultsTo: false)
    ..addFlag('save',
        help: 'Save generated report into reports/ directory',
        defaultsTo: false)
    ..addFlag('draft-issues',
        help:
            'Output drafted issue bodies and gh CLI commands based on the generated reports to start the 30-day review period',
        defaultsTo: false)
    ..addFlag('open-issues',
        help:
            'Open the public Community Review and Partner Verification issues on GitHub using the generated reports',
        defaultsTo: false)
    ..addFlag('finalize',
        help:
            'Apply verified audit changes (e.g. after the 30-day grace period) to data/contributors.yaml, ROSTER.md, and EMERITUS.md',
        defaultsTo: false)
    ..addFlag('dry-run',
        help:
            'Preview changes without modifying files on disk or opening GitHub issues',
        defaultsTo: false)
    ..addFlag('offline',
        help:
            'Skip querying live Flutter GitHub organization membership and use only local files',
        defaultsTo: false)
    ..addFlag('no-prompt',
        help: 'Disable interactive terminal prompts during --prepare',
        defaultsTo: false)
    ..addOption('retain',
        help:
            'Comma-separated usernames to retain in their current role (e.g. verified qualitative contributions)')
    ..addOption('exclude',
        help:
            'Comma-separated usernames to exclude from promotion, reinstatement, or invitation (e.g. prior ban history or declined invite)')
    ..addOption('discord',
        help:
            'Comma-separated user=discord_handle mappings to record in contributors.yaml')
    ..addOption('pr',
        help:
            'Optional PR URL or number to link in the drafted/opened review issues')
    ..addOption('contributors',
        help: 'Path to contributors YAML file',
        defaultsTo: 'data/contributors.yaml')
    ..addOption('summary',
        help: 'Path to activity summary JSON file',
        defaultsTo: 'data/activity_summary.json')
    ..addOption('output',
        abbr: 'o',
        help:
            'Output file path for generated report (prints to stdout if omitted)');

  final results = parser.parse(args);
  final isPrepare = results['prepare'] as bool;
  final isCommunity = results['community'] as bool;
  final isPartners = results['partners'] as bool;
  final isSave = results['save'] as bool;
  final isDraftIssues = results['draft-issues'] as bool;
  final isOpenIssues = results['open-issues'] as bool;
  final isFinalize = results['finalize'] as bool;
  final isDryRun = results['dry-run'] as bool;
  final isOffline = results['offline'] as bool;
  final noPrompt = results['no-prompt'] as bool;
  final retainArg = results['retain'] as String?;
  final excludeArg = results['exclude'] as String?;
  final discordArg = results['discord'] as String?;
  final prArg = results['pr'] as String?;
  final contributorsPath = results['contributors'] as String;
  final summaryPath = results['summary'] as String;
  var outputPath = results['output'] as String?;

  if (!isPrepare &&
      !isCommunity &&
      !isPartners &&
      !isDraftIssues &&
      !isOpenIssues &&
      !isFinalize) {
    print(
        'Usage: dart run tool/quarterly_audit.dart [--prepare | --community | --partners | --draft-issues | --open-issues | --finalize] [--save] [--dry-run] [--offline] [--retain u1,u2] [--exclude u1,u2] [--discord u1=d1] [--pr <PR_URL>]');
    exit(1);
  }

  final contributorsYamlFile = File(contributorsPath);
  if (!contributorsYamlFile.existsSync()) {
    print('Error: $contributorsPath not found.');
    exit(1);
  }

  final summaryFile = File(summaryPath);
  var summary = <String, dynamic>{};
  if (summaryFile.existsSync()) {
    try {
      summary =
          jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      print('Warning: Failed to parse $summaryPath: $e');
    }
  }

  final doc = ContributorsRoster.parse(contributorsYamlFile.readAsStringSync());
  final now = DateTime.now().toUtc();
  final quarter = 'Q${((now.month - 1) ~/ 3) + 1} ${now.year}';
  final quarterSlug = '${now.year}-Q${((now.month - 1) ~/ 3) + 1}';

  final reportsDir = Directory('reports');
  if (!reportsDir.existsSync()) {
    reportsDir.createSync(recursive: true);
  }

  final retainedUsers = _parseUserSet(retainArg);
  final excludedUsers = _parseUserSet(excludeArg);
  final discordOverrides = _parseDiscordMap(discordArg);

  // Query live Flutter GitHub organization membership by default when operating
  // on the primary roster so no current org member slips through.
  LiveOrgSnapshot? liveOrg;
  if (!isOffline && contributorsPath == 'data/contributors.yaml') {
    final client = GitHubClient();
    try {
      liveOrg = await fetchLiveOrgSnapshot(client);
    } finally {
      client.close();
    }
  }

  final roster =
      reconcileRosterState(doc, liveOrg: liveOrg, referenceDate: now);

  if (isPrepare) {
    _runPrepare(
      roster,
      summary,
      contributorsFile: contributorsYamlFile,
      quarter: quarter,
      quarterSlug: quarterSlug,
      retainedUsers: retainedUsers,
      excludedUsers: excludedUsers,
      discordOverrides: discordOverrides,
      isDryRun: isDryRun,
      allowPrompt: !noPrompt && excludeArg == null && stdin.hasTerminal,
    );
    return;
  }

  if (isCommunity) {
    if (isSave && outputPath == null) {
      outputPath = 'reports/$quarterSlug-community-ladder-audit.md';
    }
    final report = generateCommunityReport(
      roster,
      summary,
      excludedUsers: excludedUsers,
      retainedUsers: retainedUsers,
      prLink: prArg,
    );
    _outputReport(report, outputPath);
  } else if (isPartners) {
    if (isSave && outputPath == null) {
      outputPath = 'reports/$quarterSlug-partner-verification-audit.md';
    }
    final report = generatePartnersReport(roster, summary, prLink: prArg);
    _outputReport(report, outputPath);
  } else if (isFinalize) {
    final communityReportFile =
        File('reports/$quarterSlug-community-ladder-audit.md');
    _finalizeAudit(
      roster,
      summary,
      contributorsFile: contributorsYamlFile,
      retainedUsers: retainedUsers,
      excludedUsers: excludedUsers,
      discordOverrides: discordOverrides,
      isDryRun: isDryRun,
      existingCommunityReportFile:
          communityReportFile.existsSync() ? communityReportFile : null,
    );
  }

  if (isDraftIssues || isOpenIssues) {
    await handleReviewIssues(
      roster,
      summary,
      quarter: quarter,
      quarterSlug: quarterSlug,
      excludedUsers: excludedUsers,
      retainedUsers: retainedUsers,
      prLink: prArg,
      openOnGitHub: isOpenIssues,
      isDryRun: isDryRun,
    );
  }
}

/// Interactive/CLI kickoff helper that lists nominated candidates for manual
/// ban-history verification, generates both quarterly reports (omitting any
/// excluded users), and updates `data/contributors.yaml`, `ROSTER.md`, and
/// `EMERITUS.md` so the facilitator only needs to open a single PR.
void _runPrepare(
  ResolvedRoster roster,
  Map<String, dynamic> summary, {
  required File contributorsFile,
  required String quarter,
  required String quarterSlug,
  required Set<String> retainedUsers,
  required Set<String> excludedUsers,
  required Map<String, String> discordOverrides,
  required bool isDryRun,
  required bool allowPrompt,
}) {
  print('=== Quarterly Contributor Ladder Audit Preparation ($quarter) ===\n');

  final nominees = collectNominatedCandidates(roster, summary);
  if (nominees.isEmpty) {
    print('No new promotions, reinstatements, or prospective joiners found.');
  } else {
    print(
        'Nominated candidates for promotion, reinstatement, or invitation (${nominees.length}):');
    for (final n in nominees) {
      print(
          '  • @${n.username} (${n.currentStatus} -> ${n.recommendedRole}: ${n.mergedPrs} PRs, ${n.total} total)');
    }
    print('');
    print(
        'ACTION REQUIRED: Check the ${nominees.length} username(s) above against the internal Code of Conduct / ban history list.');
    if (allowPrompt) {
      stdout.write(
          'Enter any usernames to exclude (comma-separated, or press Enter for none): ');
      final input = stdin.readLineSync();
      excludedUsers.addAll(_parseUserSet(input));
    }
  }

  if (excludedUsers.isNotEmpty) {
    print(
        'Excluding from promotion/invitation (omitted from report & roster): ${excludedUsers.join(", ")}');
  }

  final communityPath = 'reports/$quarterSlug-community-ladder-audit.md';
  final partnerPath = 'reports/$quarterSlug-partner-verification-audit.md';

  final communityReport = generateCommunityReport(
    roster,
    summary,
    excludedUsers: excludedUsers,
    retainedUsers: retainedUsers,
  );
  final partnerReport = generatePartnersReport(roster, summary);

  if (isDryRun) {
    print('\n[DRY RUN] Would write reports to:');
    print('  • $communityPath');
    print('  • $partnerPath');
  } else {
    File(communityPath).writeAsStringSync(communityReport);
    File(partnerPath).writeAsStringSync(partnerReport);
    print('\nSaved vetted quarterly reports:');
    print('  • $communityPath');
    print('  • $partnerPath');
  }

  print('');
  _finalizeAudit(
    roster,
    summary,
    contributorsFile: contributorsFile,
    retainedUsers: retainedUsers,
    excludedUsers: excludedUsers,
    discordOverrides: discordOverrides,
    isDryRun: isDryRun,
  );

  print('\n=== Next Steps ===');
  print(
      '1. Open 1 PR with the reports and roster updates (hold open for the 30-day review period):');
  print('   git add reports/ data/contributors.yaml ROSTER.md EMERITUS.md');
  print(
      '   git commit -m "chore: $quarter quarterly contributor ladder review"');
  print(
      '2. Start the 30-day community review period by drafting or opening the public issues:');
  print('   dart run tool/quarterly_audit.dart --draft-issues --pr <PR_URL>');
  print('   dart run tool/quarterly_audit.dart --open-issues --pr <PR_URL>');
  print(
      '3. After 30 days, update the PR branch with any review adjustments and merge it:');
  print(
      '   dart run tool/quarterly_audit.dart --finalize --retain u1,u2 --exclude u3 --discord new_user=handle');
}

/// Drafts or opens the public Community Ladder Audit and Partner Verification
/// issues on GitHub using the vetted report files.
Future<void> handleReviewIssues(
  ResolvedRoster roster,
  Map<String, dynamic> summary, {
  required String quarter,
  required String quarterSlug,
  required Set<String> excludedUsers,
  required Set<String> retainedUsers,
  required String? prLink,
  required bool openOnGitHub,
  required bool isDryRun,
  ProcessRunner runProcess = Process.run,
}) async {
  final communityFile = File('reports/$quarterSlug-community-ladder-audit.md');
  final partnerFile =
      File('reports/$quarterSlug-partner-verification-audit.md');

  var communityBody = communityFile.existsSync()
      ? communityFile.readAsStringSync()
      : generateCommunityReport(
          roster,
          summary,
          excludedUsers: excludedUsers,
          retainedUsers: retainedUsers,
          prLink: prLink,
        );
  var partnerBody = partnerFile.existsSync()
      ? partnerFile.readAsStringSync()
      : generatePartnersReport(roster, summary, prLink: prLink);

  if (prLink != null && prLink.trim().isNotEmpty) {
    final prLine =
        '> **Proposed roster & report PR:** ${_formatPrReference(prLink)}  \n';
    if (!communityBody.contains('Proposed roster & report PR:')) {
      communityBody = communityBody.replaceFirst(
        '> **Governance reference:**',
        '$prLine> **Governance reference:**',
      );
    }
    if (!partnerBody.contains('Proposed roster & report PR:')) {
      partnerBody = partnerBody.replaceFirst(
        '> **Governance reference:**',
        '$prLine> **Governance reference:**',
      );
    }
  }

  final communityTitle =
      '[Quarterly Review]: $quarter Community Contributor Ladder Audit';
  final partnerTitle =
      '[Quarterly Review]: $quarter Partner Team Verification Audit';

  if (!openOnGitHub || isDryRun) {
    print('=== Drafted Quarterly Review Issues ($quarter) ===\n');
    print('1. Community Audit Issue:');
    print('   Title:  $communityTitle');
    print('   Labels: quarterly-review,community-audit');
    print(
      '   Command: gh issue create --title "$communityTitle" --body-file ${communityFile.path} --label "quarterly-review,community-audit" --assignee "Piinks"\n',
    );
    print('2. Partner Verification Issue:');
    print('   Title:  $partnerTitle');
    print('   Labels: quarterly-review,partner-audit');
    print(
      '   Command: gh issue create --title "$partnerTitle" --body-file ${partnerFile.path} --label "quarterly-review,partner-audit" --assignee "Piinks"\n',
    );
    print('--- Community Issue Body Preview ---');
    print(communityBody);
    print('--- Partner Issue Body Preview ---');
    print(partnerBody);
    return;
  }

  // Ensure labels exist
  const labels = [
    (
      'quarterly-review',
      'Quarterly Contributor Ladder Review',
      '1D76DB',
    ),
    (
      'community-audit',
      'Community Contributor Ladder Audit',
      '0E8A16',
    ),
    (
      'partner-audit',
      'Partner Team Verification Audit',
      '5319E7',
    ),
    (
      'grace-period-concluded',
      '30-day review period elapsed',
      'FBCA04',
    ),
  ];
  for (final l in labels) {
    await runProcess('gh', [
      'label',
      'create',
      l.$1,
      '--description',
      l.$2,
      '--color',
      l.$3,
      '--force',
    ]);
  }

  final commResult = await runProcess('gh', [
    'issue',
    'create',
    '--title',
    communityTitle,
    '--body',
    communityBody,
    '--label',
    'quarterly-review,community-audit',
    '--assignee',
    'Piinks',
  ]);
  if (commResult.exitCode == 0) {
    print(
      'Created Community Audit Issue: ${(commResult.stdout as String).trim()}',
    );
  } else {
    print('Failed to create Community Audit Issue: ${commResult.stderr}');
  }

  final partResult = await runProcess('gh', [
    'issue',
    'create',
    '--title',
    partnerTitle,
    '--body',
    partnerBody,
    '--label',
    'quarterly-review,partner-audit',
    '--assignee',
    'Piinks',
  ]);
  if (partResult.exitCode == 0) {
    print(
      'Created Partner Verification Issue: ${(partResult.stdout as String).trim()}',
    );
  } else {
    print('Failed to create Partner Verification Issue: ${partResult.stderr}');
  }
}

List<
    ({
      String username,
      String currentStatus,
      String recommendedRole,
      int mergedPrs,
      int total,
    })> collectNominatedCandidates(
  ResolvedRoster roster,
  Map<String, dynamic> summary,
) {
  final nominees = <({
    String username,
    String currentStatus,
    String recommendedRole,
    int mergedPrs,
    int total,
  })>[];

  for (final r in roster.reviewers) {
    final username = r.username;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 30 && prs >= 10) {
      nominees.add((
        username: username,
        currentStatus: 'Reviewer',
        recommendedRole: 'Committer',
        mergedPrs: prs,
        total: total,
      ));
    }
  }

  for (final username in roster.unassignedOrgMembers) {
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 10) {
      final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
      nominees.add((
        username: username,
        currentStatus: 'Org Member',
        recommendedRole: role,
        mergedPrs: prs,
        total: total,
      ));
    }
  }

  for (final username in roster.externalEmeriti) {
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 10) {
      final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
      nominees.add((
        username: username,
        currentStatus: 'Dasher Emeritus',
        recommendedRole: '$role (Reinstatement)',
        mergedPrs: prs,
        total: total,
      ));
    }
  }

  final externalCandidates = _discoverExternalCandidates(roster, summary);
  for (final username in externalCandidates) {
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
    nominees.add((
      username: username,
      currentStatus: 'External Contributor',
      recommendedRole: '$role (Invitation)',
      mergedPrs: prs,
      total: total,
    ));
  }

  return nominees;
}

Map<String, String> _parseDiscordMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  final map = <String, String>{};
  for (final pair in raw.split(',')) {
    final parts = pair.split('=');
    if (parts.length == 2) {
      final user = parts[0].trim().replaceAll('@', '').toLowerCase();
      final discord = parts[1].trim();
      if (user.isNotEmpty && discord.isNotEmpty) {
        map[user] = discord;
      }
    }
  }
  return map;
}

Set<String> _parseUserSet(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  return raw
      .split(',')
      .map((s) => s.trim().replaceAll('@', '').toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();
}

/// Collects all lowercase usernames currently tracked in the resolved roster.
Set<String> _collectEnrolledAndEmeritusLower(ResolvedRoster roster) {
  return <String>{
    ...loadKnownExceptionMaintainers().map((u) => u.toLowerCase()),
    ...roster.googlers.map((u) => u.toLowerCase()),
    ...roster.partners.map((p) => p.username.toLowerCase()),
    ...roster.committers.map((u) => u.toLowerCase()),
    ...roster.reviewers.map((r) => r.username.toLowerCase()),
    ...roster.unassignedOrgMembers.map((u) => u.toLowerCase()),
    ...roster.externalEmeriti.map((u) => u.toLowerCase()),
    ...roster.formerMaintainers,
  };
}

/// Discovers unenrolled external contributors who have >= 10 qualifying
/// contributions in [summary].
List<String> _discoverExternalCandidates(
    ResolvedRoster roster, Map<String, dynamic> summary) {
  final enrolledOrEmeritus = _collectEnrolledAndEmeritusLower(roster);
  final seenLower = <String>{};
  final candidates = <String>[];

  for (final entry in summary.entries) {
    final username = entry.key;
    if (isExcludedAccount(username)) continue;
    final lower = username.toLowerCase();
    if (enrolledOrEmeritus.contains(lower) || seenLower.contains(lower)) {
      continue;
    }
    final stats = entry.value as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    if (total >= 10) {
      seenLower.add(lower);
      candidates.add(username);
    }
  }

  candidates.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return candidates;
}

/// Returns true if the Reviewer entry [r] has an active one-time Year 1
/// transition carve-out (`grace_until` date on or after [now]). Once the
/// initial 12-month launch transition window passes, this naturally expires.
bool hasActiveRecentJoinerCarveOut(ContributorEntry r, DateTime now) {
  return _isGraceDateActive(r.graceUntil, now);
}

bool _isGraceDateActive(String? graceUntilStr, DateTime now) {
  if (graceUntilStr == null || graceUntilStr.trim().isEmpty) return false;
  final graceUntil = DateTime.tryParse(graceUntilStr.trim());
  if (graceUntil == null) return false;
  final todayUtc = DateTime.utc(now.year, now.month, now.day);
  return !graceUntil.isBefore(todayUtc);
}

String _formatPrReference(String prLink) {
  final trimmed = prLink.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return '<$trimmed>';
  }
  return trimmed;
}

String _formatTableRowsBlock(List<String> rows) =>
    rows.isEmpty ? '' : '\n${rows.join('\n')}';

String generateCommunityReport(
  ResolvedRoster roster,
  Map<String, dynamic> summary, {
  Set<String> excludedUsers = const {},
  Set<String> retainedUsers = const {},
  String? prLink,
}) {
  final now = DateTime.now().toUtc();
  final oneYearAgo = now.subtract(const Duration(days: 365));
  final graceDeadline = now.add(const Duration(days: 30));
  final quarter = 'Q${((now.month - 1) ~/ 3) + 1} ${now.year}';
  final dateFmt = DateFormat('MMMM d, yyyy');
  final prLineBlock = (prLink != null && prLink.trim().isNotEmpty)
      ? '\n> **Proposed roster & report PR:** ${_formatPrReference(prLink)}  '
      : '';

  // 1. Recommended Promotions & New Community Joiners
  final promotionRows = <String>[];
  for (final r in roster.reviewers) {
    final username = r.username;
    if (excludedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 30 && prs >= 10) {
      promotionRows
          .add('| @$username | Reviewer | **Committer** | $prs | $total |');
    }
  }
  for (final username in roster.unassignedOrgMembers) {
    if (excludedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 10) {
      final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
      promotionRows
          .add('| @$username | Org Member | **$role** | $prs | $total |');
    }
  }
  for (final username in roster.externalEmeriti) {
    if (excludedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 10) {
      final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
      promotionRows.add(
        '| @$username | Dasher Emeritus | **$role** (Reinstatement) | $prs | $total |',
      );
    }
  }
  final externalCandidates = _discoverExternalCandidates(roster, summary);
  for (final username in externalCandidates) {
    if (excludedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    final role = (total >= 30 && prs >= 10) ? 'Committer' : 'Reviewer';
    promotionRows.add(
      '| @$username | External Contributor | **$role** (Invitation) | $prs | $total |',
    );
  }

  // 2. Active Role Retention
  final retentionRows = <String>[];
  for (final username in roster.committers) {
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 10 || retainedUsers.contains(username.toLowerCase())) {
      retentionRows.add('| @$username | Committer | $prs | $total |');
    }
  }
  for (final r in roster.reviewers) {
    final username = r.username;
    final lower = username.toLowerCase();
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    final isPromoted =
        total >= 30 && prs >= 10 && !excludedUsers.contains(lower);
    if ((total >= 10 || retainedUsers.contains(lower)) && !isPromoted) {
      retentionRows.add('| @$username | Reviewer | $prs | $total |');
    } else if (total < 10 &&
        !retainedUsers.contains(lower) &&
        _isGraceDateActive(r.graceUntil, now)) {
      retentionRows.add(
        '| @$username | Reviewer (12m recent-joiner carve-out) | $prs | $total |',
      );
    }
  }
  for (final username in roster.unassignedOrgMembers) {
    final lower = username.toLowerCase();
    if (!retainedUsers.contains(lower)) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total < 10) {
      retentionRows.add('| @$username | Reviewer | $prs | $total |');
    }
  }

  // 3. 30-Day Grace Period
  final gracePeriodRows = <String>[];
  for (final username in roster.committers) {
    if (retainedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    if (total < 10) {
      gracePeriodRows
          .add('| @$username | Committer | $total | In grace period |');
    }
  }
  for (final r in roster.reviewers) {
    final username = r.username;
    if (retainedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    if (total < 10 && !_isGraceDateActive(r.graceUntil, now)) {
      gracePeriodRows
          .add('| @$username | Reviewer | $total | In grace period |');
    }
  }
  for (final username in roster.unassignedOrgMembers) {
    if (retainedUsers.contains(username.toLowerCase())) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    if (total < 10) {
      gracePeriodRows
          .add('| @$username | Org Member | $total | In grace period |');
    }
  }

  final promotionBlock = _formatTableRowsBlock(promotionRows);
  final retentionBlock = _formatTableRowsBlock(retentionRows);
  final gracePeriodBlock = _formatTableRowsBlock(gracePeriodRows);

  return '''
# Quarterly Community Contributor Ladder Audit ($quarter)

> **Audit date:** ${dateFmt.format(now)}  
> **12-month evaluation window:** ${dateFmt.format(oneYearAgo)} – ${dateFmt.format(now)}  
> **30-day grace period deadline:** ${dateFmt.format(graceDeadline)}  $prLineBlock
> **Governance reference:** [docs/LADDER.md](docs/LADDER.md) • [docs/QUARTERLY_REVIEW.md](docs/QUARTERLY_REVIEW.md)

This issue tracks the $quarter Flutter Contributor Ladder review and starts the 30-day community review period.

## Recommended promotions and new joiners

The following contributors qualify for role advancement or invitation to the ladder.
If you are listed below, please reply in this thread to accept your invitation or promotion and share your **Discord username** (if you do not already have the Discord team member role) so we can grant you team member channel access:

| Contributor | Current status | Recommended role | 12m merged PRs | 12m total activity |
| :--- | :--- | :--- | :--- | :--- |$promotionBlock

## Active role retention

The following community members met their 12-month role criteria and retain their roles:

| Contributor | Role | 12m merged PRs | 12m total activity |
| :--- | :--- | :--- | :--- |$retentionBlock

## 30-day grace period

The following members had < 10 contributions recorded in the last 12 months.
If you are listed below, you have 30 days to respond in this thread with any contributions that cannot be quantified automatically (issue triage, reproductions, [RFCs](https://github.com/flutter/rfc), mentoring).

| Contributor | Current role | 12m total activity | Status |
| :--- | :--- | :--- | :--- |$gracePeriodBlock

## Qualitative contributions

If you contributed through work not reflected in automated PR counts:

- Verifying issue reproductions, closing obsolete issues, and issue triage
- Reviewing design docs and [RFCs](https://github.com/flutter/rfc)
- Mentoring contributors or helping in Discord

Please leave a comment below with links or details before this review concludes on **${dateFmt.format(graceDeadline)}**.
''';
}

String generatePartnersReport(
  ResolvedRoster roster,
  Map<String, dynamic> summary, {
  String? prLink,
}) {
  final now = DateTime.now().toUtc();
  final quarter = 'Q${((now.month - 1) ~/ 3) + 1} ${now.year}';
  final dateFmt = DateFormat('MMMM d, yyyy');
  final prLineBlock = (prLink != null && prLink.trim().isNotEmpty)
      ? '\n> **Proposed roster & report PR:** ${_formatPrReference(prLink)}  '
      : '';

  final partnerRows = <String>[
    for (final p in roster.partners)
      () {
        final stats = summary[p.username] as Map<String, dynamic>?;
        final total = stats?['total'] as int? ?? 0;
        return '| @${p.username} | `${p.team}` | Maintainer | $total contributions | [ ] Verified Active |';
      }(),
  ];
  final partnerBlock = _formatTableRowsBlock(partnerRows);

  return '''
# Quarterly Partner Team Verification Audit ($quarter)

> **Audit date:** ${dateFmt.format(now)}  
> **Audit quarter:** $quarter  
> **Target team:** `@flutter/partners`  $prLineBlock
> **Governance reference:** [docs/QUARTERLY_REVIEW.md](docs/QUARTERLY_REVIEW.md) • [docs/GOVERNANCE.md](docs/GOVERNANCE.md)

This issue tracks quarterly verification for `@flutter/partners`.
The audit facilitator reaches out to each partner organization to confirm active participation for the members below.

## Active partner team members

| Contributor | Partner team | Role | 12m activity snapshot | Status verification |
| :--- | :--- | :--- | :--- | :--- |$partnerBlock

## Departures and offboarding

If any listed engineer has concluded their engagement with the partners team:

1. Confirm offboarding to revoke `@flutter/partners` write access.
2. If the departing engineer remains an active open-source contributor, specify their community ladder placement (`Committer` or `Reviewer`).

- [ ] All partner memberships confirmed with partner organizations.
''';
}

/// Parses an existing `reports/YYYY-QX-community-ladder-audit.md` file to
/// recover the pre-audit status of contributors in case `--finalize` is run on
/// a PR branch where `--prepare` already updated `data/contributors.yaml`.
({
  Map<String, String> gracePeriodRolesLower,
  Map<String, String> promotedInitialStatusLower,
}) _parseExistingReportState(File? reportFile) {
  final gracePeriodRolesLower = <String, String>{};
  final promotedInitialStatusLower = <String, String>{};
  if (reportFile == null || !reportFile.existsSync()) {
    return (
      gracePeriodRolesLower: gracePeriodRolesLower,
      promotedInitialStatusLower: promotedInitialStatusLower,
    );
  }

  var section = '';
  for (final line in reportFile.readAsLinesSync()) {
    if (line.startsWith('## ')) {
      section = line.trim();
      continue;
    }
    if (!line.startsWith('| @')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;
    final username = cells[1].replaceAll('@', '').toLowerCase();
    if (section.contains('Recommended promotions')) {
      promotedInitialStatusLower[username] = cells[2];
    } else if (section.contains('30-day grace period')) {
      gracePeriodRolesLower[username] = cells[2];
    }
  }

  return (
    gracePeriodRolesLower: gracePeriodRolesLower,
    promotedInitialStatusLower: promotedInitialStatusLower,
  );
}

void _finalizeAudit(
  ResolvedRoster roster,
  Map<String, dynamic> summary, {
  required File contributorsFile,
  required Set<String> retainedUsers,
  required Set<String> excludedUsers,
  required Map<String, String> discordOverrides,
  required bool isDryRun,
  File? existingCommunityReportFile,
}) {
  print('Applying quarterly review updates to ${contributorsFile.path}...');
  if (isDryRun) {
    print('Running in DRY-RUN mode. No files will be modified.');
  }

  final reportState = _parseExistingReportState(existingCommunityReportFile);

  final discordByUserLower = <String, String>{
    ...roster.discordByUserLower,
    ...discordOverrides,
  };
  final graceUntilByUserLower = <String, String>{
    ...roster.graceUntilByUserLower,
  };

  String? getDiscord(String username) =>
      discordByUserLower[username.toLowerCase()];

  final updatedCommitters = <String>[];
  final updatedReviewers = <String>[];
  final updatedEmeriti = <String>[];

  final promotedToCommitter = <String>[];
  final reinstatedUsers = <String>[];
  final onboardedNewJoiners = <String>[];
  final transitionedToEmeritus = <String>[];

  // 1. Evaluate current Committers
  for (final username in roster.committers) {
    final lower = username.toLowerCase();

    // If `--finalize` is re-run on a PR branch where `--prepare` already moved
    // a candidate to Committers, check if they were subsequently excluded.
    if (excludedUsers.contains(lower)) {
      final priorStatus = reportState.promotedInitialStatusLower[lower];
      if (priorStatus == 'Reviewer') {
        updatedReviewers.add(username);
        continue;
      } else if (priorStatus == 'Dasher Emeritus' ||
          priorStatus == 'Org Member') {
        updatedEmeriti.add(username);
        continue;
      } else if (priorStatus == 'External Contributor') {
        continue;
      }
    }

    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;

    if (total >= 10 || retainedUsers.contains(lower)) {
      updatedCommitters.add(username);
    } else {
      updatedEmeriti.add(username);
      transitionedToEmeritus.add('$username (from Committer)');
    }
  }

  // 2. Evaluate current Reviewers
  final now = DateTime.now().toUtc();
  for (final r in roster.reviewers) {
    final username = r.username;
    final lower = username.toLowerCase();

    if (excludedUsers.contains(lower)) {
      final priorStatus = reportState.promotedInitialStatusLower[lower];
      if (priorStatus == 'Dasher Emeritus' || priorStatus == 'Org Member') {
        updatedEmeriti.add(username);
        continue;
      } else if (priorStatus == 'External Contributor') {
        continue;
      }
    }

    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;

    if (total >= 30 && prs >= 10 && !excludedUsers.contains(lower)) {
      updatedCommitters.add(username);
      promotedToCommitter.add(username);
    } else if (total >= 10 ||
        retainedUsers.contains(lower) ||
        _isGraceDateActive(r.graceUntil, now)) {
      updatedReviewers.add(username);
    } else {
      updatedEmeriti.add(username);
      transitionedToEmeritus.add('$username (from Reviewer)');
    }
  }

  // 3. Evaluate unassigned live Org Members
  for (final username in roster.unassignedOrgMembers) {
    final lower = username.toLowerCase();

    if (retainedUsers.contains(lower)) {
      final priorRole = reportState.gracePeriodRolesLower[lower];
      if (priorRole == 'Committer') {
        updatedCommitters.add(username);
      } else {
        updatedReviewers.add(username);
      }
      continue;
    }

    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;

    if (total >= 30 && prs >= 10 && !excludedUsers.contains(lower)) {
      updatedCommitters.add(username);
      promotedToCommitter.add(username);
    } else if (total >= 10 && !excludedUsers.contains(lower)) {
      updatedReviewers.add(username);
      reinstatedUsers.add('$username (to Reviewer)');
    } else {
      updatedEmeriti.add(username);
      transitionedToEmeritus.add('$username (from Org Member)');
    }
  }

  // 4. Evaluate external Dasher Emeriti for reinstatement
  for (final username in roster.externalEmeriti) {
    final lower = username.toLowerCase();

    if (retainedUsers.contains(lower)) {
      final priorRole = reportState.gracePeriodRolesLower[lower];
      if (priorRole == 'Committer') {
        updatedCommitters.add(username);
      } else {
        updatedReviewers.add(username);
      }
      continue;
    }

    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;

    if (total >= 30 && prs >= 10 && !excludedUsers.contains(lower)) {
      updatedCommitters.add(username);
      reinstatedUsers.add('$username (to Committer)');
    } else if (total >= 10 && !excludedUsers.contains(lower)) {
      updatedReviewers.add(username);
      reinstatedUsers.add('$username (to Reviewer)');
    } else {
      updatedEmeriti.add(username);
    }
  }

  // 5. Onboard accepted external new joiners
  final rawExternal = _discoverExternalCandidates(roster, summary);
  for (final username in rawExternal) {
    final lower = username.toLowerCase();
    if (excludedUsers.contains(lower)) continue;
    final stats = summary[username] as Map<String, dynamic>?;
    final total = stats?['total'] as int? ?? 0;
    final prs = stats?['merged_prs'] as int? ?? 0;
    if (total >= 30 && prs >= 10) {
      updatedCommitters.add(username);
      onboardedNewJoiners.add('$username (to Committer)');
    } else if (total >= 10) {
      updatedReviewers.add(username);
      onboardedNewJoiners.add('$username (to Reviewer)');
    }
  }

  updatedCommitters.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  updatedReviewers.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  updatedEmeriti.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  print('Audit Update Summary:');
  print(
      '  • Promoted to Committer (${promotedToCommitter.length}): ${promotedToCommitter.isEmpty ? "none" : promotedToCommitter.join(", ")}');
  print(
      '  • Reinstated / enrolled from Org or Emeritus (${reinstatedUsers.length}): ${reinstatedUsers.isEmpty ? "none" : reinstatedUsers.join(", ")}');
  print(
      '  • Onboarded new joiners (${onboardedNewJoiners.length}): ${onboardedNewJoiners.isEmpty ? "none" : onboardedNewJoiners.join(", ")}');
  print(
      '  • Transitioned to Dasher Emeritus (${transitionedToEmeritus.length}): ${transitionedToEmeritus.isEmpty ? "none" : transitionedToEmeritus.length}');

  if (isDryRun) {
    print('Dry run complete. Exiting without modifying files.');
    return;
  }

  if (existingCommunityReportFile != null &&
      existingCommunityReportFile.existsSync()) {
    final updatedReport = _updateReportOnFinalize(
      existingCommunityReportFile.readAsStringSync(),
      summary,
      retainedUsers: retainedUsers,
      excludedUsers: excludedUsers,
    );
    existingCommunityReportFile.writeAsStringSync(updatedReport);
    print('Updated ${existingCommunityReportFile.path}.');
  }

  final today = DateTime.now().toUtc().toIso8601String().split('T').first;
  final updatedRoster = ContributorsRoster(
    maintainers: MaintainersRoster(
      googlers: [
        for (final g in roster.googlers)
          ContributorEntry(
            username: g,
            discord: getDiscord(g),
            role: 'maintainer',
          ),
      ],
      partners: [
        for (final p in roster.partners)
          ContributorEntry(
            username: p.username,
            team: p.team,
            discord: getDiscord(p.username),
            role: 'maintainer',
          ),
      ],
    ),
    committers: [
      for (final c in updatedCommitters)
        ContributorEntry(
          username: c,
          discord: getDiscord(c),
          role: 'committer',
        ),
    ],
    reviewers: [
      for (final r in updatedReviewers)
        ContributorEntry(
          username: r,
          discord: getDiscord(r),
          graceUntil: graceUntilByUserLower[r.toLowerCase()],
          role: 'reviewer',
        ),
    ],
    dashEmeritus: [
      for (final e in updatedEmeriti)
        ContributorEntry(
          username: e,
          discord: getDiscord(e),
          role: 'emeritus',
        ),
    ],
  );

  contributorsFile
      .writeAsStringSync(updatedRoster.toYamlString(lastUpdated: today));
  print('Applied verified role updates to ${contributorsFile.path}.');

  if (contributorsFile.path == 'data/contributors.yaml') {
    final result =
        Process.runSync('dart', ['run', 'tool/generate_roster.dart']);
    if (result.exitCode == 0) {
      stdout.write(result.stdout);
    } else {
      print(
          'Run `dart run tool/generate_roster.dart` to rebuild ROSTER.md and EMERITUS.md (${result.stderr}).');
    }
  } else {
    print(
        'Run `dart run tool/generate_roster.dart` to rebuild ROSTER.md and EMERITUS.md.');
  }
}

String _updateReportOnFinalize(
  String reportContent,
  Map<String, dynamic> summary, {
  required Set<String> retainedUsers,
  required Set<String> excludedUsers,
}) {
  final lines = reportContent.split('\n');
  final newRetentionRows = <String>[];
  final filteredLines = <String>[];
  var section = '';

  for (final line in lines) {
    if (line.startsWith('## ')) {
      section = line.trim();
      filteredLines.add(line);
      continue;
    }
    if (line.startsWith('| @')) {
      final cells = line.split('|').map((c) => c.trim()).toList();
      if (cells.length >= 5) {
        final rawUser = cells[1].replaceAll('@', '');
        final lower = rawUser.toLowerCase();
        if (section.contains('Recommended promotions')) {
          if (excludedUsers.contains(lower)) {
            if (cells[2] == 'Reviewer') {
              newRetentionRows
                  .add('| @$rawUser | Reviewer | ${cells[4]} | ${cells[5]} |');
            }
            continue;
          }
        } else if (section.contains('30-day grace period')) {
          if (retainedUsers.contains(lower)) {
            final role = cells[2] == 'Committer' ? 'Committer' : 'Reviewer';
            final stats = summary[rawUser] as Map<String, dynamic>?;
            final prs = stats?['merged_prs'] as int? ?? 0;
            final total = cells[3];
            newRetentionRows.add('| @$rawUser | $role | $prs | $total |');
            continue;
          } else {
            filteredLines.add(line.replaceFirst(
                '| In grace period |', '| Moved to Emeritus |'));
            continue;
          }
        }
      }
    }
    filteredLines.add(line);
  }

  if (newRetentionRows.isEmpty) {
    return filteredLines.join('\n');
  }

  final resultLines = <String>[];
  var inRetentionTable = false;
  var insertedRetentionRows = false;
  for (var i = 0; i < filteredLines.length; i++) {
    final line = filteredLines[i];
    if (line.startsWith('## Active role retention')) {
      inRetentionTable = true;
    } else if (inRetentionTable && line.startsWith('## ')) {
      if (!insertedRetentionRows) {
        resultLines.addAll(newRetentionRows);
        insertedRetentionRows = true;
      }
      inRetentionTable = false;
    } else if (inRetentionTable &&
        line.trim().isEmpty &&
        i > 0 &&
        filteredLines[i - 1].startsWith('|')) {
      resultLines.addAll(newRetentionRows);
      insertedRetentionRows = true;
      inRetentionTable = false;
    }
    resultLines.add(line);
  }
  if (inRetentionTable && !insertedRetentionRows) {
    resultLines.addAll(newRetentionRows);
  }
  return resultLines.join('\n');
}

void _outputReport(String report, String? outputPath) {
  if (outputPath != null) {
    File(outputPath).writeAsStringSync(report);
    print('Generated report saved to $outputPath');
  } else {
    print(report);
  }
}
