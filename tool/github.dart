import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Client for communicating with GitHub REST and GraphQL APIs across the Flutter organization.
class GitHubClient {
  GitHubClient({String? token, http.Client? httpClient})
      : token = token ?? _resolveToken(),
        _httpClient = httpClient ?? http.Client();

  final String? token;
  final http.Client _httpClient;

  static String? _resolveToken() {
    final envToken = Platform.environment['ORG_READ_TOKEN'] ??
        Platform.environment['GITHUB_TOKEN'] ??
        Platform.environment['GH_TOKEN'];
    if (envToken != null && envToken.isNotEmpty) {
      return envToken;
    }
    // Fall back to GitHub CLI token if installed.
    try {
      final result = Process.runSync('gh', ['auth', 'token']);
      if (result.exitCode == 0) {
        final t = (result.stdout as String).trim();
        if (t.isNotEmpty) return t;
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> get _headers {
    final map = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'flutter-contributor-ladder-tool',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token != null && token!.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  /// Fetches all members of a GitHub organization across all pages.
  Future<Set<String>> getOrgMembers(String org) async {
    final members = <String>{};
    var page = 1;
    while (true) {
      final uri = Uri.parse(
          'https://api.github.com/orgs/$org/members?per_page=100&page=$page');
      final response = await _httpClient.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception(
            'Failed to fetch org members for $org (HTTP ${response.statusCode}): ${response.body}');
      }
      final list = jsonDecode(response.body) as List;
      if (list.isEmpty) break;
      for (final item in list) {
        final login = (item as Map<String, dynamic>)['login'] as String;
        members.add(login);
      }
      if (list.length < 100) break;
      page++;
    }
    return members;
  }

  /// Fetches all members of a specific GitHub team in an organization.
  Future<Set<String>> getTeamMembers(String org, String teamSlug) async {
    final members = <String>{};
    var page = 1;
    while (true) {
      final uri = Uri.parse(
          'https://api.github.com/orgs/$org/teams/$teamSlug/members?per_page=100&page=$page');
      final response = await _httpClient.get(uri, headers: _headers);
      if (response.statusCode == 404) {
        // Team may not exist yet or not visible with current token.
        return members;
      }
      if (response.statusCode != 200) {
        throw Exception(
            'Failed to fetch team members for $org/$teamSlug (HTTP ${response.statusCode}): ${response.body}');
      }
      final list = jsonDecode(response.body) as List;
      if (list.isEmpty) break;
      for (final item in list) {
        final login = (item as Map<String, dynamic>)['login'] as String;
        members.add(login);
      }
      if (list.length < 100) break;
      page++;
    }
    return members;
  }

  /// Fetches child teams of a specific GitHub team in an organization.
  Future<List<String>> getChildTeams(String org, String teamSlug) async {
    final teams = <String>[];
    var page = 1;
    while (true) {
      final uri = Uri.parse(
          'https://api.github.com/orgs/$org/teams/$teamSlug/teams?per_page=100&page=$page');
      final response = await _httpClient.get(uri, headers: _headers);
      if (response.statusCode == 404 || response.statusCode != 200) break;
      final list = jsonDecode(response.body) as List;
      if (list.isEmpty) break;
      for (final item in list) {
        final slug = item['slug'] as String;
        teams.add(slug);
      }
      if (list.length < 100) break;
      page++;
    }
    return teams;
  }

  /// Executes a GraphQL query against the GitHub API.
  Future<Map<String, dynamic>> queryGraphQL(String query,
      {Map<String, dynamic>? variables}) async {
    final uri = Uri.parse('https://api.github.com/graphql');
    final body = jsonEncode({
      'query': query,
      if (variables != null) 'variables': variables,
    });
    final response = await _httpClient.post(uri, headers: _headers, body: body);
    if (response.statusCode != 200) {
      throw Exception(
          'GraphQL query failed (HTTP ${response.statusCode}): ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('errors')) {
      final errors = json['errors'];
      throw Exception('GraphQL returned errors: $errors');
    }
    return json['data'] as Map<String, dynamic>;
  }

  /// Fetches contribution statistics for a specific user over the given date range.
  Future<Map<String, int>> getUserActivity(String username,
      {required DateTime since, required DateTime until}) async {
    final sinceIso = since.toUtc().toIso8601String().split('T').first;
    final untilIso = until.toUtc().toIso8601String().split('T').first;

    // Search query for merged PRs authored by user
    final authoredQuery =
        'org:flutter is:pr is:merged author:$username merged:$sinceIso..$untilIso';
    // Search query for issues authored by user
    final issuesQuery =
        'org:flutter is:issue author:$username created:$sinceIso..$untilIso';
    // Search query for PRs reviewed by user
    final reviewedQuery =
        'org:flutter is:pr is:merged reviewed-by:$username -author:$username merged:$sinceIso..$untilIso';

    final gql = '''
query(\$authored: String!, \$issues: String!, \$reviewed: String!) {
  authored: search(query: \$authored, type: ISSUE, first: 1) {
    issueCount
  }
  issues: search(query: \$issues, type: ISSUE, first: 1) {
    issueCount
  }
  reviewed: search(query: \$reviewed, type: ISSUE, first: 1) {
    issueCount
  }
}
''';

    final data = await queryGraphQL(gql, variables: {
      'authored': authoredQuery,
      'issues': issuesQuery,
      'reviewed': reviewedQuery,
    });

    final authoredCount = data['authored']?['issueCount'] as int? ?? 0;
    final issuesCount = data['issues']?['issueCount'] as int? ?? 0;
    final reviewedCount = data['reviewed']?['issueCount'] as int? ?? 0;
    return {
      'merged_prs': authoredCount,
      'issues': issuesCount,
      'reviews': reviewedCount,
      'total': authoredCount + issuesCount + reviewedCount,
    };
  }

  /// Fetches contribution statistics for a batch of users in a single GraphQL query.
  Future<Map<String, Map<String, int>>> getBatchUserActivity(
      List<String> usernames,
      {required DateTime since,
      required DateTime until}) async {
    if (usernames.isEmpty) return {};

    final sinceIso = since.toUtc().toIso8601String().split('T').first;
    final untilIso = until.toUtc().toIso8601String().split('T').first;

    final results = <String, Map<String, int>>{};
    final batchSize = 10;

    for (var i = 0; i < usernames.length; i += batchSize) {
      final batch = usernames.skip(i).take(batchSize).toList();
      final gqlBuffer = StringBuffer('query {\n');

      for (var idx = 0; idx < batch.length; idx++) {
        final u = batch[idx];
        final prQuery =
            'org:flutter is:pr is:merged author:$u merged:$sinceIso..$untilIso';
        final issuesQuery =
            'org:flutter is:issue author:$u created:$sinceIso..$untilIso';
        final revQuery =
            'org:flutter is:pr is:merged reviewed-by:$u -author:$u merged:$sinceIso..$untilIso';

        gqlBuffer.writeln(
            '  u_${idx}_pr: search(query: "$prQuery", type: ISSUE, first: 0) { issueCount }');
        gqlBuffer.writeln(
            '  u_${idx}_issues: search(query: "$issuesQuery", type: ISSUE, first: 0) { issueCount }');
        gqlBuffer.writeln(
            '  u_${idx}_rev: search(query: "$revQuery", type: ISSUE, first: 0) { issueCount }');
      }
      gqlBuffer.writeln('}');

      try {
        final data = await queryGraphQL(gqlBuffer.toString());
        for (var idx = 0; idx < batch.length; idx++) {
          final u = batch[idx];
          final prCount = data['u_${idx}_pr']?['issueCount'] as int? ?? 0;
          final issuesCount =
              data['u_${idx}_issues']?['issueCount'] as int? ?? 0;
          final revCount = data['u_${idx}_rev']?['issueCount'] as int? ?? 0;
          results[u] = {
            'merged_prs': prCount,
            'issues': issuesCount,
            'reviews': revCount,
            'total': prCount + issuesCount + revCount,
          };
        }
      } catch (e) {
        print('Warning: GraphQL batch query failed for batch at index $i: $e');
        // Fallback to sequential for this batch if needed
        for (final u in batch) {
          try {
            results[u] = await getUserActivity(u, since: since, until: until);
          } catch (_) {
            results[u] = {
              'merged_prs': 0,
              'issues': 0,
              'reviews': 0,
              'total': 0
            };
          }
        }
      }
    }

    return results;
  }

  void close() {
    _httpClient.close();
  }
}
