import 'package:calculadoradarf/app/componentes/tabela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

class _L {
  const _L(this.nome, this.valor);
  final String nome;
  final double? valor;
}

void main() {
  final colunas = [
    ColunaTabela<_L>(
      titulo: 'Ativo',
      largura: 100,
      texto: (l) => l.nome,
      chave: (l) => l.nome,
    ),
    ColunaTabela<_L>(
      titulo: 'Valor',
      largura: 100,
      alinhamento: TextAlign.right,
      texto: (l) => l.valor?.toString() ?? '—',
      chave: (l) => l.valor,
      cor: (c, l) => (l.valor ?? 0) < 0 ? Colors.red : null,
    ),
    ColunaTabela<_L>(titulo: 'Sem ordem', largura: 80, texto: (l) => '#'),
  ];
  const linhas = [_L('b', 2), _L('a', null), _L('c', -1)];

  Widget tabela({
    List<_L> dados = linhas,
    ValueChanged<_L>? aoSelecionar,
    ValueChanged<_L>? aoDuploClique,
    String? selecionado,
  }) => SizedBox(
    width: 500,
    height: 300,
    child: Tabela<_L>(
      colunas: colunas,
      linhas: dados,
      vazio: 'Nada aqui',
      aoSelecionar: aoSelecionar,
      aoDuploClique: aoDuploClique,
      selecionado: selecionado,
      id: (l) => l.nome,
    ),
  );

  // Texto da primeira coluna, de cima para baixo.
  List<String> ordemAtual(WidgetTester t) => [
    for (final w in t.widgetList<Text>(find.byKey(const Key('coluna-0'))))
      w.data!,
  ];

  testWidgets(
    'Tabela: clique no título ordena e o segundo inverte; vazio mostra o texto; duplo clique chama a ação',
    (t) async {
      _L? duplo;
      await montarComponente(t, tabela(aoDuploClique: (l) => duplo = l));
      expect(ordemAtual(t), ['b', 'a', 'c']);
      expect(find.text('Valor ↕'), findsOneWidget);
      expect(find.text('Sem ordem'), findsOneWidget);

      await t.tap(find.text('Ativo ↕'));
      await t.pump();
      expect(ordemAtual(t), ['a', 'b', 'c']);
      expect(find.text('Ativo ▲'), findsOneWidget);
      await t.tap(find.text('Ativo ▲'));
      await t.pump();
      expect(ordemAtual(t), ['c', 'b', 'a']);
      expect(find.text('Ativo ▼'), findsOneWidget);

      // Valor ausente conta como -infinito: primeiro no crescente.
      await t.tap(find.text('Valor ↕'));
      await t.pump();
      expect(ordemAtual(t), ['a', 'c', 'b']);
      expect(find.text('Ativo ↕'), findsOneWidget);

      // Coluna sem chave não ordena.
      await t.tap(find.text('Sem ordem'));
      await t.pump();
      expect(ordemAtual(t), ['a', 'c', 'b']);

      await t.tap(find.text('c'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(find.text('c'));
      await t.pumpAndSettle();
      expect(duplo?.nome, 'c');

      await montarComponente(t, tabela(dados: const []));
      expect(find.text('Nada aqui'), findsOneWidget);
    },
  );

  testWidgets('Tabela: clique seleciona e a linha selecionada é marcada', (
    t,
  ) async {
    _L? sel;
    await montarComponente(t, tabela(aoSelecionar: (l) => sel = l));
    await t.tap(find.text('a'));
    await t.pumpAndSettle();
    expect(sel?.nome, 'a');

    final h = t.ensureSemantics();
    await montarComponente(t, tabela(selecionado: 'b'));
    expect(
      t.getSemantics(find.byKey(const Key('linha-b'))),
      isSemantics(isSelected: true),
    );
    expect(
      t.getSemantics(find.byKey(const Key('linha-a'))),
      isSemantics(isSelected: false),
    );
    h.dispose();
  });

  testWidgets('Tabela: cor da célula vem do callback', (t) async {
    await montarComponente(t, tabela());
    final negativo = t.widget<Text>(find.text('-1.0'));
    expect(negativo.style?.color, Colors.red);
    final normal = t.widget<Text>(find.text('2.0'));
    expect(normal.style?.color, isNot(Colors.red));
  });
}
