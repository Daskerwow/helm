import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Архитектурный инвариант: ядро (lib/helm.dart + lib/src/core/**) не
/// должно знать о существовании Flutter или любого другого UI-фреймворка.
/// Этот тест сканирует исходники ядра и падает, если туда просочился
/// `import 'package:flutter/...'`.
void main() {
  test('ядро не импортирует package:flutter', () {
    final coreFiles = [
      File('lib/helm.dart'),
      ...Directory('lib/src/core')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];

    final offenders = <String>[];
    for (final file in coreFiles) {
      final content = file.readAsStringSync();
      if (content.contains("package:flutter/")) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Store должен быть чистым Dart. Нашёл импорт Flutter в: $offenders',
    );
  });
}
