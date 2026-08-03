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
  });
}
