import 'github.dart';

/// Dynamic cache for members of the `@flutter/robots` GitHub team.
final Set<String> _robotTeamMembers = {};

/// Fetches and caches members of the `@flutter/robots` GitHub team.
Future<Set<String>> loadRobotsTeam(GitHubClient client) async {
  try {
    final members = await client.getTeamMembers('flutter', 'robots');
    _robotTeamMembers.addAll(members.map((m) => m.toLowerCase()));
  } catch (e) {
    // Graceful fallback when running offline or without elevated team-read permissions
    print('Notice: Could not load @flutter/robots team members: $e');
  }
  return _robotTeamMembers;
}

/// Fallback set of known bot and automation accounts across Flutter repositories.
const Set<String> knownBots = {
  'dependabot',
  'dependabot[bot]',
  'fluttergithubbot',
  'google-oss-robot',
  'google-oss-robot[bot]',
  'github-actions',
  'github-actions[bot]',
  'engine-flutter-autoroll',
  'engine-flutter-autoroll[bot]',
  'skia-flutter-autoroll',
  'skia-flutter-autoroll[bot]',
  'flutter-autoroll',
  'flutter-autoroll[bot]',
  'auto-submit[bot]',
  'google-cla[bot]',
  'googlebot',
  'copybara-service',
  'copybara-service[bot]',
  'renovate',
  'renovate[bot]',
  'flutteractionsbot',
  'flutter-website-bot',
  'flutter-intellij-kokoro',
  'fluttercerberus',
  'DartDevtoolWorkflowBot',
  'buildbot',
  'reidbaker-agent',
  'gemini-code-assist',
  'gemini-code-assist[bot]',
};

/// Resets the dynamic robot team members cache (useful for testing).
void resetRobotTeamCache() {
  _robotTeamMembers.clear();
}

/// Returns true if [username] represents GitHub's placeholder for deleted accounts ('ghost').
bool isGhost(String username) {
  return username.toLowerCase().trim() == 'ghost';
}

/// Returns true if [username] is a bot or deleted account that should be excluded from activity tracking.
bool isExcludedAccount(String username) {
  return isGhost(username) || isBot(username);
}

/// Returns true if [username] belongs to `@flutter/robots` or matches a known bot pattern.
bool isBot(String username) {
  final lower = username.toLowerCase().trim();
  if (_robotTeamMembers.contains(lower)) {
    return true;
  }
  if (knownBots.contains(lower) || knownBots.contains(username)) {
    return true;
  }
  if (lower.endsWith('[bot]') ||
      lower.endsWith('-bot') ||
      lower.endsWith('_bot') ||
      lower.contains('autoroll')) {
    return true;
  }
  return false;
}
