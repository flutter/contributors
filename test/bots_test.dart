import 'package:test/test.dart';
import '../tool/bots.dart';

void main() {
  group('Bot Detection (isBot)', () {
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
      expect(isBot('auto-submit[bot]'), isTrue);
      expect(isBot('google-cla[bot]'), isTrue);
      expect(isBot('renovate[bot]'), isTrue);
      expect(isBot('DartDevtoolWorkflowBot'), isTrue);
      expect(isBot('reidbaker-agent'), isTrue);
      expect(isBot('gemini-code-assist'), isTrue);
      expect(isBot('gemini-code-assist[bot]'), isTrue);
      expect(isBot('ghost'), isTrue);
      expect(isBot('buildbot'), isTrue);
    });

    test('identifies pattern-based bot usernames', () {
      expect(isBot('some-user-bot'), isTrue);
      expect(isBot('some_user_bot'), isTrue);
      expect(isBot('service[bot]'), isTrue);
      expect(isBot('flutter-autoroll'), isTrue);
      expect(isBot('custom-robot-account'), isTrue);
    });

    test(
        'identifies human contributors as non-bots (including names ending in bot)',
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
    });

    test('handles whitespace and casing gracefully', () {
      expect(isBot('  DEPENDABOT[BOT]  '), isTrue);
      expect(isBot('FlutterGithubBot'), isTrue);
      expect(isBot('  piinks  '), isFalse);
    });
  });
}
