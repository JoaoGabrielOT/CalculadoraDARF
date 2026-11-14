@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:calculadoradarf/app/plataforma/plataforma_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a trava de aba única só é dada uma vez por página', () async {
    expect(await PlataformaWeb().travarAbaUnica(), isTrue);
    expect(await PlataformaWeb().travarAbaUnica(), isFalse);
  });

  test('a mesma plataforma, de novo, continua com a trava', () async {
    final p = PlataformaWeb();
    final primeira = await p.travarAbaUnica();
    expect(await p.travarAbaUnica(), primeira);
  });

  test('sem a Notification API as notificações não fazem nada', () async {
    final original = globalContext['Notification'];
    globalContext.delete('Notification'.toJS);
    addTearDown(() => globalContext['Notification'] = original);
    final p = PlataformaWeb();
    await p.iniciarNotificacoes((_) {});
    await p.notificar(1, 'Título', 'Corpo', 'https://x.com');
    expect(await p.pedirPermissaoNotificacoes(), isFalse);
  });

  test('web é true e windows é false', () {
    final p = PlataformaWeb();
    expect(p.web, isTrue);
    expect(p.windows, isFalse);
  });
}
