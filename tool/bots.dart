import 'github.dart';

/// Dynamic cache for members of the `@flutter/robots` GitHub team.
final Set<String> _robotTeamMembers = {};

/// Fetches and caches members of the `@flutter/robots` GitHub team.
Future<Set<String>> loadRobotsTeam(GitHubClient client) async {
  try {
    final members = await client.getTeamMembers('flutter', 'robots');
    _robotTeamMembers.addAll(members.map((m) => m.toLowerCase()));
  } catch (_) {
    // Graceful fallback when running offline or without elevated team-read permissions
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
  'reidbaker-agent',
  'gemini-code-assist',
  'gemini-code-assist[bot]',
};

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
      lower.endsWith('bot') ||
      lower.contains('autoroll') ||
      lower.contains('robot')) {
    return true;
  }
  return false;
}
