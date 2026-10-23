// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:test/test.dart';

String _generateLicense(String prefix) {
  return '''
${prefix}Copyright 2026 The Flutter Authors.
${prefix}Use of this source code is governed by a BSD-style license that can be
${prefix}found in the LICENSE file.''';
}

const _extensionPrefixes = {
  '.dart': '// ',
  '.js': '// ',
  '.cjs': '// ',
  '.mjs': '// ',
  '.ts': '// ',
  '.java': '// ',
  '.kt': '// ',
  '.swift': '// ',
  '.cc': '// ',
  '.cpp': '// ',
  '.h': '// ',
  '.m': '// ',
  '.gradle': '// ',
  '.sh': '# ',
  '.py': '# ',
  '.ps1': '# ',
  '.gn': '# ',
  '.bat': 'REM ',
};

const _ignoredDirectories = {
  '.git',
  '.dart_tool',
  '.gemini',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
};

/// Returns all code files under [root] that are missing the Flutter license header.
List<String> findFilesMissingLicense(Directory root) {
  final missing = <String>[];
  final pending = <Directory>[root];

  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    final entries = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entries) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name == null) continue;

      if (entity is Directory) {
        if (_ignoredDirectories.contains(name)) continue;
        pending.add(entity);
      } else if (entity is File) {
        final dotIndex = name.lastIndexOf('.');
        if (dotIndex == -1) continue;
        final ext = name.substring(dotIndex);
        final prefix = _extensionPrefixes[ext];
        if (prefix == null) continue;

        final contents = entity.readAsStringSync().replaceAll('\r\n', '\n');
        if (contents.isEmpty) continue;

        final expectedHeader = '${_generateLicense(prefix)}\n\n';
        final pattern =
            RegExp('^(?:#![^\n]*\n)?${RegExp.escape(expectedHeader)}');
        if (!pattern.hasMatch(contents)) {
          missing.add(entity.path);
        }
      }
    }
  }

  return missing..sort();
}

void main() {
  group('License Headers', () {
    test('root LICENSE file exists and is non-empty', () {
      final licenseFile = File('LICENSE');
      expect(licenseFile.existsSync(), isTrue);
      expect(licenseFile.readAsStringSync().trim(), isNotEmpty);
    });

    test('all code files in the repository have the Flutter license header',
        () {
      final missing = findFilesMissingLicense(Directory.current);
      expect(
        missing,
        isEmpty,
        reason: 'The following code files are missing the required Flutter '
            'license header (followed by a blank line):\n'
            '  ${missing.join('\n  ')}\n\n'
            'Expected header:\n${_generateLicense('// ')}',
      );
    });

    test(
        'findFilesMissingLicense detects missing headers and accepts valid ones',
        () {
      final tempDir = Directory.systemTemp.createTempSync('license_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      File('${tempDir.path}/valid.dart').writeAsStringSync(
        '${_generateLicense('// ')}\n\nvoid main() {}\n',
      );
      File('${tempDir.path}/valid_script.sh').writeAsStringSync(
        '#!/usr/bin/env bash\n${_generateLicense('# ')}\n\necho "ok"\n',
      );
      File('${tempDir.path}/missing.dart').writeAsStringSync(
        'void main() {}\n',
      );
      File('${tempDir.path}/no_blank_line.dart').writeAsStringSync(
        '${_generateLicense('// ')}\nvoid main() {}\n',
      );
      File('${tempDir.path}/ignored.json').writeAsStringSync('{}\n');

      final missing = findFilesMissingLicense(tempDir)
          .map((p) => p.split('/').last)
          .toList();
      expect(missing, equals(['missing.dart', 'no_blank_line.dart']));
    });
  });
}
