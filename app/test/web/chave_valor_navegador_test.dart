@TestOn('browser')
library;

import 'package:calculadoradarf/app/web/chave_valor_navegador.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void limpar() {
  final chaves = [
    for (var i = 0; i < web.window.localStorage.length; i++)
      web.window.localStorage.key(i)!,
  ];
  for (final c in chaves.where((c) => c.startsWith('darf:'))) {
    web.window.localStorage.removeItem(c);
  }
}

void main() {
  setUp(limpar);
  tearDown(limpar);

  test('vai ao window.localStorage', () {
    final kv = chaveValorDoNavegador();
    expect(kv, isNotNull);
    kv!.definir('darf:a', '1');
    expect(web.window.localStorage.getItem('darf:a'), '1');
    expect(kv.obter('darf:a'), '1');
    expect(kv.chaves(), contains('darf:a'));
    kv.remover('darf:a');
    expect(kv.obter('darf:a'), isNull);
    expect(kv.chaves(), isNot(contains('darf:a')));
  });
}
