import 'dart:async';

import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'apoio/montar.dart';
import 'apoio/plataforma_falsa.dart';
import 'apoio/servicos_falsos.dart';

CoresApp _cores(WidgetTester t) =>
    CoresApp.de(t.element(find.text('Calculadora DARF').first));

void main() {
  testWidgets('MaterialApp em português do Brasil com o título do app', (
    t,
  ) async {
    await montarApp(t);
    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Calculadora DARF');
    expect(app.locale, const Locale('pt', 'BR'));
    expect(find.byKey(chaveCaptura), findsOneWidget);
  });

  testWidgets('tema Automático segue o claro/escuro do sistema', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await montarApp(t, tema: TemaVisual.automatico);
    expect(_cores(t).destaque, const Color(0xFF6C5CE7)); // Moderno
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    expect(_cores(t).destaque, const Color(0xFF1B1F2A)); // Claro
  });

  testWidgets('trocar o tema pelo estado vale na hora', (t) async {
    await montarApp(t, tema: TemaVisual.claro);
    expect(_cores(t).destaque, const Color(0xFF1B1F2A));
    final estado = Provider.of<EstadoApp>(
      t.element(find.byType(Casca)),
      listen: false,
    );
    unawaited(estado.trocarTema(TemaVisual.terminal));
    await t.pumpAndSettle();
    expect(_cores(t).destaque, const Color(0xFF2EA043));
  });

  testWidgets('iniciarApp abre o app com os serviços dados', (t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ServicosFalsos();
    await iniciarApp(servicos: s, plataforma: PlataformaFalsa());
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Calculadora DARF'), findsWidgets);
    expect(s.chamadas, contains('iniciar()'));
  });

  testWidgets('o primeiro quadro já usa o tema gravado', (t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ServicosFalsos()
      ..estadoInicial = const EstadoInicial(
        mesInicial: '2026-10',
        mesesComDados: ['2026-10'],
        preferencias: Preferencias(tema: TemaVisual.terminal),
      );
    await iniciarApp(servicos: s, plataforma: PlataformaFalsa());
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_cores(t).destaque, const Color(0xFF2EA043)); // Terminal
    expect(s.chamadas.where((c) => c == 'iniciar()'), hasLength(1));
  });

  testWidgets('servicos.iniciar() que falha abre a tela de falha', (t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ServicosFalsos()..erros['iniciar'] = Exception('disco cheio');
    await iniciarApp(servicos: s, plataforma: PlataformaFalsa());
    await t.pump();
    expect(find.textContaining('disco cheio'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    s.erros.clear();
    await t.tap(find.text('Tentar de novo'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(Casca), findsOneWidget);
  });

  testWidgets('falha ao subir os serviços mostra o motivo', (t) async {
    var chamadas = 0;
    await t.pumpWidget(
      AppFalhaInicial('Sem permissão.', aoTentar: () => chamadas++),
    );
    expect(find.textContaining('Sem permissão.'), findsOneWidget);
    await t.tap(find.text('Tentar de novo'));
    expect(chamadas, 1);
  });

  testWidgets('Tentar de novo espera o encerramento da tentativa anterior', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final primeiro = _EncerraLento()..erros['iniciar'] = StateError('x');
    final segundo = ServicosFalsos();
    var criados = 0;
    await iniciarApp(
      plataforma: PlataformaFalsa(),
      criarServicos: (_) async => ++criados == 1 ? primeiro : segundo,
    );
    await t.pump();
    await t.tap(find.text('Tentar de novo'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(criados, 1); // ainda esperando o encerramento
    primeiro.encerrado.complete();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(seconds: 1));
    expect(criados, 2);
    expect(find.byType(Casca), findsOneWidget);
  });

  testWidgets('exatamente em 840 usa o layout de PC sem estourar', (t) async {
    await montarApp(t, tamanho: const Size(840, 700));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(t.takeException(), isNull);
    await montarApp(t, tamanho: const Size(839, 700));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('falha ao subir os serviços: motivo, sem Exception, e retenta', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ServicosFalsos();
    var tentativas = 0;
    await iniciarApp(
      plataforma: PlataformaFalsa(),
      criarServicos: (_) async {
        tentativas++;
        if (tentativas == 1) throw Exception('pasta bloqueada');
        return s;
      },
    );
    await t.pump();
    expect(find.textContaining('pasta bloqueada'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
    await t.tap(find.text('Tentar de novo'));
    // a recriação dos serviços é assíncrona de verdade
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(tentativas, 2);
    expect(find.byType(Casca), findsOneWidget);
    expect(s.chamadas, contains('iniciar()'));
  });
}

class _EncerraLento extends ServicosFalsos {
  final Completer<void> encerrado = Completer<void>();

  @override
  Future<void> encerrar() => encerrado.future;
}
