import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../tool/bots.dart';
import '../tool/github.dart';

void main() {
  group('Bot Detection (isBot)', () {
    tearDown(resetRobotTeamCache);

    test('identifies known bots in knownBots set', () {
      expect(isBot('dependabot'), isTrue);
      expect(isBot('dependabot[bot]'), isTrue);
      expect(isBot('fluttergithubbot'), isTrue);
      expect(isBot('flutteractionsbot'), isTrue);
      expect(isBot('google-oss-robot'), isTrue);
      expect(isBot('google-oss-robot[bot]'), isTrue);
      expect(isBot('github-actions'), isTrue);
      expect(isBot('github-actions[bot]'), isTrue);
      expect(isBot('engine-flutter-autoroll'), isTrue);
      expect(isBot('auto-submit'), isTrue);
      expect(isBot('auto-submit[bot]'), isTrue);
      expect(isBot('google-cla'), isTrue);
      expect(isBot('google-cla[bot]'), isTrue);
      expect(isBot('renovate[bot]'), isTrue);
      expect(isBot('DartDevtoolWorkflowBot'), isTrue);
      expect(isBot('reidbaker-agent'), isTrue);
      expect(isBot('gemini-code-assist'), isTrue);
      expect(isBot('gemini-code-assist[bot]'), isTrue);
      expect(isBot('buildbot'), isTrue);
    });

    test('identifies pattern-based bot usernames', () {
      expect(isBot('some-user-bot'), isTrue);
      expect(isBot('some_user_bot'), isTrue);
      expect(isBot('service[bot]'), isTrue);
      expect(isBot('flutter-autoroll'), isTrue);
      expect(isBot('custom-autoroll-service'), isTrue);
    });

    test(
        'identifies human contributors as non-bots (including names ending in bot or containing robot)',
        () {
      expect(isBot('Piinks'), isFalse);
      expect(isBot('parlough'), isFalse);
      expect(isBot('AbdeMohlbi'), isFalse);
      expect(isBot('Hixie'), isFalse);
      expect(isBot('nate-thegrate'), isFalse);
      expect(isBot('Mairramer'), isFalse);
      expect(isBot('ValentinVignal'), isFalse);
      expect(isBot('robert-ancell'), isFalse);
      expect(isBot('csells'), isFalse);
      expect(isBot('talbot'), isFalse);
      expect(isBot('abbot'), isFalse);
      expect(isBot('chabot'), isFalse);
      expect(isBot('BottlePumpkin'), isFalse);
      expect(isBot('saibotma'), isFalse);
      expect(isBot('Abbott-Deng'), isFalse);
      expect(isBot('mr-robot'), isFalse);
      expect(isBot('robotics-fan'), isFalse);
      expect(isBot('irobot'), isFalse);
    });

    test('handles deleted user ghost account separately', () {
      expect(isGhost('ghost'), isTrue);
      expect(isGhost('  GHOST  '), isTrue);
      expect(isGhost('Piinks'), isFalse);
      expect(isBot('ghost'), isFalse);
      expect(isExcludedAccount('ghost'), isTrue);
      expect(isExcludedAccount('dependabot'), isTrue);
      expect(isExcludedAccount('Piinks'), isFalse);
    });

    test('handles whitespace and casing gracefully', () {
      expect(isBot('  DEPENDABOT[BOT]  '), isTrue);
      expect(isBot('FlutterGithubBot'), isTrue);
      expect(isBot('  piinks  '), isFalse);
    });

    test(
        'loadRobotTeams dynamically adds members of @flutter/robots and @flutter/bots to bots',
        () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.path,
          anyOf(
            equals('/orgs/flutter/teams/robots/members'),
            equals('/orgs/flutter/teams/bots/members'),
          ),
        );
        return http.Response(
          jsonEncode([
            {'login': 'dynamic-team-robot-account'}
          ]),
          200,
        );
      });
      final gh = GitHubClient(token: 'test', httpClient: mockClient);
      await loadRobotTeams(gh);
      expect(isBot('dynamic-team-robot-account'), isTrue);
    });

    test('knownBots in tool/bots.dart stays in sync with references/bots.txt',
        () {
      final botsFile =
          File('.agents/skills/quarterly-ladder-analysis/references/bots.txt');
      expect(botsFile.existsSync(), isTrue);
      final fileBots = botsFile
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toSet();
      expect(knownBots, equals(fileBots));
      for (final bot in fileBots) {
        expect(isExcludedAccount(bot), isTrue);
      }
    });
  });
}
