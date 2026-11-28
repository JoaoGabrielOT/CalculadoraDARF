import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/extremos_vista.dart';
import 'package:calculadoradarf/nucleo/extremos.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/montar_componente.dart';

AnaliseExtremos _analise(double melhor, double pior) => AnaliseExtremos(
  melhor: melhor,
  pior: pior,
  extremos: const Extremos(
    maximo: Extremo(preco: 38, data: '2026-10-14'),
    minimo: Extremo(preco: 5, data: '2026-10-21'),
  ),
  desde: '2026-10-05',
  ate: '2026-10-28',
);

Future<void> _montar(
  WidgetTester t,
  AnaliseExtremos a, {
  double? real,
  String legenda = 'Resultado real',
  TemaVisual tema = TemaVisual.claro,
}) => montarComponente(
  t,
  SizedBox(
    width: 300,
    child: BlocoExtremos(
      analise: a,
      rotuloMelhor: 'Melhor possível',
      rotuloPior: 'Pior possível',
      real: real,
      legendaReal: legenda,
    ),
  ),
  tema: tema,
);

CoresApp _cores(WidgetTester t) =>
    CoresApp.de(t.element(find.byType(BlocoExtremos)));

Color? _fundo(WidgetTester t, String chave) =>
    ((t.widget<Container>(find.byKey(Key(chave))).decoration)! as BoxDecoration)
        .color;

/// Posição do marcador na faixa, de 0 (pior) a 1 (melhor).
double _posicao(WidgetTester t) {
  final faixa = find.byKey(const Key('faixa-extremos'));
  final m = find.byKey(const Key('marcador-extremos'));
  return (t.getCenter(m).dx - t.getTopLeft(faixa).dx) / t.getSize(faixa).width;
}

void main() {
  for (final tema in [TemaVisual.claro, TemaVisual.terminal]) {
    group('selos, tema ${tema.chave}', () {
      testWidgets('positivo: verde, ▲ e fundo translúcido', (t) async {
        await _montar(t, _analise(52.8, 10), tema: tema);
        final c = _cores(t);
        final texto = t.widget<Text>(find.text('▲ ${brl(52.8)}'));
        expect(texto.style?.color, c.alta);
        expect(_fundo(t, 'selo-melhor'), c.alta.withValues(alpha: .13));
      });

      testWidgets('negativo: vermelho, ▼ e fundo translúcido', (t) async {
        await _montar(t, _analise(10, -13.18), tema: tema);
        final c = _cores(t);
        final texto = t.widget<Text>(find.text('▼ ${brl(-13.18)}'));
        expect(texto.style?.color, c.queda);
        expect(_fundo(t, 'selo-pior'), c.queda.withValues(alpha: .13));
      });

      testWidgets('zero: cinza, sem seta', (t) async {
        await _montar(t, _analise(0, -5), tema: tema);
        final c = _cores(t);
        final texto = t.widget<Text>(find.text(brl(0)));
        expect(texto.style?.color, c.textoSuave);
        expect(_fundo(t, 'selo-melhor'), c.textoSuave.withValues(alpha: .13));
      });
    });
  }

  group('faixa e marcador', () {
    testWidgets('dentro da faixa: na posição proporcional', (t) async {
      await _montar(t, _analise(30, -10), real: 10);
      expect(find.byKey(const Key('faixa-extremos')), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('faixa-extremos'))).height, 6);
      expect(_posicao(t), closeTo(.5, .01));
      expect(find.text('Resultado real: ${brl(10)}'), findsOneWidget);
    });

    testWidgets('fora da faixa: preso na ponta', (t) async {
      await _montar(t, _analise(30, -10), real: 100);
      expect(_posicao(t), closeTo(1, .01));
      expect(find.text('Resultado real: ${brl(100)}'), findsOneWidget);
      await _montar(t, _analise(30, -10), real: -100);
      expect(_posicao(t), closeTo(0, .01));
    });

    testWidgets('ausente: barra sem marcador e sem legenda', (t) async {
      await _montar(t, _analise(30, -10));
      expect(find.byKey(const Key('faixa-extremos')), findsOneWidget);
      expect(find.byKey(const Key('marcador-extremos')), findsNothing);
      expect(find.textContaining('Resultado real'), findsNothing);
    });

    testWidgets('legenda "Hoje" e valor negativo', (t) async {
      await _montar(t, _analise(30, -10), real: -4, legenda: 'Hoje');
      expect(find.text('Hoje: ${brl(-4)}'), findsOneWidget);
    });

    testWidgets('mesmo valor nos dois extremos: marcador no meio', (t) async {
      await _montar(t, _analise(5, 5), real: 5);
      expect(_posicao(t), closeTo(.5, .01));
    });

    testWidgets('carregando e indisponível: sem faixa', (t) async {
      await _montar(t, const AnaliseExtremos(carregando: true), real: 1);
      expect(find.byKey(const Key('faixa-extremos')), findsNothing);
      expect(find.text('Carregando…'), findsNWidgets(2));
      await _montar(t, const AnaliseExtremos(), real: 1);
      expect(find.byKey(const Key('faixa-extremos')), findsNothing);
      expect(find.text('Indisponível'), findsNWidgets(2));
    });
  });

  testWidgets('Semantics resume os valores', (t) async {
    final h = t.ensureSemantics();
    await _montar(t, _analise(52.8, -13.18), real: 19.81);
    expect(
      find.bySemanticsLabel(
        'Melhor possível ${brl(52.8)}, pior possível ${brl(-13.18)}, '
        'resultado real ${brl(19.81)}',
      ),
      findsOneWidget,
    );
    await _montar(t, _analise(52.8, -13.18));
    expect(
      find.bySemanticsLabel(
        'Melhor possível ${brl(52.8)}, pior possível ${brl(-13.18)}',
      ),
      findsOneWidget,
    );
    h.dispose();
  });
}
