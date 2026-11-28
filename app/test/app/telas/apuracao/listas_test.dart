import 'dart:async';

import 'package:calculadoradarf/app/componentes/cartao.dart' show Cartao;
import 'package:calculadoradarf/app/componentes/controles.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/apuracao/barra_filtros.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/lista_lotes.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 1400);
const _celular = Size(360, 3000);

/// Mês de exemplo com uma quarta compra totalmente vendida.
Mes _mesComVendido() {
  final base = mesAbertoExemplo();
  return Mes(
    mes: base.mes,
    lotes: [
      ...base.lotes,
      Lote(
        id: 'L4',
        ticker: 'ITUB4',
        tipo: 'Ação',
        dataCompra: '2026-10-02',
        qtd: 10,
        preco: 30,
        vendas: [Venda(id: 'V4', data: '2026-10-03', qtd: 10, preco: 31)],
      ),
    ],
  );
}

Future<ServicosFalsos> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  bool windows = true,
}) async {
  final s = servicos ?? ServicosFalsos();
  await montarApp(
    t,
    servicos: s,
    plataforma: PlataformaFalsa(windows: windows),
    tamanho: tamanho,
    tela: const TelaApuracao(
      conteudo: listasApuracao,
      sliversCompactos: listasSliversApuracao,
    ),
  );
  await t.pumpAndSettle();
  return s;
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaApuracao)), listen: false);

int _chamadasA(ServicosFalsos s, String prefixo) =>
    s.chamadas.where((c) => c.startsWith(prefixo)).length;

Finder _celula(String id, int coluna) => find.descendant(
  of: find.byKey(Key('linha-$id')),
  matching: find.byKey(Key('coluna-$coluna')),
);

String _textoCelula(WidgetTester t, String id, int coluna) =>
    t.widget<Text>(_celula(id, coluna)).data!;

Finder _item(String texto) => find.widgetWithText(PopupMenuItem<String>, texto);

double _y(WidgetTester t, String texto) =>
    t.getTopLeft(find.text(texto).first).dy;

/// Ações que são só ícone (o tooltip é o rótulo antigo).
const _soIcone = {'Editar', 'Excluir', 'Editar venda', 'Excluir venda'};

Finder _botao(String rotulo) => _soIcone.contains(rotulo)
    ? find.descendant(
        of: find.byTooltip(rotulo),
        matching: find.byType(IconButton),
      )
    : find.ancestor(
        of: find.text(rotulo),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

bool _habilitado(WidgetTester t, String rotulo) =>
    switch (t.widget(_botao(rotulo))) {
      final ButtonStyleButton b => b.onPressed != null,
      final IconButton b => b.onPressed != null,
      final w => throw StateError('botão inesperado: $w'),
    };

/// Texto do campo de busca da lista [id] ('lotes' ou 'vendas').
String _busca(WidgetTester t, String id) => t
    .widget<TextField>(
      find.descendant(
        of: find.byKey(Key('busca-$id')),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

/// Abre o Ordenar da lista [id] e inverte a direção.
Future<void> _inverter(WidgetTester t, String id) async {
  await t.tap(find.byKey(Key('chip-$id-ordem')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key('inverter-$id')));
  await t.pumpAndSettle();
}

String _rotuloOrdenar(WidgetTester t, String id) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(Key('chip-$id-ordem')),
        matching: find.byType(Text),
      ),
    )
    .data!;

Finder _ponto(String chave) => find.descendant(
  of: find.byKey(Key(chave)),
  matching: find.byKey(const ValueKey('ponto-marcado')),
);

Finder _noDialogo(String texto) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(texto));

/// Marca a linha: o toque simples espera o fim da janela do duplo toque.
Future<void> _selecionar(WidgetTester t, String id) async {
  await t.tap(find.byKey(Key('linha-$id')));
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

Finder _tituloLotes(String texto) => find.descendant(
  of: find.byKey(const Key('tabela-lotes')),
  matching: find.text(texto),
);

Future<void> _duploToque(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 50));
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets('expandido largo: tabela de ativos com as 11 colunas', (t) async {
    await _montar(t, tamanho: const Size(1920, 1400));
    for (final titulo in [
      'TICKER ↕',
      'TIPO',
      'COMPRA ↕',
      'QTD ↕',
      'PREÇO ↕',
      'ATUAL ↕',
      'TOTAL ↕',
      'GANHO/PERDA ↕',
      'VENDIDA',
      'RESTANTE ↕',
      'SITUAÇÃO',
    ]) {
      expect(_tituloLotes(titulo), findsOneWidget, reason: titulo);
    }
    expect(find.text('Ativos comprados'), findsOneWidget);
    expect(
      find.text('Clique nos títulos das colunas para ordenar'),
      findsOneWidget,
    );
    expect(_textoCelula(t, 'L1', 0), 'PETR4');
    expect(_textoCelula(t, 'L1', 2), '05/10/2026');
    expect(_textoCelula(t, 'L1', 8), '40');
    expect(_textoCelula(t, 'L1', 9), '60');
    expect(_textoCelula(t, 'L1', 10), 'Vendido parcial');
    expect(_textoCelula(t, 'L2', 10), 'Não vendido');
  });

  testWidgets('expandido: ordena pelo título e filtra por situação com '
      'contagem visíveis/total', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
    await _montar(t, servicos: s);
    expect(find.byKey(const Key('contagem-lotes')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '4');

    await t.tap(find.text('Em aberto'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '3/4');
    expect(find.byKey(const Key('linha-L4')), findsNothing);

    await t.tap(find.text('Vendidos'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '1/4');
    expect(find.byKey(const Key('linha-L4')), findsOneWidget);
    expect(find.byKey(const Key('linha-L2')), findsNothing);

    await t.tap(find.text('Todos'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '4');

    // título da coluna ordena (TICKER crescente: AAPL34 antes de VALE3)
    await t.tap(_tituloLotes('TICKER ↕'));
    await t.pumpAndSettle();
    expect(_tituloLotes('TICKER ▲'), findsOneWidget);
    final ys = [
      for (final id in ['L3', 'L4', 'L1', 'L2'])
        t.getTopLeft(find.byKey(Key('linha-$id'))).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('duas compras iguais não se confundem na seleção', (t) async {
    final s = ServicosFalsos();
    Lote igual(String id) => Lote(
      id: id,
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-10-08',
      qtd: 100,
      preco: 60,
    );
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10', lotes: [igual('A1'), igual('A2')]),
    );
    await _montar(t, servicos: s);
    await _selecionar(t, 'A2');
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('excluirCompra(2026-10, A2)'));
  });

  testWidgets('duplo clique na compra abre Registrar venda com o lote', (
    t,
  ) async {
    await _montar(t);
    await _duploToque(t, find.byKey(const Key('linha-L2')));
    expect(find.text('Registrar venda'), findsWidgets);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('ticker')))
          .controller!
          .text,
      'VALE3',
    );
  });

  testWidgets('duplo clique na venda abre Editar venda', (t) async {
    await _montar(t);
    await _duploToque(t, find.byKey(const Key('linha-V1')));
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Editar venda'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('expandido: botões sem seleção avisam com o texto do Python', (
    t,
  ) async {
    final s = await _montar(t);
    final pedidos = {
      'Editar': [
        'Editar',
        'Selecione uma compra na tabela de ativos comprados.',
      ],
      'Excluir': [
        'Excluir',
        'Selecione um ativo na tabela de ativos comprados.',
      ],
      'Editar venda': ['Editar', 'Selecione uma venda na tabela de vendas.'],
      'Excluir venda': ['Excluir', 'Selecione uma venda na tabela de vendas.'],
    };
    for (final e in pedidos.entries) {
      await t.tap(_botao(e.key));
      await t.pumpAndSettle();
      expect(_noDialogo(e.value[0]), findsOneWidget, reason: e.key);
      expect(_noDialogo(e.value[1]), findsOneWidget, reason: e.key);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
    }
    expect(_chamadasA(s, 'excluir'), 0);
    expect(_chamadasA(s, 'editar'), 0);
  });

  testWidgets('Registrar venda sem compra em aberto avisa uma vez só', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(
        mes: '2026-10',
        lotes: [
          Lote(
            id: 'X',
            ticker: 'ITUB4',
            tipo: 'Ação',
            dataCompra: '2026-10-02',
            qtd: 10,
            preco: 30,
            vendas: [Venda(id: 'XV', data: '2026-10-03', qtd: 10, preco: 31)],
          ),
        ],
      ),
    );
    await _montar(t, servicos: s);
    await t.tap(_botao('Registrar venda'));
    await t.pumpAndSettle();
    expect(find.text('Não há compras em aberto neste mês.'), findsOneWidget);
  });

  testWidgets('excluir pede confirmação com o texto do Python', (t) async {
    final s = await _montar(t);
    // compra com vendas
    await _selecionar(t, 'L1');
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    expect(_noDialogo('Excluir ativo'), findsOneWidget);
    expect(_noDialogo('Excluir PETR4 e todas as vendas dele?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(_chamadasA(s, 'excluirCompra'), 0);

    // compra sem vendas
    await _selecionar(t, 'L2');
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    expect(_noDialogo('Excluir VALE3?'), findsOneWidget);
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('excluirCompra(2026-10, L2)'));

    // venda
    await _selecionar(t, 'V1');
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir venda'));
    await t.pumpAndSettle();
    expect(_noDialogo('Excluir venda'), findsOneWidget);
    expect(_noDialogo('Excluir esta venda?'), findsOneWidget);
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('excluirVenda(2026-10, V1)'));
  });

  testWidgets('erro ao excluir aparece em aviso, sem Exception', (t) async {
    final s = ServicosFalsos();
    s.erros['excluirCompra'] = ErroValidacao('Mês fechado.');
    await _montar(t, servicos: s);
    await _selecionar(t, 'L2');
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(find.text('Mês fechado.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('nova compra pergunta "Você já fez a venda de <T>?" e abre a '
      'venda no Sim', (t) async {
    final s = ServicosFalsos();
    final base = mesAbertoExemplo();
    s.visaoAposCompra = visaoExemplo(
      Mes(
        mes: '2026-10',
        lotes: [
          ...base.lotes,
          Lote(
            id: 'L9',
            ticker: 'ITUB4',
            tipo: 'Ação',
            dataCompra: '2026-10-28',
            qtd: 10,
            preco: 30,
          ),
        ],
      ),
    );
    await _montar(t, servicos: s);
    await t.tap(_botao('Novo ativo'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('ticker')), 'ITUB4');
    await t.enterText(find.byKey(const ValueKey('qtd')), '10');
    await t.enterText(find.byKey(const ValueKey('preco')), '30');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('Você já fez a venda de ITUB4?'), findsOneWidget);
    await t.tap(find.text('Sim, registrar venda'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('ticker')))
          .controller!
          .text,
      'ITUB4',
    );
  });

  for (final (nome, tamanho) in [('expandido', _pc), ('compacto', _celular)]) {
    testWidgets('filtros da união ($nome): busca, tipo, ordem, inverter e '
        'Limpar nas compras', (t) async {
      await _montar(t, tamanho: tamanho);
      expect(find.text('Limpar'), findsNothing);

      // busca: o campo fica sempre à vista
      await t.enterText(find.byKey(const Key('busca-lotes')), 'vale');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('contagem-lotes')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data,
        '1/3',
      );
      expect(find.text('AAPL34'), findsNothing);
      expect(find.byKey(const Key('limpar-lotes')), findsOneWidget);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '3');
      expect(_busca(t, 'lotes'), '');
      expect(find.text('Limpar'), findsNothing);

      // tipo
      await t.tap(find.byKey(const Key('chip-lotes-tipo')));
      await t.pumpAndSettle();
      for (final opcao in ['Todos', 'Ação', 'BDR']) {
        expect(_item(opcao), findsOneWidget, reason: opcao);
      }
      await t.tap(_item('BDR'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data,
        '1/3',
      );
      expect(find.text('AAPL34'), findsOneWidget);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();

      // ordem por ticker (crescente) e inversão pelo item do menu
      await t.tap(find.byKey(const Key('chip-lotes-ordem')));
      await t.pumpAndSettle();
      await t.tap(_item('Ticker'));
      await t.pumpAndSettle();
      expect(_y(t, 'AAPL34') < _y(t, 'PETR4'), isTrue);
      expect(_y(t, 'PETR4') < _y(t, 'VALE3'), isTrue);
      await _inverter(t, 'lotes');
      expect(_y(t, 'VALE3') < _y(t, 'PETR4'), isTrue);
      expect(_y(t, 'PETR4') < _y(t, 'AAPL34'), isTrue);
    });

    testWidgets('filtros da união ($nome): operação, tipo e busca nas '
        'vendas', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
      await _montar(t, servicos: s, tamanho: tamanho);
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data,
        '2',
      );
      await t.tap(find.byKey(const Key('chip-vendas-operacao')));
      await t.pumpAndSettle();
      for (final opcao in ['Todas', 'Swing', 'Day trade']) {
        expect(_item(opcao), findsOneWidget, reason: opcao);
      }
      await t.tap(_item('Day trade'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data,
        '0/2',
      );
      expect(find.text('Nenhuma venda para esse filtro.'), findsOneWidget);
      await t.tap(find.byKey(const Key('limpar-vendas')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('chip-vendas-tipo')));
      await t.pumpAndSettle();
      await t.tap(_item('BDR'));
      await t.pumpAndSettle();
      expect(find.text('Nenhuma venda para esse filtro.'), findsOneWidget);
      await t.tap(find.byKey(const Key('limpar-vendas')));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(const Key('busca-vendas')), 'itub');
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data,
        '1/2',
      );
    });
  }

  group('PC 1366 (app inteiro)', () {
    Future<ServicosFalsos> montarApp1366(
      WidgetTester t, {
      double altura = 768,
    }) async {
      final s = ServicosFalsos()
        ..precos = {'PETR4': 36.2, 'VALE3': 58.4, 'AAPL34': 57.1};
      await montarApp(t, servicos: s, tamanho: Size(1366, altura));
      await t.pumpAndSettle();
      return s;
    }

    Finder cartaoDe(String chave) => find
        .ancestor(of: find.byKey(Key(chave)), matching: find.byType(Cartao))
        .first;

    Finder rolagemDe(String chave) => find.ancestor(
      of: find.byKey(Key(chave)),
      matching: find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );

    testWidgets('compras: TICKER…GANHO/PERDA à vista sem rolar; o resto à '
        'direita, alcançável rolando com a barra visível', (t) async {
      await montarApp1366(t);
      final rolagem = rolagemDe('tabela-lotes');
      expect(rolagem, findsOneWidget);
      final posicao = t
          .state<ScrollableState>(
            find
                .descendant(of: rolagem, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      expect(posicao.pixels, 0);
      expect(posicao.maxScrollExtent, greaterThan(0));
      expect(
        find.ancestor(
          of: find.byKey(const Key('tabela-lotes')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollbar && w.thumbVisibility == true,
          ),
        ),
        findsOneWidget,
      );
      final ganho = _celula('L1', 6);
      expect(t.widget<Text>(ganho).data, startsWith('▲ +R\$'));
      final cartao = t.getRect(cartaoDe('tabela-lotes'));
      final texto = t.getRect(ganho);
      expect(cartao.left <= texto.left && texto.right <= cartao.right, isTrue);
      expect(t.renderObject<RenderParagraph>(ganho).didExceedMaxLines, isFalse);
      // nenhuma coluna some
      for (final titulo in ['TOTAL ↕', 'VENDIDA', 'RESTANTE ↕', 'SITUAÇÃO']) {
        expect(_tituloLotes(titulo), findsOneWidget, reason: titulo);
      }
      // nenhuma célula corta o texto
      final celulas = find.descendant(
        of: find.byKey(const Key('linha-L1')),
        matching: find.byType(Text),
      );
      for (var i = 0; i < celulas.evaluate().length; i++) {
        expect(
          t.renderObject<RenderParagraph>(celulas.at(i)).didExceedMaxLines,
          isFalse,
        );
      }
    });

    testWidgets('vendas: todas as colunas, sem cortar texto; as de fora '
        'rolam', (t) async {
      // a altura só traz o cartão de vendas à vista; a largura é a de 1366
      await montarApp1366(t, altura: 1400);
      for (final titulo in ['TAXAS B3 ↕', 'LUCRO BRUTO ↕', 'APÓS TAXAS ↕']) {
        expect(
          find.descendant(
            of: find.byKey(const Key('tabela-vendas')),
            matching: find.text(titulo),
          ),
          findsOneWidget,
          reason: titulo,
        );
      }
      final textos = find.descendant(
        of: find.byKey(const Key('linha-V1')),
        matching: find.byType(Text),
      );
      for (var i = 0; i < textos.evaluate().length; i++) {
        expect(
          t.renderObject<RenderParagraph>(textos.at(i)).didExceedMaxLines,
          isFalse,
        );
      }
      expect(rolagemDe('tabela-vendas'), findsOneWidget);
    });

    testWidgets('a ordenação pelo título não reinicia ao mudar a largura', (
      t,
    ) async {
      await montarApp1366(t);
      await t.tap(_tituloLotes('TICKER ↕'));
      await t.pumpAndSettle();
      expect(_tituloLotes('TICKER ▲'), findsOneWidget);
      t.view.physicalSize = const Size(1900, 768);
      await t.pumpAndSettle();
      expect(_tituloLotes('TICKER ▲'), findsOneWidget);
      // largo, cabe tudo: não há o que rolar
      expect(
        t
            .state<ScrollableState>(
              find
                  .descendant(
                    of: rolagemDe('tabela-lotes'),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .maxScrollExtent,
        0,
      );
      t.view.physicalSize = const Size(1366, 768);
      await t.pumpAndSettle();
      expect(_tituloLotes('TICKER ▲'), findsOneWidget);
    });

    testWidgets('filtros numa linha: Situação, busca, Tipo e Ordenar', (
      t,
    ) async {
      await montarApp1366(t);
      final dy = t.getCenter(find.byType(Segmentado<String>)).dy;
      for (final f in [
        find.byKey(const Key('busca-lotes')),
        find.byKey(const Key('chip-lotes-tipo')),
        find.byKey(const Key('chip-lotes-ordem')),
      ]) {
        expect(t.getCenter(f).dy, moreOrLessEquals(dy, epsilon: 1));
      }
      expect(
        t.getSize(find.byKey(const Key('busca-lotes'))).width,
        greaterThanOrEqualTo(160),
      );
    });
  });

  group('controles do cartão (PC)', () {
    testWidgets('Ativos comprados: ícones Editar e Excluir, Registrar venda '
        'secundário e Novo ativo principal, na ponta direita', (t) async {
      await _montar(t);
      final editar = t.widget<BotaoIcone>(
        find.ancestor(of: _botao('Editar'), matching: find.byType(BotaoIcone)),
      );
      expect(editar.icone, Icons.edit);
      expect(editar.destrutivo, isFalse);
      final excluir = t.widget<BotaoIcone>(
        find.ancestor(of: _botao('Excluir'), matching: find.byType(BotaoIcone)),
      );
      expect(excluir.icone, Icons.delete);
      expect(excluir.destrutivo, isTrue);
      expect(
        find.widgetWithText(BotaoSecundario, 'Registrar venda'),
        findsOneWidget,
      );
      expect(find.widgetWithText(BotaoPrincipal, 'Novo ativo'), findsOneWidget);
      // da esquerda para a direita: Editar, Excluir, Registrar venda, Novo
      final xs = [
        for (final r in ['Editar', 'Excluir', 'Registrar venda', 'Novo ativo'])
          t.getCenter(_botao(r)).dx,
      ];
      expect(xs, [...xs]..sort());
      expect(
        t.getCenter(_botao('Editar')).dy,
        moreOrLessEquals(t.getCenter(_botao('Novo ativo')).dy, epsilon: 1),
      );
      // o título fica à esquerda, longe das ações
      expect(
        t.getCenter(find.text('Ativos comprados')).dx,
        lessThan(xs.first - 200),
      );
    });

    testWidgets('Posição | Carteira segmentado, com a cotação em texto à '
        'direita', (t) async {
      await _montar(t);
      final seletor = find.byKey(const Key('seletor-posicao'));
      expect(seletor, findsOneWidget);
      expect(t.widget(seletor), isA<Segmentado<ModoLista>>());
      expect(
        find.descendant(of: seletor, matching: find.text('Carteira atual')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: seletor,
          matching: find.text('Posição em 28/10/2026'),
        ),
        findsOneWidget,
      );
      final cotacao = find.textContaining(RegExp('[Cc]otação atual'));
      expect(cotacao, findsOneWidget);
      expect(t.getTopLeft(cotacao).dx, greaterThan(t.getTopRight(seletor).dx));
    });

    testWidgets('filtros: Situação segmentada, busca, Tipo e Ordenar com as '
        'opções de hoje', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
      await _montar(t, servicos: s);
      final situacao = find.byType(Segmentado<String>);
      expect(situacao, findsOneWidget);
      expect(t.widget<Segmentado<String>>(situacao).compacto, isFalse);
      for (final o in ['Todos', 'Em aberto', 'Vendidos']) {
        expect(
          find.descendant(of: situacao, matching: find.text(o)),
          findsOneWidget,
        );
      }
      final busca = find.descendant(
        of: find.byKey(const Key('busca-lotes')),
        matching: find.byType(CampoBusca),
        matchRoot: true,
      );
      expect(t.widget<CampoBusca>(busca).dica, 'Buscar ticker…');
      expect(
        find.descendant(
          of: find.byKey(const Key('chip-lotes-tipo')),
          matching: find.text('Tipo'),
        ),
        findsOneWidget,
      );
      expect(_rotuloOrdenar(t, 'lotes'), 'Cadastro ↑');
      await t.tap(find.byKey(const Key('chip-lotes-ordem')));
      await t.pumpAndSettle();
      for (final o in [
        'Cadastro',
        'Data da compra',
        'Ticker',
        'Quantidade',
        'Preço de compra',
        'Preço atual',
        'Total',
        'Ganho/perda',
        'Restante',
      ]) {
        expect(_item(o), findsOneWidget, reason: o);
      }
      // trocar de campo usa a direção padrão dele (Total: decrescente)
      await t.tap(_item('Total'));
      await t.pumpAndSettle();
      expect(_rotuloOrdenar(t, 'lotes'), 'Total ↓');
      await t.tap(find.byKey(const Key('chip-lotes-ordem')));
      await t.pumpAndSettle();
      await t.tap(_item('Cadastro'));
      await t.pumpAndSettle();
      // cadastro: PETR4 antes de AAPL34; invertido, ao contrário
      expect(_y(t, 'PETR4') < _y(t, 'AAPL34'), isTrue);
      await _inverter(t, 'lotes');
      expect(_rotuloOrdenar(t, 'lotes'), 'Cadastro ↓');
      expect(_y(t, 'AAPL34') < _y(t, 'PETR4'), isTrue);

      // a situação segmentada filtra
      await t.tap(
        find.descendant(of: situacao, matching: find.text('Vendidos')),
      );
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data,
        '1/4',
      );
      expect(find.byKey(const Key('limpar-lotes')), findsOneWidget);
    });

    testWidgets('Vendas do mês: ícones Editar venda e Excluir venda, menus '
        'Operação e Tipo e Ordenar', (t) async {
      await _montar(t);
      expect(
        t
            .widget<BotaoIcone>(
              find.ancestor(
                of: _botao('Excluir venda'),
                matching: find.byType(BotaoIcone),
              ),
            )
            .destrutivo,
        isTrue,
      );
      expect(_botao('Editar venda'), findsOneWidget);
      for (final (chave, rotulo) in [
        ('chip-vendas-operacao', 'Operação'),
        ('chip-vendas-tipo', 'Tipo'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key(chave)),
            matching: find.text(rotulo),
          ),
          findsOneWidget,
          reason: rotulo,
        );
      }
      expect(_rotuloOrdenar(t, 'vendas'), 'Data da venda ↓');
      final busca = find.descendant(
        of: find.byKey(const Key('busca-vendas')),
        matching: find.byType(CampoBusca),
        matchRoot: true,
      );
      expect(t.widget<CampoBusca>(busca).dica, 'Buscar ticker…');
    });
  });

  group('celular 360', () {
    const tamanho = Size(360, 800);

    testWidgets('Situação compacta, busca expandida e ícones Tipo e Ordenar '
        'com ponto fora do padrão', (t) async {
      await _montar(t, tamanho: tamanho, windows: false);
      final situacao = find.byType(Segmentado<String>);
      expect(situacao, findsOneWidget);
      expect(t.widget<Segmentado<String>>(situacao).compacto, isTrue);
      await t.ensureVisible(find.byKey(const Key('busca-lotes')));
      await t.pumpAndSettle();
      // o título cabe inteiro: Registrar venda vira ícone no celular
      final titulo = t.renderObject<RenderParagraph>(
        find.text('Ativos comprados'),
      );
      expect(titulo.didExceedMaxLines, isFalse);
      expect(find.byTooltip('Registrar venda'), findsOneWidget);
      // busca na linha de baixo, ocupando o que sobra dos ícones
      final busca = find.byKey(const Key('busca-lotes'));
      final tipo = find.byKey(const Key('chip-lotes-tipo'));
      final ordem = find.byKey(const Key('chip-lotes-ordem'));
      expect(t.getTopLeft(busca).dy, greaterThan(t.getBottomLeft(situacao).dy));
      expect(t.getSize(busca).width, greaterThan(150));
      expect(t.getCenter(tipo).dy, moreOrLessEquals(t.getCenter(busca).dy));
      expect(t.getCenter(ordem).dy, moreOrLessEquals(t.getCenter(busca).dy));
      expect(t.getTopRight(ordem).dx, lessThanOrEqualTo(360 - 16 + 0.5));
      expect(find.byTooltip('Tipo'), findsWidgets);
      expect(find.byTooltip(RegExp(r'^Ordenar: ')), findsWidgets);
      expect(_ponto('chip-lotes-tipo'), findsNothing);
      expect(_ponto('chip-lotes-ordem'), findsNothing);

      await t.tap(tipo);
      await t.pumpAndSettle();
      await t.tap(_item('Ação'));
      await t.pumpAndSettle();
      expect(_ponto('chip-lotes-tipo'), findsOneWidget);
      expect(_ponto('chip-lotes-ordem'), findsNothing);

      await t.ensureVisible(ordem);
      await t.pumpAndSettle();
      await _inverter(t, 'lotes');
      expect(_ponto('chip-lotes-ordem'), findsOneWidget);
    });

    testWidgets('Situação na largura da barra e dica curta sem truncar', (
      t,
    ) async {
      await _montar(t, tamanho: tamanho, windows: false);
      await t.ensureVisible(find.byKey(const Key('busca-lotes')));
      await t.pumpAndSettle();
      final situacao = find.byType(Segmentado<String>);
      expect(
        t.getSize(situacao).width,
        moreOrLessEquals(
          t.getSize(find.byType(BarraFiltros)).width,
          epsilon: 1,
        ),
      );
      final busca = find.descendant(
        of: find.byKey(const Key('busca-lotes')),
        matching: find.byType(CampoBusca),
        matchRoot: true,
      );
      expect(t.widget<CampoBusca>(busca).dica, 'Buscar');
      final dica = t.renderObject<RenderParagraph>(find.text('Buscar'));
      expect(dica.didExceedMaxLines, isFalse);
    });

    testWidgets('a lista termina com folga para o + não cobrir o último '
        'cartão', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
      await _montar(t, servicos: s, tamanho: tamanho, windows: false);
      final pos = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (var i = 0; i < 4; i++) {
        pos.jumpTo(pos.maxScrollExtent);
        await t.pumpAndSettle();
      }
      final ultimo = find.byWidgetPredicate(
        (w) => w.key is Key && w.key.toString().contains('cartao-venda-'),
      );
      final fim = t.getBottomLeft(ultimo.last).dy;
      expect(tamanho.height - fim, greaterThanOrEqualTo(88));
      expect(
        fim,
        lessThanOrEqualTo(t.getTopLeft(find.byType(FloatingActionButton)).dy),
      );
    });
  });

  Mes mesComGrupo() {
    final base = mesAbertoExemplo();
    Lote lote(String id, int qtd, double preco, List<Venda> v) => Lote(
      id: id,
      ticker: 'ITUB4',
      tipo: 'Ação',
      dataCompra: '2026-10-02',
      qtd: qtd,
      preco: preco,
      vendas: v,
    );
    return Mes(
      mes: base.mes,
      lotes: [
        ...base.lotes,
        lote('G-A', 10, 30, [
          Venda(id: 'G1.1', data: '2026-10-03', qtd: 10, preco: 31),
        ]),
        lote('G-B', 6, 28, [
          Venda(id: 'G1.2', data: '2026-10-03', qtd: 6, preco: 31),
        ]),
        lote('S-A', 5, 30, [
          Venda(id: 'V9', data: '2026-10-04', qtd: 5, preco: 31),
        ]),
      ],
    );
  }

  testWidgets('grupo aparece numa linha e expande', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(mesComGrupo());
    await _montar(t, servicos: s);
    expect(t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data, '3');
    expect(find.byKey(const Key('linha-G1')), findsOneWidget);
    expect(find.byKey(const Key('linha-G1.1')), findsNothing);
    expect(_textoCelula(t, 'G1', 0), '▸ ITUB4');
    expect(_textoCelula(t, 'G1', 3), '16');
    await t.tap(find.byKey(const Key('linha-G1')));
    // o toque único espera o prazo do duplo toque
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(_textoCelula(t, 'G1', 0), '▾ ITUB4');
    expect(_textoCelula(t, 'G1.1', 3), '10');
    expect(_textoCelula(t, 'G1.2', 3), '6');
  });

  testWidgets('tocar numa linha filha seleciona o grupo', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(mesComGrupo());
    await _montar(t, servicos: s);
    await t.tap(find.byKey(const Key('linha-G1')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('linha-G1.2')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    final controle = Provider.of<ControleApuracao>(
      t.element(find.byKey(const Key('tabela-vendas'))),
      listen: false,
    );
    expect(controle.vendaSelecionada, 'G1');
  });

  testWidgets('cartão Lucro bruto conta grupos como a lista de vendas', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(mesComGrupo());
    await _montar(t, servicos: s);
    expect(t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data, '3');
    expect(find.text('3 vendas no mês'), findsOneWidget);
  });

  testWidgets('venda simples continua igual', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(mesComGrupo());
    await _montar(t, servicos: s);
    expect(_textoCelula(t, 'V9', 0), 'ITUB4');
    expect(_textoCelula(t, 'V9', 3), '5');
  });

  testWidgets('compacto: grupo num cartão com as compras ao expandir', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(mesComGrupo());
    await _montar(t, servicos: s, tamanho: _celular, windows: false);
    expect(find.byKey(const Key('cartao-venda-G1')), findsOneWidget);
    expect(find.byKey(const Key('parte-venda-G1.1')), findsNothing);
    await t.tap(find.byKey(const Key('expandir-venda-G1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('parte-venda-G1.1')), findsOneWidget);
    expect(find.byKey(const Key('parte-venda-G1.2')), findsOneWidget);
    expect(find.byKey(const Key('expandir-venda-V9')), findsNothing);
  });

  testWidgets('compacto: cartões com menu de item nas compras e vendas', (
    t,
  ) async {
    final s = await _montar(t, tamanho: _celular, windows: false);
    expect(find.text('Ativos comprados'), findsOneWidget);
    expect(find.text('Vendas do mês'), findsOneWidget);
    expect(find.text('Restante: 60'), findsOneWidget);

    await t.tap(find.byKey(const Key('menu-lote-L1')));
    await t.pumpAndSettle();
    expect(_item('Registrar venda'), findsOneWidget);
    expect(_item('Editar compra'), findsOneWidget);
    expect(_item('Excluir compra'), findsOneWidget);
    await t.tap(_item('Excluir compra'));
    await t.pumpAndSettle();
    expect(_noDialogo('Excluir compra'), findsOneWidget);
    expect(_noDialogo('Excluir PETR4 e todas as vendas dele?'), findsOneWidget);
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('excluirCompra(2026-10, L1)'));

    await t.tap(find.byKey(const Key('menu-venda-V1')));
    await t.pumpAndSettle();
    expect(_item('Editar venda'), findsOneWidget);
    await t.tap(_item('Excluir venda'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('excluirVenda(2026-10, V1)'));
  });

  testWidgets('compacto: compra sem menu de Registrar venda quando vendida', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
    await _montar(t, servicos: s, tamanho: _celular);
    await t.tap(find.byKey(const Key('menu-lote-L4')));
    await t.pumpAndSettle();
    expect(_item('Registrar venda'), findsNothing);
    expect(_item('Editar compra'), findsOneWidget);
  });

  testWidgets('listas vazias mostram a mensagem do Python', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10'));
    await _montar(t, servicos: s);
    expect(
      find.text(
        'Nenhum ativo neste mês. Clique em  +  Novo ativo  para '
        'começar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nenhuma venda registrada neste mês.'), findsOneWidget);
  });

  testWidgets('cotação atual: "…" antes de chegar, preço depois, "—" em '
      'vendidos; ▲ verde e ▼ vermelho', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(_mesComVendido());
    final resposta = Completer<Map<String, double?>>();
    s.precosFn = (_) => resposta.future;
    await _montar(t, servicos: s);
    expect(_chamadasA(s, 'precosCarteira(AAPL34,PETR4,VALE3)'), 1);
    expect(_textoCelula(t, 'L1', 5), '…');
    expect(_textoCelula(t, 'L2', 5), '…');
    expect(_textoCelula(t, 'L4', 5), '—');
    expect(_textoCelula(t, 'L1', 6), '—');

    resposta.complete({'PETR4': 40.0, 'VALE3': 50.0, 'AAPL34': null});
    await t.pumpAndSettle();
    expect(_textoCelula(t, 'L1', 5), 'R\$ 40,00');
    expect(_textoCelula(t, 'L3', 5), '—');
    expect(_textoCelula(t, 'L4', 5), '—');
    expect(_textoCelula(t, 'L1', 6), startsWith('▲ +R\$ 450,00'));
    expect(_textoCelula(t, 'L2', 6), startsWith('▼ '));
    final cores = CoresApp.de(t.element(find.byType(TelaApuracao)));
    expect(t.widget<Text>(_celula('L1', 6)).style!.color, cores.alta);
    expect(t.widget<Text>(_celula('L2', 6)).style!.color, cores.queda);
  });

  testWidgets('cotações só se repetem a cada 60 s com a aba visível e meus '
      'dados', (t) async {
    final s = ServicosFalsos();
    s.precos = {'PETR4': 40, 'VALE3': 50, 'AAPL34': 60};
    await _montar(t, servicos: s);
    expect(_chamadasA(s, 'precosCarteira'), 1);
    await t.pump(const Duration(seconds: 60));
    expect(_chamadasA(s, 'precosCarteira'), 2);

    _estado(t).irPara(Aba.caixa);
    await t.pump();
    await t.pump(const Duration(seconds: 60));
    expect(_chamadasA(s, 'precosCarteira'), 2);

    _estado(t).irPara(Aba.apuracao);
    await t.pump();
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    final antes = _chamadasA(s, 'precosCarteira');
    await t.pump(const Duration(seconds: 60));
    expect(_chamadasA(s, 'precosCarteira'), antes);
  });

  testWidgets('falha das cotações vira "—", não "…" para sempre', (t) async {
    final s = ServicosFalsos();
    s.erros['precosCarteira'] = StateError('sem rede');
    await _montar(t, servicos: s);
    expect(_textoCelula(t, 'L1', 5), '—');
    expect(find.textContaining('Exception'), findsNothing);
  });

  for (final (nome, tamanho) in [
    ('expandido', const Size(1366, 768)),
    ('compacto', const Size(360, 800)),
  ]) {
    testWidgets('lista rola enquanto as cotações da carteira carregam '
        '($nome)', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(
          mes: '2026-10',
          lotes: [
            for (var i = 0; i < 60; i++)
              Lote(
                id: 'M$i',
                ticker: 'TICK${i.toString().padLeft(2, '0')}',
                tipo: 'Ação',
                dataCompra: '2026-10-05',
                qtd: 10,
                preco: 10.0 + i,
              ),
          ],
        ),
      );
      final pendente = Completer<Map<String, double?>>();
      s.precosFn = (_) => pendente.future;
      await montarApp(
        t,
        servicos: s,
        tamanho: tamanho,
        tela: const TelaApuracao(
          conteudo: listasApuracao,
          sliversCompactos: listasSliversApuracao,
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(_chamadasA(s, 'precosCarteira'), 1);

      final alvo = nome == 'expandido'
          ? find.descendant(
              of: find.byKey(const Key('tabela-lotes')),
              matching: find.byType(Scrollable),
            )
          : find.byType(Scrollable).first;
      final antes = t.state<ScrollableState>(alvo).position.pixels;
      await t.drag(alvo, const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 400));
      expect(
        t.state<ScrollableState>(alvo).position.pixels,
        greaterThan(antes),
      );
      expect(pendente.isCompleted, isFalse);
      // o corpo é lazy: nem todas as 60 linhas existem
      expect(find.byType(Text).evaluate().length, lessThan(900));
    });
  }

  testWidgets('mês fechado, amigo ou erro de leitura: nada de gravar', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10', fechado: true, lotes: mesAbertoExemplo().lotes),
    );
    await _montar(t, servicos: s);
    for (final b in [
      'Novo ativo',
      'Registrar venda',
      'Editar',
      'Excluir',
      'Editar venda',
      'Excluir venda',
    ]) {
      expect(_habilitado(t, b), isFalse, reason: b);
    }
    await _duploToque(t, find.byKey(const Key('linha-L2')));
    expect(find.text('Registrar venda'), findsOneWidget); // só o botão
    expect(_chamadasA(s, 'registrar'), 0);
    expect(_chamadasA(s, 'excluir'), 0);
  });

  testWidgets('visão de amigo: botões desabilitados e sem gravar', (t) async {
    final s = await _montar(t);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    for (final b in ['Novo ativo', 'Excluir', 'Editar venda']) {
      expect(_habilitado(t, b), isFalse, reason: b);
    }
    await _duploToque(t, find.byKey(const Key('linha-L2')));
    expect(find.byType(Dialog), findsNothing);
    expect(_chamadasA(s, 'excluir'), 0);
  });

  testWidgets('compacto: mês fechado não tem menu de item', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10', fechado: true, lotes: mesAbertoExemplo().lotes),
    );
    await _montar(t, servicos: s, tamanho: _celular);
    expect(find.text('VALE3'), findsOneWidget);
    expect(find.byKey(const Key('menu-lote-L2')), findsNothing);
  });

  testWidgets('erro de leitura do mês: listas vazias e sem botões ativos', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10'),
      erroLeitura: 'Mês ilegível.',
    );
    await _montar(t, servicos: s);
    expect(_habilitado(t, 'Novo ativo'), isFalse);
  });

  testWidgets('seleção invisível pelo filtro some: Excluir avisa e não chama '
      'o serviço', (t) async {
    final s = await _montar(t);
    await _selecionar(t, 'L2'); // VALE3
    await t.enterText(find.byKey(const Key('busca-lotes')), 'petr');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('linha-L2')), findsNothing);
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    expect(
      _noDialogo('Selecione um ativo na tabela de ativos comprados.'),
      findsOneWidget,
    );
    expect(_chamadasA(s, 'excluirCompra'), 0);
  });

  testWidgets('venda marcada e escondida pelo filtro some da seleção', (
    t,
  ) async {
    final s = await _montar(t);
    await _selecionar(t, 'V1');
    await t.tap(find.byKey(const Key('chip-vendas-operacao')));
    await t.pumpAndSettle();
    await t.tap(_item('Day trade'));
    await t.pumpAndSettle();
    await t.tap(_botao('Excluir venda'));
    await t.pumpAndSettle();
    expect(
      _noDialogo('Selecione uma venda na tabela de vendas.'),
      findsOneWidget,
    );
    expect(_chamadasA(s, 'excluirVenda'), 0);
  });

  testWidgets('expandido: o Ordenar vale depois do clique no título', (
    t,
  ) async {
    await _montar(t);
    await t.tap(_tituloLotes('TICKER ↕'));
    await t.pumpAndSettle();
    expect(_y(t, 'AAPL34') < _y(t, 'PETR4'), isTrue);
    await t.tap(find.byKey(const Key('chip-lotes-ordem')));
    await t.pumpAndSettle();
    await t.tap(
      _item('Preço de compra'),
    ); // PETR4 32,5 < AAPL34 55 < VALE3 60,1
    await t.pumpAndSettle();
    expect(_tituloLotes('TICKER ↕'), findsOneWidget);
    expect(_y(t, 'PETR4') < _y(t, 'AAPL34'), isTrue);
    expect(_y(t, 'AAPL34') < _y(t, 'VALE3'), isTrue);
    await _inverter(t, 'lotes');
    expect(_y(t, 'VALE3') < _y(t, 'AAPL34'), isTrue);
  });

  testWidgets('compacto: 1000 compras montam só os cartões à vista e a '
      'rolagem chega ao fim', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(
        mes: '2026-10',
        lotes: [
          for (var i = 0; i < 1000; i++)
            Lote(
              id: 'M$i',
              ticker: 'TICK$i',
              tipo: 'Ação',
              dataCompra: '2026-10-05',
              qtd: 10,
              preco: 10,
            ),
        ],
      ),
    );
    await _montar(t, servicos: s, tamanho: const Size(360, 800));
    int cartoes() => find
        .byWidgetPredicate(
          (w) => w.key is Key && w.key.toString().contains('cartao-lote-'),
        )
        .evaluate()
        .length;
    expect(cartoes(), lessThan(40));
    final pos = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    pos.jumpTo(1500);
    await t.pump();
    expect(cartoes(), inInclusiveRange(1, 39));
    for (var i = 0; i < 6; i++) {
      pos.jumpTo(pos.maxScrollExtent);
      await t.pump();
    }
    expect(cartoes(), lessThan(40));
    expect(find.byKey(const Key('cartao-lote-M999')), findsOneWidget);
    expect(find.text('Nenhuma venda registrada neste mês.'), findsOneWidget);
  });

  testWidgets('exclusão pendente bloqueia outra ação de editar ou excluir', (
    t,
  ) async {
    final s = ServicosFalsos();
    final espera = Completer<void>();
    s.esperaExclusao = espera.future;
    await _montar(t, servicos: s);
    await _selecionar(t, 'L2');
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(_chamadasA(s, 'excluirCompra'), 1);
    expect(_habilitado(t, 'Excluir'), isFalse);
    expect(_habilitado(t, 'Editar'), isFalse);
    final controle = Provider.of<ControleApuracao>(
      t.element(find.byType(ListaLotes)),
      listen: false,
    );
    await controle.excluirLote(t.element(find.byType(ListaLotes)));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    espera.complete();
    await t.pumpAndSettle();
    expect(_habilitado(t, 'Excluir'), isTrue);
  });

  Future<Completer<void>> pendenteNoCelular(
    WidgetTester t,
    ServicosFalsos s,
  ) async {
    final espera = Completer<void>();
    s.esperaExclusao = espera.future;
    await _montar(t, servicos: s, tamanho: _celular, windows: false);
    await t.tap(find.byKey(const Key('menu-lote-L2')));
    await t.pumpAndSettle();
    await t.tap(_item('Excluir compra'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    expect(_chamadasA(s, 'excluirCompra'), 1);
    return espera;
  }

  testWidgets('exclusão pendente desabilita FAB, nova compra e menus de item', (
    t,
  ) async {
    final s = ServicosFalsos();
    final espera = await pendenteNoCelular(t, s);
    expect(
      t
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('menu-lote-L1')),
          )
          .enabled,
      isFalse,
    );
    expect(
      t
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('menu-venda-V1')),
          )
          .enabled,
      isFalse,
    );
    final ctx = t.element(find.byType(CustomScrollView));
    await Provider.of<ControleApuracao>(ctx, listen: false).novaCompra(ctx);
    await t.pumpAndSettle();
    expect(find.text('Novo ativo'), findsNothing);
    espera.complete();
    await t.pumpAndSettle();
    expect(
      t
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('confirmação negada ou exclusão com erro liberam o Excluir', (
    t,
  ) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s);
    await _selecionar(t, 'L2');
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(_habilitado(t, 'Excluir'), isTrue);
    expect(_chamadasA(s, 'excluirCompra'), 0);

    s.erros['excluirCompra'] = ErroValidacao('Mês fechado.');
    await t.tap(_botao('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir').last);
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(_habilitado(t, 'Excluir'), isTrue);
    expect(_habilitado(t, 'Novo ativo'), isTrue);
  });
}
