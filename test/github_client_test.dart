// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../tool/github.dart';

void main() {
  group('GitHubClient', () {
    test(
        'sends required headers including authorization when token is provided',
        () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode([]), 200);
      });

      final client =
          GitHubClient(token: 'secret_test_token', httpClient: mockClient);
      await client.getOrgMembers('flutter');

      expect(capturedRequest.headers['Authorization'],
          equals('Bearer secret_test_token'));
      expect(capturedRequest.headers['Accept'],
          equals('application/vnd.github+json'));
      expect(capturedRequest.headers['User-Agent'],
          equals('flutter-contributor-ladder-tool'));
      expect(capturedRequest.headers['X-GitHub-Api-Version'],
          equals('2022-11-28'));
    });

    test('getOrgMembers paginates through all pages until last page', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        final page = request.url.queryParameters['page'];
        if (page == '1') {
          final list = List.generate(100, (i) => {'login': 'user_$i'});
          return http.Response(jsonEncode(list), 200);
        } else if (page == '2') {
          final list = [
            {'login': 'user_100'},
            {'login': 'user_101'}
          ];
          return http.Response(jsonEncode(list), 200);
        }
        return http.Response(jsonEncode([]), 200);
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final members = await client.getOrgMembers('flutter');

      expect(members.length, equals(102));
      expect(members.contains('user_0'), isTrue);
      expect(members.contains('user_101'), isTrue);
      expect(requestCount, equals(2));
    });

    test(
        'getTeamMembers returns empty set on 404 (team does not exist or private)',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "Not Found"}', 404);
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final members =
          await client.getTeamMembers('flutter', 'non_existent_team');

      expect(members, isEmpty);
    });

    test('getTeamMembers returns member logins on 200', () async {
      final mockClient = MockClient((request) async {
        final list = [
          {'login': 'alice'},
          {'login': 'bob'}
        ];
        return http.Response(jsonEncode(list), 200);
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final members = await client.getTeamMembers('flutter', 'robots');

      expect(members, equals({'alice', 'bob'}));
    });

    test('queryGraphQL returns data map on successful query', () async {
      final mockClient = MockClient((request) async {
        final responseBody = {
          'data': {
            'search': {'issueCount': 42}
          }
        };
        return http.Response(jsonEncode(responseBody), 200);
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final data = await client.queryGraphQL('query { search { issueCount } }');

      expect(data['search']['issueCount'], equals(42));
    });

    test('queryGraphQL throws exception when response contains errors',
        () async {
      final mockClient = MockClient((request) async {
        final responseBody = {
          'errors': [
            {'message': 'Field not found'}
          ]
        };
        return http.Response(jsonEncode(responseBody), 200);
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      expect(
        () async => await client.queryGraphQL('query { invalid }'),
        throwsA(isA<Exception>()),
      );
    });

    test('retries on 429 rate limit response and succeeds after retry',
        () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('{"message": "rate limit exceeded"}', 429,
              headers: {'retry-after': '0'});
        }
        return http.Response(
            jsonEncode([
              {'login': 'recovered_user'}
            ]),
            200);
      });

      final client = GitHubClient(
        token: 'test',
        httpClient: mockClient,
        delay: (_) async {},
      );
      final members = await client.getTeamMembers('flutter', 'robots');

      expect(callCount, equals(2));
      expect(members, equals({'recovered_user'}));
    });

    test('throws exception when rate limit retries are exhausted', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"message": "rate limit exceeded"}', 429,
            headers: {'retry-after': '0'});
      });

      final client = GitHubClient(
        token: 'test',
        httpClient: mockClient,
        delay: (_) async {},
      );
      expect(
        () async => await client.getTeamMembers('flutter', 'robots'),
        throwsA(isA<Exception>()),
      );
    });

    test('retries on 502 server error and succeeds on subsequent attempt',
        () async {
      var callCount = 0;
      final delays = <Duration>[];
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Bad Gateway', 502);
        }
        return http.Response(
            jsonEncode([
              {'login': 'alice'}
            ]),
            200);
      });

      final client = GitHubClient(
        token: 'test',
        httpClient: mockClient,
        delay: (d) async => delays.add(d),
      );
      final members = await client.getTeamMembers('flutter', 'robots');
      expect(callCount, equals(2));
      expect(delays, equals([const Duration(seconds: 2)]));
      expect(members, equals({'alice'}));
    });

    test('getChildTeams fetches child team slugs and handles 404', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('non_existent')) {
          return http.Response('Not Found', 404);
        }
        return http.Response(
          jsonEncode([
            {'slug': 'canonical'},
            {'slug': 'tcs'},
          ]),
          200,
        );
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final children = await client.getChildTeams('flutter', 'partners');
      expect(children, equals(['canonical', 'tcs']));

      final empty = await client.getChildTeams('flutter', 'non_existent');
      expect(empty, isEmpty);
    });

    test('getUserActivity queries GraphQL and returns summed stats', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'authored': {'issueCount': 12},
              'issues': {'issueCount': 5},
              'reviewed': {'issueCount': 8},
            }
          }),
          200,
        );
      });

      final client = GitHubClient(token: 'test', httpClient: mockClient);
      final stats = await client.getUserActivity(
        'octocat',
        since: DateTime.utc(2025, 8, 1),
        until: DateTime.utc(2026, 8, 1),
      );

      expect(
          stats,
          equals({
            'merged_prs': 12,
            'issues': 5,
            'reviews': 8,
            'total': 25,
          }));
    });

    test(
        'getBatchUserActivity returns batched results and falls back to sequential on error',
        () async {
      final emptyClient = GitHubClient(
        token: 'test',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        await emptyClient.getBatchUserActivity([],
            since: DateTime.utc(2025, 1, 1), until: DateTime.utc(2026, 1, 1)),
        isEmpty,
      );

      // Test happy path batch query
      final batchMock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'u_0_pr': {'issueCount': 10},
              'u_0_issues': {'issueCount': 2},
              'u_0_rev': {'issueCount': 3},
              'u_1_pr': {'issueCount': 1},
              'u_1_issues': {'issueCount': 4},
              'u_1_rev': {'issueCount': 0},
            }
          }),
          200,
        );
      });
      final batchClient = GitHubClient(token: 'test', httpClient: batchMock);
      final batchStats = await batchClient.getBatchUserActivity(
        ['alice', 'bob'],
        since: DateTime.utc(2025, 1, 1),
        until: DateTime.utc(2026, 1, 1),
      );
      expect(batchStats['alice']?['total'], equals(15));
      expect(batchStats['bob']?['total'], equals(5));

      // Test fallback to sequential when batch query returns GraphQL error
      var callNum = 0;
      final fallbackMock = MockClient((request) async {
        callNum++;
        if (callNum == 1) {
          return http.Response(
            jsonEncode({
              'errors': [
                {'message': 'Batch query error'}
              ]
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'authored': {'issueCount': 3},
              'issues': {'issueCount': 2},
              'reviewed': {'issueCount': 1},
            }
          }),
          200,
        );
      });
      final fallbackClient =
          GitHubClient(token: 'test', httpClient: fallbackMock);
      final fallbackStats = await fallbackClient.getBatchUserActivity(
        ['alice'],
        since: DateTime.utc(2025, 1, 1),
        until: DateTime.utc(2026, 1, 1),
      );
      expect(fallbackStats['alice']?['total'], equals(6));
    });
  });

  group('Username Validation & Query Injection Protection', () {
    test('validates conformant GitHub usernames', () {
      expect(isValidGitHubUsername('Piinks'), isTrue);
      expect(isValidGitHubUsername('loic-sharma'), isTrue);
      expect(isValidGitHubUsername('fluttergithubbot'), isTrue);
      expect(isValidGitHubUsername('dependabot[bot]'), isTrue);
      expect(isValidGitHubUsername('user123'), isTrue);
      expect(isValidGitHubUsername('a-b-c'), isTrue);
    });

    test('rejects malicious or invalid username strings', () {
      expect(isValidGitHubUsername('user" { search { } }'), isFalse);
      expect(isValidGitHubUsername('user\nother'), isFalse);
      expect(isValidGitHubUsername('user with spaces'), isFalse);
      expect(isValidGitHubUsername('-startinghyphen'), isFalse);
      expect(isValidGitHubUsername('endinghyphen-'), isFalse);
      expect(isValidGitHubUsername('user--consecutive'), isFalse);
      expect(isValidGitHubUsername(''), isFalse);
    });

    test('getUserActivity throws ArgumentError on injection attempt', () async {
      final client = GitHubClient(token: 'test');
      expect(
        () async => await client.getUserActivity('bad"user',
            since: DateTime.utc(2026, 1, 1), until: DateTime.utc(2026, 1, 2)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getBatchUserActivity throws ArgumentError on injection attempt',
        () async {
      final client = GitHubClient(token: 'test');
      expect(
        () async => await client.getBatchUserActivity(['validUser', 'bad"user'],
            since: DateTime.utc(2026, 1, 1), until: DateTime.utc(2026, 1, 2)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
