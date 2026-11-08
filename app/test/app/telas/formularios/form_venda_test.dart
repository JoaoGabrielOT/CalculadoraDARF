import 'dart:async';

import 'package:calculadoradarf/app/componentes/campo_data.dart';
import 'package:calculadoradarf/app/regras/formularios.dart'
    show textoEscolhaDasCompras, textoEscolhaDasComprasPorCompra;
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
import 'package:calculadoradarf/app/telas/formularios/form_venda.dart'
    show ModoVenda;
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/dados_exemplo.dart';
import '../../apoio/servicos_falsos.dart';

VisaoMes _visao(ServicosFalsos s) => s.visoes['2026-10']!;

Future<ResultadoForm<VendaRegistrada>> _abrir(
  WidgetTester t,
  ServicosFalsos s, {
  Lote? lote,
  String ticker = '',
  (Lote, Venda)? editar,
  Size tamanho = const Size(1366, 768),
}) => abrirNoTeste<VendaRegistrada>(
  t,
  s,
  (c) =>
      abrirFormVenda(c, _visao(s), lote: lote, ticker: ticker, editar: editar),
  tamanho: tamanho,
);

Finder get _campoData => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Data',
);

Lote _l(String id) =>
    _visao(ServicosFalsos()).dados.lotes.firstWhere((l) => l.id == id);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets(
    'ao escolher o ticker preenche a quantidade com o disponível e a data',
    (t) async {
      final s = ServicosFalsos();
      await _abrir(t, s);
      expect(find.text('Registrar venda'), findsOneWidget);
      expect(find.text('Mês 10/2026'), findsOneWidget);
      expect(find.text('Em carteira'), findsOneWidget);
      expect(find.text('Escolha um ticker'), findsOneWidget);
      await t.tap(find.text('PETR4'));
      await t.pump();
      expect(campoTexto(t, 'ticker').controller!.text, 'PETR4');
      expect(find.text('Quantidade (máx. 60)'), findsOneWidget);
      expect(campoTexto(t, 'qtd').controller!.text, '60');
      expect(find.text('28/10/2026'), findsOneWidget);

      await t.enterText(campo('ticker'), 'xxxx1');
      await t.pump();
      expect(
        find.text('Nenhuma compra em aberto desse ticker'),
        findsOneWidget,
      );
      await t.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('venda retroativa: rótulos repetidos de compra ganham o sufixo '
      '(2)', (t) async {
    final s = ServicosFalsos();
    Lote igual(String id) => Lote(
      id: id,
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-07-05',
      qtd: 10,
      preco: 30,
    );
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10', lotes: [igual('A'), igual('B')]),
    );
    await _abrir(t, s, ticker: 'PETR4');
    await t.enterText(_campoData, '15/09/2026');
    await t.pump();
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    expect(find.text('05/07/2026  ·  R\$ 30,00  ·  10 disp.'), findsWidgets);
    expect(
      find.text('05/07/2026  ·  R\$ 30,00  ·  10 disp. (2)'),
      findsOneWidget,
    );
    await t.tap(find.text('05/07/2026  ·  R\$ 30,00  ·  10 disp. (2)'));
    await t.pumpAndSettle();
    await t.enterText(campo('preco'), '31');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimaVenda?.loteId, 'B');
  });

  testWidgets(
    'Sugerir preço: preço chega e mostra a origem; preço digitado não é '
    'sobrescrito; resposta atrasada de um pedido antigo é ignorada',
    (t) async {
      final s = ServicosFalsos();
      final pedidos = <String, Completer<(double, String)>>{};
      s.precoVendaFn = (ticker, dia) =>
          (pedidos[dia] = Completer<(double, String)>()).future;
      await _abrir(t, s, lote: _l('L2'));
      expect(find.text('Buscando cotação…'), findsOneWidget);
      expect(s.chamadas, contains('precoVenda(VALE3, 2026-10-28)'));

      // outro dia: novo pedido; a resposta do antigo chega depois e é ignorada
      await t.enterText(_campoData, '27/10/2026');
      await t.pump();
      expect(s.chamadas, contains('precoVenda(VALE3, 2026-10-27)'));
      pedidos['2026-10-28']!.complete((10.0, 'Cotação atual'));
      await t.pump();
      expect(campoTexto(t, 'preco').controller!.text, '');
      expect(find.text('Buscando cotação…'), findsOneWidget);
      pedidos['2026-10-27']!.complete((11.5, 'Fechamento de 27/10'));
      await t.pump();
      expect(campoTexto(t, 'preco').controller!.text, '11,50');
      expect(find.text('Fechamento de 27/10 · pode alterar'), findsOneWidget);

      // preço digitado pelo usuário vale mais que uma sugestão nova
      await t.enterText(campo('preco'), '12,00');
      await t.enterText(_campoData, '26/10/2026');
      await t.pump();
      expect(s.chamadas.where((c) => c.startsWith('precoVenda')).length, 2);
      expect(campoTexto(t, 'preco').controller!.text, '12,00');
    },
  );

  testWidgets('preço digitado enquanto a cotação carrega não é sobrescrito', (
    t,
  ) async {
    final s = ServicosFalsos();
    final c = Completer<(double, String)>();
    s.precoVendaFn = (_, _) => c.future;
    await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '9,99');
    c.complete((10.0, 'Cotação atual'));
    await t.pump();
    expect(campoTexto(t, 'preco').controller!.text, '9,99');
  });

  testWidgets('cotação que falha pede o preço', (t) async {
    final s = ServicosFalsos()..erros['precoVenda'] = Exception('rede');
    await _abrir(t, s, lote: _l('L2'));
    await t.pump();
    expect(
      find.text('Não foi possível buscar a cotação. Informe o preço.'),
      findsOneWidget,
    );
  });

  testWidgets('a interface responde enquanto o preço sugerido não chega', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.precoVendaFn = (_, _) => Completer<(double, String)>().future;
    await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '10');
    await t.enterText(campo('sel-L2'), '50');
    await t.enterText(campo('qtd'), '50');
    await t.pump();
    expect(find.text('Buscando cotação…'), findsOneWidget);
    expect(find.text('Selecionado 50 de 50'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('venda no dia da compra mostra a parte de day trade da prévia', (
    t,
  ) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      Mes(
        mes: '2026-10',
        lotes: [
          Lote(
            id: 'D',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: hojeExemplo,
            qtd: 10,
            preco: 30,
          ),
        ],
      ),
    );
    s.previaResp = const PreviaVenda(
      linhas: [],
      gerencial: 5,
      fiscal: 5,
      qtdDt: 10,
      qtdComum: 0,
    );
    await _abrir(t, s, ticker: 'PETR4');
    await t.enterText(campo('preco'), '31');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Day trade: 10 ações; comum: 0 ações'), findsOneWidget);
  });

  testWidgets('retroativa mantém o resumo financeiro de uma compra', (t) async {
    final s = ServicosFalsos();
    final antigo = Lote(
      id: 'R1',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-07-10',
      qtd: 100,
      preco: 50,
    );
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [antigo]));
    await _abrir(t, s, ticker: 'VALE3');
    await t.enterText(_campoData, '15/09/2026');
    await t.enterText(campo('preco'), '55');
    await t.pump();
    expect(find.text('R\$ 5.500,00'), findsOneWidget);
    expect(find.textContaining('Swing trade'), findsOneWidget);
  });

  testWidgets('datas: só o mês aberto e os meses anteriores fora de '
      'mesesSemVendaRetroativa; edição só o mês aberto', (t) async {
    final s = ServicosFalsos()..semVendaRetroativa = {'2026-08'};
    final antigo = Lote(
      id: 'R1',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-07-10',
      qtd: 100,
      preco: 50,
    );
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [antigo]));
    await _abrir(t, s, ticker: 'VALE3');
    expect(s.chamadas, contains('mesesSemVendaRetroativa(2026-10)'));
    final permitido = t.widget<CampoData>(find.byType(CampoData)).permitido!;
    expect(permitido('2026-10-02'), isTrue);
    expect(permitido('2026-09-15'), isTrue);
    expect(permitido('2026-08-20'), isFalse);
    expect(permitido('2026-07-20'), isTrue);
  });

  testWidgets('datas na edição: só o mês aberto, sem consultar os meses', (
    t,
  ) async {
    final s2 = ServicosFalsos();
    final lote = _l('L1');
    await _abrir(t, s2, editar: (lote, lote.vendas.first));
    expect(
      s2.chamadas.any((c) => c.startsWith('mesesSemVendaRetroativa')),
      isFalse,
    );
    final p2 = t.widget<CampoData>(find.byType(CampoData)).permitido!;
    expect(p2('2026-10-10'), isTrue);
    expect(p2('2026-09-15'), isFalse);
  });

  testWidgets('venda retroativa mostra o aviso devolvido', (t) async {
    final s = ServicosFalsos();
    final antigo = Lote(
      id: 'R1',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-07-10',
      qtd: 100,
      preco: 50,
    );
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [antigo]));
    s.vendaRegistrada = VendaRegistrada(
      visao: s.visoes['2026-10']!,
      mesGravado: '2026-09',
      aviso: 'A venda foi gravada em 09/2026.',
    );
    s.reservadoMetas = 0;
    final r = await _abrir(t, s, ticker: 'VALE3');
    await t.enterText(_campoData, '15/09/2026');
    await t.enterText(campo('preco'), '55');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('reservadoEmMetas(R1)'));
    expect(find.text('Venda registrada'), findsOneWidget);
    expect(find.text('A venda foi gravada em 09/2026.'), findsOneWidget);
    expect(r.concluido, isFalse);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(r.valor?.mesGravado, '2026-09');
  });

  testWidgets('meta ativa na compra recusa a venda retroativa', (t) async {
    final s = ServicosFalsos()..reservadoMetas = 90;
    final antigo = Lote(
      id: 'R1',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-07-10',
      qtd: 100,
      preco: 50,
    );
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [antigo]));
    await _abrir(t, s, ticker: 'VALE3');
    await t.enterText(_campoData, '15/09/2026');
    await t.enterText(campo('preco'), '55');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.textContaining('Quantidade livre: 10.'), findsOneWidget);
    expect(s.ultimaVenda, isNull);
  });

  testWidgets('validações da venda usam as mensagens do Python', (t) async {
    final s = ServicosFalsos();
    await _abrir(t, s);
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(
      find.text('Escolha o ticker e a compra que foi vendida.'),
      findsOneWidget,
    );
    await t.tap(find.text('VALE3'));
    await t.pump();
    await t.enterText(campo('qtd'), '999');
    await t.enterText(campo('preco'), '10');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(
      find.text(
        'Quantidade indisponível: só há 200 ações de VALE3 nessa data.',
      ),
      findsWidgets,
    );
    await t.enterText(_campoData, '');
    await t.enterText(campo('qtd'), '10');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Selecione a data da venda.'), findsOneWidget);
    expect(s.ultimaVendaQtd, isNull);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('salvar registra a venda e devolve o resultado', (t) async {
    final s = ServicosFalsos();
    final r = await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '65,5');
    await t.enterText(campo('qtd'), '50');
    await t.enterText(campo('sel-L2'), '50');
    await t.pump();
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    final v = s.ultimaVendaQtd!;
    expect(v.ticker, 'VALE3');
    expect(v.data, hojeExemplo);
    expect(v.qtd, 50);
    expect(v.preco, 65.5);
    expect(v.selecao, [('L2', 50)]);
    expect(v.grupo, startsWith('grupo-'));
    expect(s.chamadas, contains('novoGrupoVenda()'));
    expect(r.valor?.visao.mes, '2026-10');
  });

  testWidgets('editar: compra e ticker fixos, preenche a venda e salva com '
      'editarVenda', (t) async {
    final s = ServicosFalsos();
    final lote = _l('L1');
    final r = await _abrir(t, s, editar: (lote, lote.vendas.first));
    expect(find.text('Editar venda'), findsOneWidget);
    expect(find.text('Em carteira'), findsNothing);
    expect(campoTexto(t, 'ticker').enabled, isFalse);
    expect(campoTexto(t, 'qtd').controller!.text, '40');
    expect(campoTexto(t, 'preco').controller!.text, '35,00');
    expect(find.text('20/10/2026'), findsOneWidget);
    expect(find.text('Quantidade (máx. 100)'), findsOneWidget);
    // editar não busca cotação
    expect(s.chamadas.any((c) => c.startsWith('precoVenda')), isFalse);
    await t.enterText(campo('qtd'), '50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.chamadas.last, 'editarVenda(2026-10, V1, 2026-10-20, 50)');
    expect(r.valor, isNotNull);
  });

  testWidgets('sem compras em aberto avisa em vez de abrir', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10'));
    final r = await _abrir(t, s);
    expect(find.text('Não há compras em aberto neste mês.'), findsOneWidget);
    expect(find.text('Registrar venda'), findsOneWidget); // título do aviso
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(r.concluido, isTrue);
    expect(r.valor, isNull);
  });

  testWidgets('erro do serviço aparece no rodapé sem fechar', (t) async {
    final s = ServicosFalsos()
      ..erros['registrarVendaQtd'] = ErroValidacao(
        'A compra foi alterada em outro aparelho. Abra a venda novamente.',
      );
    final r = await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '10');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'A compra foi alterada em outro aparelho. Abra a venda novamente.',
      ),
      findsOneWidget,
    );
    expect(r.concluido, isFalse);
  });

  testWidgets('compacto: tela cheia', (t) async {
    await _abrir(
      t,
      ServicosFalsos(),
      lote: _l('L2'),
      tamanho: const Size(360, 800),
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('editar com preço de 8 casas chega intacto a editarVenda', (
    t,
  ) async {
    final s = ServicosFalsos();
    final lote = Lote(
      id: 'P1',
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-10-05',
      qtd: 100,
      preco: 30,
      vendas: [
        Venda(id: 'PV', data: '2026-10-20', qtd: 40, preco: 32.12345678),
      ],
    );
    await _abrir(t, s, editar: (lote, lote.vendas.first));
    expect(campoTexto(t, 'preco').controller!.text, '32,12345678');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimaVenda?.preco, 32.12345678);
    expect(s.ultimaVenda?.qtd, 40);
  });

  testWidgets('duplo toque com o serviço pendente faz uma única chamada', (
    t,
  ) async {
    final s = ServicosFalsos();
    final espera = Completer<void>();
    s.esperaGravacao = espera.future;
    await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '10');
    await t.tap(find.text('Salvar'));
    await t.tap(find.text('Salvar'), warnIfMissed: false);
    await t.pump();
    expect(
      s.chamadas.where((c) => c.startsWith('registrarVendaQtd')).length,
      1,
    );
    espera.complete();
    await t.pumpAndSettle();
  });

  testWidgets('quantidade e preço são lidos antes do await e os campos ficam '
      'sem edição enquanto grava', (t) async {
    final s = ServicosFalsos();
    final espera = Completer<void>();
    s.esperaReserva = espera.future;
    final antigo = Lote(
      id: 'R1',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-07-10',
      qtd: 100,
      preco: 50,
    );
    s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [antigo]));
    await _abrir(t, s, ticker: 'VALE3');
    await t.enterText(_campoData, '15/09/2026');
    await t.enterText(campo('qtd'), '10');
    await t.enterText(campo('preco'), '55');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(campoTexto(t, 'qtd').readOnly, isTrue);
    expect(campoTexto(t, 'preco').readOnly, isTrue);
    expect(campoTexto(t, 'ticker').readOnly, isTrue);
    campoTexto(t, 'qtd').controller!.text = '99';
    campoTexto(t, 'preco').controller!.text = '1';
    espera.complete();
    await t.pumpAndSettle();
    expect(s.ultimaVenda?.qtd, 10);
    expect(s.ultimaVenda?.preco, 55);
  });

  group('venda por quantidade', () {
    Lote compra(
      String id,
      String data,
      int qtd,
      double preco, {
      List<Venda>? vendas,
    }) => Lote(
      id: id,
      ticker: 'BBAS3',
      tipo: 'Ação',
      dataCompra: data,
      qtd: qtd,
      preco: preco,
      vendas: vendas,
    );

    ServicosFalsos servicos(List<Lote> lotes) {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: lotes));
      return s;
    }

    final b1 = compra('B1', '2026-10-02', 100, 30);
    final b2 = compra('B2', '2026-10-05', 100, 20);

    ModoVenda? modo(WidgetTester t) {
      final sel = t
          .widget<SegmentedButton<ModoVenda>>(
            find.byKey(const ValueKey('modo-venda')),
          )
          .selected;
      return sel.isEmpty ? null : sel.first;
    }

    VoidCallback? salvar(WidgetTester t) => t
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'))
        .onPressed;

    int chamadasDe(ServicosFalsos s, String nome) =>
        s.chamadas.where((c) => c.startsWith('$nome(')).length;

    const meio = Duration(milliseconds: 400);

    testWidgets('caminho geral abre em Automático com a regra explicada', (
      t,
    ) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      expect(find.text('Automático'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
      expect(modo(t), ModoVenda.automatico);
      expect(
        find.text(
          'Primeiro as compras de hoje (day trade, regra da Receita). Depois '
          'as de menor custo por ação, incluindo as taxas de compra; em '
          'empate, a mais antiga.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sel-B1')), findsNothing);
      await t.pump(meio);
    });

    testWidgets(
      'duplo clique num lote abre em Manual com o lote selecionado e o ativo '
      'preenchido',
      (t) async {
        final s = servicos([b1, b2]);
        await _abrir(t, s, lote: b2);
        expect(modo(t), ModoVenda.manual);
        expect(campoTexto(t, 'ticker').controller!.text, 'BBAS3');
        expect(campoTexto(t, 'qtd').controller!.text, '100');
        expect(campoTexto(t, 'sel-B2').controller!.text, '100');
        expect(campoTexto(t, 'sel-B1').controller!.text, '');
        expect(find.text('Selecionado 100 de 100'), findsOneWidget);
        expect(campoTexto(t, 'preco').focusNode!.hasFocus, isTrue);
        await t.pump(meio);
      },
    );

    testWidgets('alternar modos não grava e o Manual parte da seleção '
        'automática', (t) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.enterText(campo('preco'), '35');
      await t.pump();
      await t.tap(find.text('Manual'));
      await t.pump();
      expect(modo(t), ModoVenda.manual);
      // a compra mais barata (B2) primeiro, o resto na seguinte
      expect(campoTexto(t, 'sel-B2').controller!.text, '100');
      expect(campoTexto(t, 'sel-B1').controller!.text, '50');
      expect(find.text('Selecionado 150 de 150'), findsOneWidget);
      await t.tap(find.text('Automático'));
      await t.pump();
      await t.tap(find.text('Manual'));
      await t.pump(meio);
      expect(modo(t), ModoVenda.manual);
      expect(chamadasDe(s, 'registrarVendaQtd'), 0);
      expect(chamadasDe(s, 'editarGrupoVenda'), 0);
      expect(s.ultimaVendaQtd, isNull);
    });

    testWidgets('manual mostra data, quantidade original, disponível e custo '
        'e limita o campo ao disponível', (t) async {
      final parcial = compra(
        'P1',
        '2026-10-02',
        100,
        30,
        vendas: [Venda(id: 'PV', data: '2026-10-10', qtd: 20, preco: 31)],
      );
      final s = servicos([parcial, b2]);
      await _abrir(t, s, lote: parcial);
      final custo = brl(custoUnitarioEfetivo(parcial));
      expect(
        find.text('02/10/2026  ·  original 100  ·  disp. 80  ·  custo $custo'),
        findsOneWidget,
      );
      expect(
        find.text(
          '05/10/2026  ·  original 100  ·  disp. 100  ·  custo '
          '${brl(custoUnitarioEfetivo(b2))}',
        ),
        findsOneWidget,
      );
      await t.enterText(campo('sel-P1'), '999');
      await t.pump();
      expect(campoTexto(t, 'sel-P1').controller!.text, '80');
      await t.pump(meio);
    });

    testWidgets('compras do dia aparecem travadas e entram primeiro', (
      t,
    ) async {
      final hoje = compra('D1', hojeExemplo, 10, 40);
      final s = servicos([b1, hoje]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '50');
      await t.tap(find.text('Manual'));
      await t.pump();
      expect(campoTexto(t, 'sel-D1').enabled, isFalse);
      expect(campoTexto(t, 'sel-D1').controller!.text, '10');
      expect(campoTexto(t, 'sel-B1').controller!.text, '40');
      expect(find.text('Compra de hoje (day trade)'), findsOneWidget);
      await t.pump(meio);
    });

    testWidgets('Confirmar só habilita com a soma exata', (t) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.tap(find.text('Manual'));
      await t.pump();
      expect(salvar(t), isNotNull);
      await t.enterText(campo('sel-B1'), '40');
      await t.pump();
      expect(find.text('Selecionado 140 de 150'), findsOneWidget);
      expect(salvar(t), isNull);
      expect(
        find.text(
          'A soma das compras escolhidas (140) é diferente da quantidade da '
          'venda (150).',
        ),
        findsOneWidget,
      );
      await t.enterText(campo('sel-B1'), '50');
      await t.pump();
      expect(salvar(t), isNotNull);
      await t.pump(meio);
    });

    testWidgets('manual envia a seleção escolhida', (t) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.enterText(campo('preco'), '35');
      await t.tap(find.text('Manual'));
      await t.pump();
      await t.enterText(campo('sel-B2'), '70');
      await t.enterText(campo('sel-B1'), '80');
      await t.pump();
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(s.ultimaVendaQtd?.selecao, [('B1', 80), ('B2', 70)]);
      expect(s.ultimaVendaQtd?.qtd, 150);
    });

    testWidgets('automático envia o pedido sem seleção', (t) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.enterText(campo('preco'), '35');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(s.ultimaVendaQtd?.selecao, isNull);
      expect(s.ultimaVendaQtd?.ticker, 'BBAS3');
      expect(s.ultimaVendaQtd?.qtd, 150);
    });

    testWidgets('botão desativado durante a gravação', (t) async {
      final s = servicos([b1, b2]);
      final espera = Completer<void>();
      s.esperaGravacao = espera.future;
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('preco'), '35');
      await t.tap(find.text('Salvar'));
      await t.pump();
      expect(salvar(t), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.text('Salvar'), warnIfMissed: false);
      await t.pump();
      expect(chamadasDe(s, 'registrarVendaQtd'), 1);
      espera.complete();
      await t.pumpAndSettle();
    });

    testWidgets('venda duplicada mostra "Essa venda já foi registrada."', (
      t,
    ) async {
      final s = servicos([b1, b2]);
      s.vendaRegistrada = VendaRegistrada(
        visao: s.visoes['2026-10']!,
        aviso: 'Essa venda já foi registrada.',
      );
      final r = await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('preco'), '35');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Essa venda já foi registrada.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(r.valor, isNotNull);
    });

    testWidgets('mês por custo médio: rótulo e aviso do custo médio', (
      t,
    ) async {
      final s = servicos([b1, b2]);
      s.previaResp = const PreviaVenda(
        linhas: [],
        gerencial: 10,
        fiscal: 7.5,
        qtdDt: 0,
        qtdComum: 150,
        custoMedio: true,
      );
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.enterText(campo('preco'), '35');
      await t.pump(meio);
      expect(
        find.textContaining('Resultado fiscal da operação (custo médio): '),
        findsOneWidget,
      );
      expect(find.text(textoEscolhaDasCompras), findsOneWidget);
      expect(find.text(textoEscolhaDasComprasPorCompra), findsNothing);
    });

    testWidgets('painel fiscal x gerencial e prévia 300 ms depois da última '
        'tecla', (t) async {
      final s = servicos([b1, b2]);
      s.previaResp = PreviaVenda(
        linhas: [
          LinhaPrevia(ItemAlocacao(b2, 100), custoUnitarioEfetivo(b2), 1000),
          LinhaPrevia(ItemAlocacao(b1, 50), custoUnitarioEfetivo(b1), 234.5),
        ],
        gerencial: 1234.5,
        fiscal: 1100,
        qtdDt: 0,
        qtdComum: 150,
      );
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '150');
      await t.enterText(campo('preco'), '35');
      await t.pump(meio);
      expect(
        find.text(
          'Resultado pelas compras escolhidas (gerencial): R\$ 1.234,50',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Resultado fiscal da operação (por compra): R\$ 1.100,00'),
        findsOneWidget,
      );
      expect(find.text('Day trade: 0 ações; comum: 150 ações'), findsOneWidget);
      expect(find.text(textoEscolhaDasComprasPorCompra), findsOneWidget);
      // automático lista as compras escolhidas pelo serviço
      expect(
        find.textContaining('05/10/2026  ·  100 ações  ·  custo '),
        findsOneWidget,
      );
      expect(s.ultimaPrevia?.qtd, 150);
      expect(s.ultimaPrevia?.selecao, isNull);
      // resumo da ordem somado por compra: 150 x R\$ 35,00
      expect(find.text('R\$ 5.250,00'), findsOneWidget);
      expect(find.textContaining('Swing trade'), findsOneWidget);

      final antes = chamadasDe(s, 'previaVenda');
      await t.enterText(campo('qtd'), '10');
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(campo('qtd'), '20');
      await t.pump(const Duration(milliseconds: 299));
      expect(chamadasDe(s, 'previaVenda'), antes);
      await t.pump(const Duration(milliseconds: 1));
      expect(chamadasDe(s, 'previaVenda'), antes + 1);
      expect(s.ultimaPrevia?.qtd, 20);
    });

    testWidgets('prévia manual leva a seleção e o aviso de metas aparece', (
      t,
    ) async {
      final s = servicos([b1, b2]);
      s.previaResp = const PreviaVenda(
        linhas: [],
        gerencial: 1,
        fiscal: 1,
        qtdDt: 0,
        qtdComum: 10,
        aviso: 'Esta venda usa quantidade reservada por metas ativas.',
      );
      await _abrir(t, s, lote: b2);
      await t.enterText(campo('preco'), '35');
      await t.pump(meio);
      expect(s.ultimaPrevia?.selecao, [('B2', 100)]);
      expect(
        find.text('Esta venda usa quantidade reservada por metas ativas.'),
        findsOneWidget,
      );
    });

    testWidgets('erro da prévia aparece sem travar o formulário', (t) async {
      final s = servicos([b1, b2])
        ..erros['previaVenda'] = ErroValidacao('Preço inválido.');
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('preco'), '35');
      await t.pump(meio);
      expect(find.text('Preço inválido.'), findsOneWidget);
      expect(salvar(t), isNotNull);
    });

    testWidgets('automático acima do disponível explica na área da prévia', (
      t,
    ) async {
      final s = servicos([b1, b2]);
      await _abrir(t, s, ticker: 'BBAS3');
      await t.enterText(campo('qtd'), '300');
      await t.pump(meio);
      expect(
        find.text(
          'Quantidade indisponível: só há 200 ações de BBAS3 nessa data.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('retroativa e mês fechado seguem com uma compra', (t) async {
      final antigo = compra('R1', '2026-07-10', 100, 50);
      final s = servicos([antigo]);
      await _abrir(t, s, ticker: 'BBAS3');
      expect(find.text('Automático'), findsOneWidget);
      await t.enterText(_campoData, '15/09/2026');
      await t.pump();
      expect(find.text('Automático'), findsNothing);
      expect(find.text('Compra'), findsOneWidget);
      await t.enterText(campo('preco'), '55');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(s.ultimaVenda?.loteId, 'R1');
      expect(chamadasDe(s, 'registrarVendaQtd'), 0);
    });

    testWidgets('editar venda em grupo abre o grupo inteiro', (t) async {
      final g1 = compra(
        'B1',
        '2026-10-02',
        100,
        30,
        vendas: [Venda(id: 'G.1', data: '2026-10-20', qtd: 30, preco: 35)],
      );
      final g2 = compra(
        'B2',
        '2026-10-05',
        100,
        20,
        vendas: [Venda(id: 'G.2', data: '2026-10-20', qtd: 20, preco: 35)],
      );
      final s = servicos([g1, g2]);
      final r = await _abrir(t, s, editar: (g1, g1.vendas.first));
      expect(find.text('Editar venda'), findsOneWidget);
      // a prévia vale na edição, com o id do próprio grupo
      await t.pump(meio);
      expect(s.ultimaPrevia?.grupo, 'G');
      expect(s.ultimaPrevia?.selecao, [('B1', 30), ('B2', 20)]);
      expect(modo(t), ModoVenda.manual);
      expect(campoTexto(t, 'ticker').enabled, isFalse);
      expect(campoTexto(t, 'qtd').controller!.text, '50');
      expect(campoTexto(t, 'preco').controller!.text, '35,00');
      expect(find.text('20/10/2026'), findsOneWidget);
      // a quantidade do próprio grupo está liberada
      expect(campoTexto(t, 'sel-B1').controller!.text, '30');
      expect(campoTexto(t, 'sel-B2').controller!.text, '20');
      expect(
        find.textContaining('original 100  ·  disp. 100'),
        findsNWidgets(2),
      );
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(
        s.chamadas,
        contains('editarGrupoVenda(2026-10, G, 2026-10-20, 50)'),
      );
      expect(s.ultimaVendaQtd?.selecao, [('B1', 30), ('B2', 20)]);
      expect(chamadasDe(s, 'editarVenda'), 0);
      expect(r.valor, isNotNull);
    });
  });
}
