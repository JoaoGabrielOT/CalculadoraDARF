import 'dart:async';

import 'package:calculadoradarf/app/componentes/campo_data.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
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
    'ao escolher o ticker lista os lotes abertos e preenche a quantidade com '
    'o disponível',
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
      expect(
        find.text('05/10/2026  ·  R\$ 32,50  ·  60 disp.'),
        findsOneWidget,
      );
      expect(
        find.text('Ação  ·  Custo R\$ 32,50  ·  Disponível: 60'),
        findsOneWidget,
      );
      expect(find.text('Quantidade (máx. 60)'), findsOneWidget);
      expect(campoTexto(t, 'qtd').controller!.text, '60');
      expect(find.text('28/10/2026'), findsOneWidget);

      await t.enterText(campo('ticker'), 'xxxx1');
      await t.pump();
      expect(
        find.text('Nenhuma compra em aberto desse ticker'),
        findsOneWidget,
      );
    },
  );

  testWidgets('rótulos repetidos de compra ganham o sufixo (2)', (t) async {
    final s = ServicosFalsos();
    Lote igual(String id) => Lote(
      id: id,
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-10-05',
      qtd: 10,
      preco: 30,
    );
    s.visoes['2026-10'] = visaoExemplo(
      Mes(mes: '2026-10', lotes: [igual('A'), igual('B')]),
    );
    await _abrir(t, s, ticker: 'PETR4');
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    expect(find.text('05/10/2026  ·  R\$ 30,00  ·  10 disp.'), findsWidgets);
    expect(
      find.text('05/10/2026  ·  R\$ 30,00  ·  10 disp. (2)'),
      findsOneWidget,
    );
    await t.tap(find.text('05/10/2026  ·  R\$ 30,00  ·  10 disp. (2)'));
    await t.pumpAndSettle();
    await t.enterText(campo('preco'), '31');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimaVenda?.loteId, 'B');
  });

  testWidgets('lote e ticker iniciais vêm escolhidos', (t) async {
    final s = ServicosFalsos();
    await _abrir(t, s, lote: _l('L2'));
    expect(campoTexto(t, 'ticker').controller!.text, 'VALE3');
    expect(campoTexto(t, 'qtd').controller!.text, '200');
    expect(campoTexto(t, 'preco').focusNode!.hasFocus, isTrue);
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
    await t.enterText(campo('qtd'), '50');
    await t.pump();
    expect(find.text('Buscando cotação…'), findsOneWidget);
    expect(find.text('R\$ 500,00'), findsOneWidget);
    expect(find.textContaining('Será creditado na conta: '), findsOneWidget);
    expect(find.textContaining('Swing trade'), findsOneWidget);
  });

  testWidgets('venda no dia da compra é day trade', (t) async {
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
    await _abrir(t, s, ticker: 'PETR4');
    await t.enterText(campo('preco'), '31');
    await t.pump();
    expect(
      find.textContaining('Day trade (compra e venda no mesmo dia)'),
      findsOneWidget,
    );
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
      find.text('Quantidade maior que a disponível (200).'),
      findsOneWidget,
    );
    await t.enterText(_campoData, '');
    await t.enterText(campo('qtd'), '10');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Selecione a data da venda.'), findsOneWidget);
    expect(s.ultimaVenda, isNull);
  });

  testWidgets('salvar registra a venda e devolve o resultado', (t) async {
    final s = ServicosFalsos();
    final r = await _abrir(t, s, lote: _l('L2'));
    await t.enterText(campo('preco'), '65,5');
    await t.enterText(campo('qtd'), '50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimaVenda?.loteId, 'L2');
    expect(s.ultimaVenda?.data, hojeExemplo);
    expect(s.ultimaVenda?.qtd, 50);
    expect(s.ultimaVenda?.preco, 65.5);
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
      ..erros['registrarVenda'] = ErroValidacao(
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
    expect(s.chamadas.where((c) => c.startsWith('registrarVenda')).length, 1);
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
}
