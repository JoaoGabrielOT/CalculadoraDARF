import 'package:calculadoradarf/app/componentes/tabela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

class _Mutavel {
  _Mutavel(this.nome, this.valor);
  final String nome;
  double valor;
}

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

  group('Tabela: ids, ordenação robusta e cache', () {
    Widget tab<L>({
      required List<ColunaTabela<L>> cols,
      required List<L> dados,
      String? selecionado,
      String Function(L)? id,
    }) => SizedBox(
      width: 500,
      height: 300,
      child: Tabela<L>(
        colunas: cols,
        linhas: dados,
        vazio: 'v',
        selecionado: selecionado,
        id: id,
      ),
    );

    List<String> coluna0(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byKey(const Key('coluna-0'))))
        w.data!,
    ];

    testWidgets('linhas de texto repetido: só a do id fica selecionada', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final dados = [(1, 'x'), (2, 'x'), (3, 'x')];
      await montarComponente(
        t,
        tab<(int, String)>(
          cols: [ColunaTabela(titulo: 'T', largura: 1, texto: (l) => l.$2)],
          dados: dados,
          selecionado: '2',
          id: (l) => '${l.$1}',
        ),
      );
      expect(t.takeException(), isNull);
      expect(
        t.getSemantics(find.byKey(const Key('linha-2'))),
        isSemantics(isSelected: true),
      );
      expect(
        t.getSemantics(find.byKey(const Key('linha-1'))),
        isSemantics(isSelected: false),
      );
      h.dispose();
    });

    testWidgets('sem id, linhas repetidas não duplicam Key', (t) async {
      await montarComponente(
        t,
        tab<String>(
          cols: [ColunaTabela(titulo: 'T', largura: 1, texto: (l) => l)],
          dados: const ['x', 'x'],
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.text('x'), findsNWidgets(2));
    });

    test('selecionado sem id é erro de programação', () {
      expect(
        () => Tabela<String>(
          colunas: [ColunaTabela(titulo: 'T', largura: 1, texto: (l) => l)],
          linhas: const ['x'],
          vazio: 'v',
          selecionado: 'x',
        ),
        throwsAssertionError,
      );
    });

    testWidgets(
      'ordenar com texto repetido, null, tipos mistos e NaN não lança',
      (t) async {
        final cols = [
          ColunaTabela<(String, Object?)>(
            titulo: 'N',
            largura: 1,
            texto: (l) => l.$1,
            chave: (l) => l.$2,
          ),
        ];
        Future<void> ordenar(List<(String, Object?)> dados) async {
          // Key nova: cada chamada começa sem ordenação.
          await montarComponente(
            t,
            KeyedSubtree(
              key: UniqueKey(),
              child: tab(cols: cols, dados: dados),
            ),
          );
          await t.tap(find.text('N ↕'));
          await t.pump();
          expect(t.takeException(), isNull);
        }

        // texto repetido e null em coluna de texto: null (vazio) primeiro
        await ordenar([('a', 'b'), ('b', null), ('c', 'B'), ('d', 'a')]);
        expect(coluna0(t), ['b', 'd', 'a', 'c']);
        // tipos mistos: cai para texto
        await ordenar([('a', 10), ('b', 'abc'), ('c', 2.5), ('d', true)]);
        expect(coluna0(t).length, 4);
        // NaN entre números
        await ordenar([('a', 3.0), ('b', double.nan), ('c', 1.0)]);
        expect(coluna0(t), ['b', 'c', 'a']);
      },
    );

    testWidgets(
      'a ordenação é guardada: rebuild com a mesma lista não recalcula',
      (t) async {
        var chamadas = 0;
        final dados = [('b', 2.0), ('a', 1.0)];
        final cols = [
          ColunaTabela<(String, double)>(
            titulo: 'N',
            largura: 1,
            texto: (l) => l.$1,
            chave: (l) {
              chamadas++;
              return l.$2;
            },
          ),
        ];
        late StateSetter reconstruir;
        var selecionado = 'a';
        await montarComponente(
          t,
          StatefulBuilder(
            builder: (c, set) {
              reconstruir = set;
              return tab<(String, double)>(
                cols: cols,
                dados: dados,
                selecionado: selecionado,
                id: (l) => l.$1,
              );
            },
          ),
        );
        await t.tap(find.text('N ↕'));
        await t.pump();
        final depois = chamadas;
        expect(depois, greaterThan(0));
        reconstruir(() => selecionado = 'b');
        await t.pump();
        // Mesma lista: só valida as chaves (uma passada, sem reordenar).
        expect(chamadas, depois + dados.length);
        // inverter o sentido recalcula
        await t.tap(find.text('N ▲'));
        await t.pump();
        expect(chamadas, greaterThan(depois));
      },
    );

    testWidgets(
      'lista alterada no lugar: ordenada reflete remoção e inclusão',
      (t) async {
        final dados = [('c', 3.0), ('a', 1.0), ('b', 2.0)];
        final cols = [
          ColunaTabela<(String, double)>(
            titulo: 'N',
            largura: 1,
            texto: (l) => l.$1,
            chave: (l) => l.$2,
          ),
        ];
        late StateSetter reconstruir;
        await montarComponente(
          t,
          StatefulBuilder(
            builder: (c, set) {
              reconstruir = set;
              return tab<(String, double)>(cols: cols, dados: dados);
            },
          ),
        );
        await t.tap(find.text('N ↕'));
        await t.pump();
        expect(coluna0(t), ['a', 'b', 'c']);

        reconstruir(() {
          dados.removeAt(0); // sai o 'c'
          dados.add(('d', 0.5)); // entra o 'd'
        });
        await t.pump();
        expect(coluna0(t), ['d', 'a', 'b']);

        // Mesma identidade e mesmo tamanho, mas o valor da chave mudou.
        final mutavel = _Mutavel('x', 5);
        final outros = [mutavel, _Mutavel('y', 3)];
        await montarComponente(
          t,
          KeyedSubtree(
            key: UniqueKey(),
            child: StatefulBuilder(
              builder: (c, set) {
                reconstruir = set;
                return tab<_Mutavel>(
                  cols: [
                    ColunaTabela<_Mutavel>(
                      titulo: 'N',
                      largura: 1,
                      texto: (l) => l.nome,
                      chave: (l) => l.valor,
                    ),
                  ],
                  dados: outros,
                );
              },
            ),
          ),
        );
        await t.tap(find.text('N ↕'));
        await t.pump();
        expect(coluna0(t), ['y', 'x']);
        reconstruir(() => mutavel.valor = 1);
        await t.pump();
        expect(coluna0(t), ['x', 'y']);
      },
    );

    testWidgets('ids repetidos viram erro de programação (debug)', (t) async {
      await montarComponente(
        t,
        tab<String>(
          cols: [ColunaTabela(titulo: 'T', largura: 1, texto: (l) => l)],
          dados: const ['x', 'x'],
          id: (l) => l,
        ),
      );
      final erro = t.takeException();
      expect(erro, isA<AssertionError>());
      expect(erro.toString(), contains('id'));
    });

    testWidgets('larguras menores que 0,5 mantêm a proporção', (t) async {
      await montarComponente(
        t,
        tab<String>(
          cols: [
            ColunaTabela(titulo: 'E', largura: 0.1, texto: (l) => l),
            ColunaTabela(titulo: 'L', largura: 0.3, texto: (l) => 'larga'),
          ],
          dados: const ['z'],
        ),
      );
      double larguraDe(String titulo) => t
          .getSize(
            find.ancestor(
              of: find.text(titulo),
              matching: find.byType(InkWell),
            ),
          )
          .width;
      expect(larguraDe('L') / larguraDe('E'), closeTo(3, 0.01));
    });
  });

  testWidgets('Tabela: cor da célula vem do callback', (t) async {
    await montarComponente(t, tabela());
    final negativo = t.widget<Text>(find.text('-1.0'));
    expect(negativo.style?.color, Colors.red);
    final normal = t.widget<Text>(find.text('2.0'));
    expect(normal.style?.color, isNot(Colors.red));
  });
}
