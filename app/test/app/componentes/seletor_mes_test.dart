import 'dart:async';

import 'package:calculadoradarf/app/componentes/seletor_mes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: '2026-10-28'));

  Future<Future<String?> Function()> preparar(
    WidgetTester t, {
    String atual = '2026-10',
    Set<String> comDados = const {'2026-03'},
  }) async {
    await montarComponente(t, const SizedBox());
    final c = t.element(find.byType(SizedBox).first);
    return () =>
        escolherMes(c, atual: atual, comDados: comDados, maximo: '2026-10');
  }

  testWidgets(
    'escolherMes: futuro desabilitado, Mês atual devolve o mês de hoje, setas mudam o ano',
    (t) async {
      final abrir = await preparar(t, atual: '2026-03');
      var f = abrir();
      await t.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Verde: meses com operações'), findsOneWidget);

      // Nov e Dez de 2026 são futuros: tocar não fecha.
      await t.tap(find.text('Nov'));
      await t.pumpAndSettle();
      expect(find.text('Mês atual'), findsOneWidget);

      // Seta para a frente desabilitada no ano máximo; para trás muda o ano.
      await t.tap(find.byIcon(Icons.chevron_right));
      await t.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      // Mês anterior sem arquivo pode ser escolhido.
      await t.tap(find.text('Jan'));
      await t.pumpAndSettle();
      expect(await f, '2025-01');

      f = abrir();
      await t.pumpAndSettle();
      await t.tap(find.text('Mês atual'));
      await t.pumpAndSettle();
      expect(await f, '2026-10');

      f = abrir();
      await t.pumpAndSettle();
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
      expect(await f, isNull);
    },
  );

  testWidgets(
    'escolherMes: mês aberto e meses com dados têm pista não cromática',
    (t) async {
      final abrir = await preparar(t);
      unawaited(abrir());
      await t.pumpAndSettle();
      // Um para o mês aberto (marca), um para o mês com dados (ponto).
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
    },
  );
}
