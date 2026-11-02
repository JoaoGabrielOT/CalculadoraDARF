import 'package:calculadoradarf/app/componentes/cartao.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  for (final tema in [
    TemaVisual.terminal,
    TemaVisual.claro,
    TemaVisual.moderno,
  ]) {
    testWidgets(
      'ChipFiltro selecionado tem ícone de marcação (${tema.chave})',
      (t) async {
        final h = t.ensureSemantics();
        await montarComponente(
          t,
          const Column(
            children: [
              ChipFiltro(rotulo: 'Todos', selecionado: true, aoTocar: null),
              ChipFiltro(rotulo: 'Altas', selecionado: false, aoTocar: null),
            ],
          ),
          tema: tema,
        );
        expect(
          find.descendant(
            of: find.widgetWithText(ChipFiltro, 'Todos'),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.widgetWithText(ChipFiltro, 'Altas'),
            matching: find.byIcon(Icons.check),
          ),
          findsNothing,
        );
        expect(
          t.getSemantics(find.widgetWithText(ChipFiltro, 'Todos')),
          isSemantics(isSelected: true, isButton: true),
        );
        h.dispose();
      },
    );
  }

  testWidgets('ChipFiltro chama aoTocar', (t) async {
    var n = 0;
    await montarComponente(
      t,
      ChipFiltro(rotulo: 'Altas', selecionado: false, aoTocar: () => n++),
    );
    await t.tap(find.text('Altas'));
    expect(n, 1);
  });

  testWidgets('BotaoSegmentado marca só a opção atual e avisa a escolha', (
    t,
  ) async {
    String? escolhido;
    await montarComponente(
      t,
      BotaoSegmentado<String>(
        opcoes: const [('a', 'Ações'), ('f', 'FIIs')],
        valor: 'a',
        aoMudar: (v) => escolhido = v,
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    await t.tap(find.text('FIIs'));
    expect(escolhido, 'f');
  });

  testWidgets('Cartao, Selo, Pilula e Kpi mostram seus textos', (t) async {
    await montarComponente(
      t,
      const Cartao(
        child: Column(
          children: [
            Kpi(titulo: 'Imposto', valor: 'R\$ 10,00', sub: 'no mês'),
            Selo(texto: '+1,2%', alta: true),
            Selo(texto: '-1,2%', alta: false),
            Pilula(texto: 'Isento'),
          ],
        ),
      ),
    );
    for (final s in [
      'Imposto',
      'R\$ 10,00',
      'no mês',
      '+1,2%',
      '-1,2%',
      'Isento',
    ]) {
      expect(find.text(s), findsOneWidget);
    }
  });
}
