import 'dart:convert';
import 'dart:io';

/// Tool that inspects open quarterly review issues weekly, posts a weekly
/// countdown update while < 30 days have elapsed, and pings the assignee once
/// the 30-day review period has concluded.
void main(List<String> args) async {
  final isDryRun =
      Platform.environment['DRY_RUN'] == 'true' || args.contains('--dry-run');
  print(
      'Checking open quarterly review issues for 30-day grace period status...');
  if (isDryRun) {
    print('Running in DRY-RUN mode. No comments will be posted.');
  }

  final issues = await getOpenQuarterlyIssues();
  if (issues.isEmpty) {
    print('No open quarterly review issues found.');
    return;
  }

  final now = DateTime.now().toUtc();
  print('Found ${issues.length} open quarterly review issue(s).');

  for (final issue in issues) {
    final number = issue['number'] as int;
    final title = issue['title'] as String;
    final createdAtStr = issue['createdAt'] as String;
    final createdAt = DateTime.parse(createdAtStr).toUtc();
    final eval = evaluateGracePeriodIssue(issue, now: now);

    if (eval.alreadyConcluded) {
      print(
          'Issue #$number ("$title"): Grace period reminder already posted. Skipping.');
      continue;
    }

    final daysElapsed = eval.daysElapsed;
    print(
        'Issue #$number ("$title"): $daysElapsed days elapsed since creation ($createdAtStr).');

    if (eval.shouldRemind) {
      print(
          '>>> Grace period has elapsed (>= 30 days) for Issue #$number! Pinging assignee(s): ${eval.assignees.join(', ')}');
      final commentBody = buildGracePeriodConclusionComment(
        title: title,
        daysElapsed: daysElapsed,
        assignees: eval.assignees,
      );

      if (!isDryRun) {
        await ensureGracePeriodConcludedLabel();
        await postIssueComment(number, commentBody);
        await addIssueLabel(number, 'grace-period-concluded');
        print(
            'Successfully posted grace period conclusion reminder and added label to Issue #$number.');
      } else {
        print(
            'Dry run: Would have posted the following conclusion comment to #$number:\n');
        print(commentBody);
      }
    } else if (eval.shouldPostWeeklyUpdate) {
      print(
          'Issue #$number: ${eval.daysRemaining} day(s) remaining in the 30-day grace period. Posting weekly status update...');
      final weeklyComment = buildWeeklyGracePeriodUpdateComment(
        title: title,
        daysElapsed: daysElapsed,
        createdAt: createdAt,
      );

      if (!isDryRun) {
        await postIssueComment(number, weeklyComment);
        print('Successfully posted weekly status update to Issue #$number.');
      } else {
        print(
            'Dry run: Would have posted the following weekly status update to #$number:\n');
        print(weeklyComment);
      }
    }
  }
}

/// Extracts the assignee GitHub usernames from an issue JSON map, falling back
/// to the author login or `'Piinks'` if no assignees are set.
List<String> extractAssignees(Map<String, dynamic> item) {
  final assigneesList = (item['assignees'] as List? ?? [])
      .map((a) => (a as Map<String, dynamic>)['login'] as String?)
      .whereType<String>()
      .where((login) => login.trim().isNotEmpty)
      .toList();
  if (assigneesList.isNotEmpty) {
    return assigneesList;
  }

  final authorLogin =
      (item['author'] as Map<String, dynamic>?)?['login'] as String?;
  if (authorLogin != null && authorLogin.trim().isNotEmpty) {
    return [authorLogin.trim()];
  }

  return const ['Piinks'];
}

/// Evaluates whether an open quarterly review issue needs a weekly update or a
/// 30-day grace period conclusion reminder.
({
  bool shouldRemind,
  bool shouldPostWeeklyUpdate,
  int daysElapsed,
  int daysRemaining,
  bool alreadyConcluded,
  List<String> assignees,
}) evaluateGracePeriodIssue(Map<String, dynamic> issue,
    {required DateTime now}) {
  final createdAtStr = issue['createdAt'] as String;
  final createdAt = DateTime.parse(createdAtStr).toUtc();
  final labels =
      (issue['labels'] as List? ?? []).map((l) => l['name'] as String).toSet();

  final alreadyConcluded = labels.contains('grace-period-concluded');
  final daysElapsed = now.toUtc().difference(createdAt).inDays;
  final daysRemaining = (30 - daysElapsed).clamp(0, 30);
  final assignees = extractAssignees(issue);

  return (
    shouldRemind: !alreadyConcluded && daysElapsed >= 30,
    shouldPostWeeklyUpdate: !alreadyConcluded && daysElapsed < 30,
    daysElapsed: daysElapsed,
    daysRemaining: daysRemaining,
    alreadyConcluded: alreadyConcluded,
    assignees: assignees,
  );
}

/// Builds the weekly status update comment posted on open quarterly review
/// issues while the 30-day review period is in progress.
String buildWeeklyGracePeriodUpdateComment({
  required String title,
  required int daysElapsed,
  required DateTime createdAt,
}) {
  final daysRemaining = (30 - daysElapsed).clamp(0, 30);
  final createdDate = createdAt.toUtc().toIso8601String().split('T').first;
  final targetEndDate = createdAt
      .toUtc()
      .add(const Duration(days: 30))
      .toIso8601String()
      .split('T')
      .first;

  final buffer = StringBuffer();
  buffer.writeln('## Weekly review period status update');
  buffer.writeln();
  buffer.writeln(
      '**$title** is currently in the 30-day review and grace period:');
  buffer.writeln('- **Elapsed:** $daysElapsed day(s) (opened $createdDate)');
  buffer.writeln(
      '- **Remaining:** $daysRemaining day(s) until the 30-day review window concludes on **$targetEndDate**');
  buffer.writeln();
  buffer.writeln(
      'If you were tagged above and have not yet replied, please comment on this thread before **$targetEndDate** to accept your invitation, share your Discord username for team member role provisioning, or share qualitative contributions (issue triage, reproductions, [RFCs](https://github.com/flutter/rfc), design docs, or mentoring).');
  return buffer.toString();
}

/// Builds the markdown comment to post when the 30-day grace period concludes,
/// pinging the assignee(s).
String buildGracePeriodConclusionComment({
  required String title,
  required int daysElapsed,
  List<String> assignees = const ['Piinks'],
}) {
  final effectiveAssignees = assignees.isEmpty ? const ['Piinks'] : assignees;
  final mentions = effectiveAssignees
      .map((a) => a.trim().startsWith('@') ? a.trim() : '@${a.trim()}')
      .join(', ');

  final buffer = StringBuffer();
  buffer.writeln('## 30-day review period concluded');
  buffer.writeln();
  buffer.writeln(
      'cc $mentions — The 30-day review and grace period for **$title** has concluded ($daysElapsed days since opening).');
  buffer.writeln();
  buffer.writeln('### Next steps:');
  buffer.writeln(
      '1. Review qualitative contributions, appeals, and Discord usernames shared by new joiners/promoted members in this thread.');
  buffer.writeln(
      '2. On the open quarterly review PR branch, run `dart run tool/quarterly_audit.dart --finalize --retain ... --exclude ... --discord user=handle` to update `data/contributors.yaml`, [ROSTER.md](ROSTER.md), and [EMERITUS.md](EMERITUS.md), then merge the PR.');
  buffer.writeln(
      '3. Update GitHub teams (`@flutter/reviewers`, `@flutter/committers`, and `@flutter/maintainers` as child teams of `@flutter/flutter-hackers`, along with `@flutter/partners` child teams), grant the Discord team member role to newly added ladder members, and remove members transitioning to Dasher Emeritus from the GitHub organization.');
  buffer.writeln('4. Close this issue once updates land.');
  return buffer.toString();
}

/// Queries GitHub for open issues labeled 'quarterly-review'.
Future<List<Map<String, dynamic>>> getOpenQuarterlyIssues() async {
  try {
    final result = await Process.run('gh', [
      'issue',
      'list',
      '--state',
      'open',
      '--label',
      'quarterly-review',
      '--json',
      'number,title,createdAt,labels,assignees,author',
    ]);

    if (result.exitCode != 0) {
      print(
          'Notice: gh issue list exited with code ${result.exitCode}: ${result.stderr}');
      return [];
    }

    final decoded = jsonDecode(result.stdout as String) as List;
    return decoded.cast<Map<String, dynamic>>();
  } catch (e) {
    print('Notice: Could not query GitHub issues: $e');
    return [];
  }
}

/// Ensures the `grace-period-concluded` label exists in the repository.
Future<void> ensureGracePeriodConcludedLabel() async {
  await Process.run('gh', [
    'label',
    'create',
    'grace-period-concluded',
    '--description',
    '30-day review period elapsed',
    '--color',
    'FBCA04',
    '--force',
  ]);
}

/// Posts a comment to a GitHub issue.
Future<void> postIssueComment(int issueNumber, String body) async {
  final result = await Process.run('gh', [
    'issue',
    'comment',
    '$issueNumber',
    '--body',
    body,
  ]);
  if (result.exitCode != 0) {
    print('Failed to post comment to #$issueNumber: ${result.stderr}');
  }
}

/// Adds a label to a GitHub issue.
Future<void> addIssueLabel(int issueNumber, String label) async {
  final result = await Process.run('gh', [
    'issue',
    'edit',
    '$issueNumber',
    '--add-label',
    label,
  ]);
  if (result.exitCode != 0) {
    print('Failed to add label "$label" to #$issueNumber: ${result.stderr}');
  }
}
