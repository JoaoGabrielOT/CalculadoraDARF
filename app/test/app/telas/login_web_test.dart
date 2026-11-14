import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/telas/conta/tela_conta.dart';
import 'package:calculadoradarf/app/telas/login_web/tela_login_web.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/montar.dart';
import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

const _semToken = EstadoConta(temCredencial: true);
const _comToken = EstadoConta(
  temCredencial: true,
  temToken: true,
  status: StatusSync.sync,
);
const _conectada = EstadoConta(
  email: 'eu@gmail.com',
  temCredencial: true,
  temToken: true,
  status: StatusSync.ok,
);

ServicosFalsos _servicos(EstadoConta conta) =>
    ServicosFalsos()..estadoConta = conta;

Future<void> _montar(
  WidgetTester t,
  ServicosFalsos s, {
  bool web = true,
  Size tamanho = const Size(390, 844),
  PlataformaFalsa? plataforma,
}) async {
  await montarApp(
    t,
    servicos: s,
    plataforma: plataforma ?? PlataformaFalsa(web: web, windows: !web),
    tamanho: tamanho,
  );
  await t.pumpAndSettle();
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(MaterialApp)), listen: false);

Finder get _entrar => find.widgetWithText(FilledButton, 'Entrar com o Google');

void main() {
  testWidgets('Web sem token: tela de login, sem a casca', (t) async {
    await _montar(t, _servicos(_semToken));
    expect(find.text(textoLoginWebTitulo), findsOneWidget);
    expect(find.text(textoLoginWebCorpo), findsOneWidget);
    expect(find.text('Entrar com o Google'), findsOneWidget);
    expect(find.text(textoLoginWebContasAutorizadas), findsOneWidget);
    expect(find.byType(Casca), findsNothing);
  });

  testWidgets('tocar em Entrar com o Google chama conectar', (t) async {
    final s = _servicos(_semToken);
    await _montar(t, s);
    await t.tap(_entrar);
    await t.pump();
    expect(s.chamadas, contains('conectar()'));
  });

  testWidgets('com token ou com e-mail, a casca aparece', (t) async {
    await _montar(t, _servicos(_comToken));
    expect(find.byType(Casca), findsOneWidget);
    expect(find.byType(TelaLoginWeb), findsNothing);
  });

  testWidgets('com e-mail sem token, a casca aparece', (t) async {
    await _montar(
      t,
      _servicos(const EstadoConta(temCredencial: true, email: 'a@b.c')),
    );
    expect(find.byType(Casca), findsOneWidget);
    expect(find.byType(TelaLoginWeb), findsNothing);
  });

  testWidgets('fora da Web, sem token, a casca aparece', (t) async {
    await _montar(t, _servicos(_semToken), web: false);
    expect(find.byType(Casca), findsOneWidget);
    expect(find.byType(TelaLoginWeb), findsNothing);
  });

  testWidgets('aviso da fila aparece na tela de login', (t) async {
    await _montar(t, _servicos(_semToken));
    _estado(t).avisar('Sessão expirada', 'Conecte sua conta Google novamente.');
    await t.pumpAndSettle();
    expect(find.text('Sessão expirada'), findsOneWidget);
    expect(find.text('Conecte sua conta Google novamente.'), findsOneWidget);
    expect(_estado(t).avisos, isEmpty);
  });

  testWidgets('aguardando o login: botão desabilitado e Abrindo o Google', (
    t,
  ) async {
    await _montar(
      t,
      _servicos(
        const EstadoConta(status: StatusSync.login, temCredencial: true),
      ),
    );
    final botao = find.widgetWithText(FilledButton, 'Abrindo o Google...');
    expect(botao, findsOneWidget);
    expect(t.widget<FilledButton>(botao).onPressed, isNull);
    expect(find.text('Entrar com o Google'), findsNothing);
  });

  testWidgets(
    'página restaurada do cache com o login aberto: cancela e reabilita o botão',
    (t) async {
      final s = _servicos(_semToken)..loginPendente = Completer<void>();
      final p = PlataformaFalsa(web: true, windows: false);
      await _montar(t, s, plataforma: p);
      await t.tap(_entrar);
      await t.pump();
      expect(
        find.widgetWithText(FilledButton, 'Abrindo o Google...'),
        findsOneWidget,
      );
      p.restaurarPagina();
      await t.pumpAndSettle();
      expect(s.chamadas, contains('cancelarLogin()'));
      expect(t.widget<FilledButton>(_entrar).onPressed, isNotNull);
    },
  );

  testWidgets('página restaurada aguardando o login (status) cancela', (
    t,
  ) async {
    final s = _servicos(
      const EstadoConta(status: StatusSync.login, temCredencial: true),
    );
    final p = PlataformaFalsa(web: true, windows: false);
    await _montar(t, s, plataforma: p);
    p.restaurarPagina();
    await t.pump();
    expect(s.chamadas, contains('cancelarLogin()'));
  });

  testWidgets('página restaurada sem login aberto não cancela nada', (t) async {
    final s = _servicos(_semToken);
    final p = PlataformaFalsa(web: true, windows: false);
    await _montar(t, s, plataforma: p);
    p.restaurarPagina();
    await t.pump();
    expect(s.chamadas, isNot(contains('cancelarLogin()')));
  });

  group('Verificar atualização na Conta', () {
    Future<void> abrirConta(WidgetTester t, {required bool web}) async {
      await _montar(
        t,
        _servicos(_conectada),
        web: web,
        tamanho: const Size(400, 2400),
      );
      _estado(t).irPara(Aba.conta);
      await t.pumpAndSettle();
    }

    testWidgets('na Web não aparece', (t) async {
      await abrirConta(t, web: true);
      expect(find.byType(TelaConta), findsOneWidget);
      expect(find.text('Verificar atualização'), findsNothing);
    });

    testWidgets('fora da Web aparece', (t) async {
      await abrirConta(t, web: false);
      expect(find.text('Verificar atualização'), findsOneWidget);
    });
  });

  group('sessão que cai', () {
    testWidgets('sem a pessoa sair: a tela de login avisa', (t) async {
      final s = _servicos(_comToken);
      await _montar(t, s);
      expect(find.byType(Casca), findsOneWidget);
      // o servidor respondeu 401: o token some e o status vai a off
      s.eventosFalsos.add(const EventoConta(_semToken));
      await t.pumpAndSettle();
      expect(find.byType(TelaLoginWeb), findsOneWidget);
      expect(find.text('Sessão expirada'), findsOneWidget);
      expect(find.text('Faça login novamente.'), findsOneWidget);
    });

    testWidgets('com o aviso do sincronizador: um só, o último', (t) async {
      final s = _servicos(_conectada);
      await _montar(t, s);
      s.eventosFalsos
        ..add(const EventoConta(_semToken))
        ..add(
          const EventoAviso(
            'Sessão expirada',
            'Conecte sua conta Google novamente.',
          ),
        );
      await t.pumpAndSettle();
      expect(find.text('Sessão expirada'), findsOneWidget);
      expect(find.text('Conecte sua conta Google novamente.'), findsOneWidget);
      expect(find.text('Faça login novamente.'), findsNothing);
    });

    testWidgets('saindo pelo botão: sem o aviso', (t) async {
      final s = _servicos(_conectada);
      await _montar(t, s, tamanho: const Size(400, 2400));
      _estado(t).irPara(Aba.conta);
      await t.pumpAndSettle();
      await t.tap(
        find.ancestor(
          of: find.descendant(
            of: find.byType(TelaConta),
            matching: find.text('Sair'),
          ),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sair'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('sair()'));
      s.eventosFalsos.add(const EventoConta(_semToken));
      await t.pumpAndSettle();
      expect(find.byType(TelaLoginWeb), findsOneWidget);
      expect(find.text('Sessão expirada'), findsNothing);
      expect(_estado(t).avisos, isEmpty);
    });

    testWidgets('saída que falha não cala o aviso seguinte', (t) async {
      final s = _servicos(_conectada)..erros['sair'] = Exception('rede');
      await _montar(t, s, tamanho: const Size(400, 2400));
      _estado(t).irPara(Aba.conta);
      await t.pumpAndSettle();
      await t.tap(
        find.ancestor(
          of: find.descendant(
            of: find.byType(TelaConta),
            matching: find.text('Sair'),
          ),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sair'));
      await t.pump(const Duration(seconds: 7));
      await t.pumpAndSettle();
      s.eventosFalsos.add(const EventoConta(_semToken));
      await t.pumpAndSettle();
      expect(find.byType(TelaLoginWeb), findsOneWidget);
      expect(find.text('Faça login novamente.'), findsOneWidget);
    });

    testWidgets('fora da Web a sessão que cai não ganha aviso novo', (t) async {
      final s = _servicos(_comToken);
      await _montar(t, s, web: false);
      s.eventosFalsos.add(const EventoConta(_semToken));
      await t.pump();
      expect(_estado(t).avisos, isEmpty);
      expect(find.byType(TelaLoginWeb), findsNothing);
    });
  });
}
