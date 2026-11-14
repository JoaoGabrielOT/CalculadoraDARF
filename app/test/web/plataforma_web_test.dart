@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:calculadoradarf/app/plataforma/plataforma_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as html;

void main() {
  test('a mesma plataforma, de novo, continua com a trava', () async {
    final p = PlataformaWeb(nomeTrava: 'teste-mesma');
    expect(await p.travarAbaUnica(), isTrue);
    expect(await p.travarAbaUnica(), isTrue);
  });

  test('duas chamadas simultâneas recebem o mesmo resultado', () async {
    final p = PlataformaWeb(nomeTrava: 'teste-simultaneas');
    final a = p.travarAbaUnica();
    final b = p.travarAbaUnica();
    expect(identical(a, b), isTrue);
    expect(await Future.wait([a, b]), [true, true]);
  });

  test('a trava de aba única só é dada uma vez por página', () async {
    expect(await PlataformaWeb().travarAbaUnica(), isTrue);
    expect(await PlataformaWeb().travarAbaUnica(), isFalse);
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

  test('pageshow restaurado do cache dispara paginaRestaurada; o comum não', () {
    final p = PlataformaWeb();
    var vezes = 0;
    p.paginaRestaurada.addListener(() => vezes++);
    html.window.dispatchEvent(
      html.PageTransitionEvent(
        'pageshow',
        html.PageTransitionEventInit(persisted: false),
      ),
    );
    expect(vezes, 0);
    html.window.dispatchEvent(
      html.PageTransitionEvent(
        'pageshow',
        html.PageTransitionEventInit(persisted: true),
      ),
    );
    expect(vezes, 1);
  });

  test('web é true e windows é false', () {
    final p = PlataformaWeb();
    expect(p.web, isTrue);
    expect(p.windows, isFalse);
  });
}
