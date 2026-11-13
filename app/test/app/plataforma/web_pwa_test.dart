import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifesto da PWA', () {
    final m = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(m['name'], 'Calculadora DARF');
    expect(m['short_name'], 'Calculadora DARF');
    expect(m['display'], 'standalone');
    expect(m['start_url'], './');
    expect(m['background_color'], '#0D1117');
    expect(m['theme_color'], '#0D1117');
    for (final i in (m['icons'] as List).cast<Map<String, dynamic>>()) {
      expect(
        File('web/${i['src']}').existsSync(),
        isTrue,
        reason: '${i['src']}',
      );
    }
  });
  test('index.html com viewport-fit, iOS e sem textos do modelo', () {
    final h = File('web/index.html').readAsStringSync();
    for (final s in [
      'lang="pt-BR"',
      'viewport-fit=cover',
      'rel="apple-touch-icon" href="icons/apple-touch-icon.png"',
      'apple-mobile-web-app-capable',
      'apple-mobile-web-app-title" content="Calculadora DARF"',
      '<title>Calculadora DARF</title>',
      'name="theme-color" content="#0D1117"',
    ]) {
      expect(h, contains(s));
    }
    expect(h, isNot(contains('A new Flutter project')));
  });
}
