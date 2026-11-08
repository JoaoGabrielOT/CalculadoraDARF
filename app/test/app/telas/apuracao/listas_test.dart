import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/lista_lotes.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
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

Finder _botao(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _habilitado(WidgetTester t, String texto) =>
    t.widget<ButtonStyleButton>(_botao(texto)).onPressed != null;

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

  testWidgets('expandido: tabela de ativos com as 11 colunas', (t) async {
    await _montar(t);
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
    await t.tap(_botao('+  Novo ativo'));
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

      // busca
      await t.tap(find.byTooltip('Buscar ticker').first);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('busca-lotes')), 'vale');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('contagem-lotes')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data,
        '1/3',
      );
      expect(find.text('AAPL34'), findsNothing);
      expect(find.text('Limpar'), findsWidgets);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data, '3');
      expect(find.byKey(const Key('busca-lotes')), findsNothing);

      // tipo
      await t.tap(find.byKey(const Key('chip-lotes-tipo')));
      await t.pumpAndSettle();
      await t.tap(_item('BDR'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-lotes'))).data,
        '1/3',
      );
      expect(find.text('AAPL34'), findsOneWidget);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();

      // ordem por ticker (crescente) e inversão
      await t.tap(find.byKey(const Key('chip-lotes-ordem')));
      await t.pumpAndSettle();
      await t.tap(_item('Ticker'));
      await t.pumpAndSettle();
      expect(_y(t, 'AAPL34') < _y(t, 'PETR4'), isTrue);
      expect(_y(t, 'PETR4') < _y(t, 'VALE3'), isTrue);
      await t.tap(find.byKey(const Key('inverter-lotes')));
      await t.pumpAndSettle();
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
      await t.tap(_item('Day trade'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data,
        '0/2',
      );
      expect(find.text('Nenhuma venda para esse filtro.'), findsOneWidget);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('chip-vendas-tipo')));
      await t.pumpAndSettle();
      await t.tap(_item('BDR'));
      await t.pumpAndSettle();
      expect(find.text('Nenhuma venda para esse filtro.'), findsOneWidget);
      await t.tap(find.text('Limpar').first);
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('Buscar ticker').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('busca-vendas')), 'itub');
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.byKey(const Key('contagem-vendas'))).data,
        '1/2',
      );
    });
  }

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
      '+  Novo ativo',
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
    for (final b in ['+  Novo ativo', 'Excluir', 'Editar venda']) {
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
    expect(_habilitado(t, '+  Novo ativo'), isFalse);
  });

  testWidgets('seleção invisível pelo filtro some: Excluir avisa e não chama '
      'o serviço', (t) async {
    final s = await _montar(t);
    await _selecionar(t, 'L2'); // VALE3
    await t.tap(find.byTooltip('Buscar ticker').first);
    await t.pumpAndSettle();
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

  testWidgets('expandido: o chip Ordenar vale depois do clique no título', (
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
    await t.tap(find.byKey(const Key('inverter-lotes')));
    await t.pumpAndSettle();
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
    expect(_habilitado(t, '+  Novo ativo'), isTrue);
  });
}
