@TestOn('browser')
library;

import 'package:calculadoradarf/integracoes/google/guarda_nonce.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  setUp(() => web.window.sessionStorage.removeItem('darf:nonce'));
  tearDown(() => web.window.sessionStorage.removeItem('darf:nonce'));

  test('guarda no sessionStorage; consumir devolve e apaga', () {
    guardaNonceDoNavegador().guardar('abc');
    expect(web.window.sessionStorage.getItem('darf:nonce'), 'abc');
    expect(guardaNonceDoNavegador().consumir(), 'abc');
    expect(web.window.sessionStorage.getItem('darf:nonce'), isNull);
    expect(guardaNonceDoNavegador().consumir(), isNull);
  });
}
