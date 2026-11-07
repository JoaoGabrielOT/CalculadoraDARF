import 'dart:async';

import 'package:calculadoradarf/app/componentes/grafico_linha.dart';
import 'package:calculadoradarf/app/componentes/logo_ativo.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/radar/tela_radar.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 900);

DadosAtivo _dados(
  String ticker, {
  double preco = 32.5,
  double varPct = 1.5,
  double variacao = 0.48,
  double media = 28,
  double atr = 0.9,
  double atrPct = 3.0,
}) => DadosAtivo(
  ticker: ticker,
  nome: 'Nome de $ticker',
  preco: preco,
  media6m: media,
  atr: atr,
  atrPct: atrPct,
  risco: classificarRisco(atrPct),
  variacao: variacao,
  variacaoPct: varPct,
  vsMediaPct: (preco / media - 1) * 100,
);

CotacaoOk _ok(String t, {double varPct = 1.5, double preco = 32.5}) =>
    CotacaoOk(_dados(t, varPct: varPct, preco: preco));

typedef _Aberto = ({String ticker, String nome, DadosAtivo? dados});

class _Cena {
  _Cena(this.servicos);

  final ServicosFalsos servicos;
  final List<_Aberto> abertos = [];
}

Future<_Cena> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  bool naAba = true,
  bool assentar = true,
}) async {
  final cena = _Cena(servicos ?? ServicosFalsos());
  await montarApp(
    t,
    servicos: cena.servicos,
    tamanho: tamanho,
    tela: TelaRadar(
      aoAbrirGrafico: (
        c, {
        required ticker,
        required nome,
        dados,
        amigo = false,
        jaTenho = true,
      }) => cena.abertos.add((ticker: ticker, nome: nome, dados: dados)),
    ),
  );
  if (assentar) await t.pumpAndSettle();
  if (naAba) {
    _estado(t).irPara(Aba.radar);
    if (assentar) {
      await t.pumpAndSettle();
    } else {
      await t.pump();
      await t.pump();
    }
  }
  return cena;
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaRadar)), listen: false);

Finder _linha(String ticker) => find.byKey(Key('linha-radar-$ticker'));
Finder _cartao(String ticker) => find.byKey(Key('cartao-radar-$ticker'));

Finder _na(Finder linha, Finder f) => find.descendant(of: linha, matching: f);

/// Tickers visíveis, de cima para baixo.
List<String> _ordem(
  WidgetTester t,
  List<String> tickers, {
  Finder Function(String) achar = _linha,
}) {
  final achados = <(double, String)>[];
  for (final tk in tickers) {
    final f = achar(tk);
    if (f.evaluate().isNotEmpty) achados.add((t.getTopLeft(f).dy, tk));
  }
  achados.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final a in achados) a.$2];
}

/// Arrasta em passos, com quadros entre eles (a lista reordenável decide a
/// posição a cada quadro).
Future<void> _arrastar(WidgetTester t, Finder alvo, double dy) async {
  final gesto = await t.startGesture(t.getCenter(alvo));
  await t.pump();
  for (var i = 0; i < 8; i++) {
    await gesto.moveBy(Offset(0, dy / 8));
    await t.pump(const Duration(milliseconds: 50));
  }
  await gesto.up();
  await t.pumpAndSettle();
}

VisaoRadar _radarAmigo() => VisaoRadar(
  itens: [
    ItemRadar(ticker: 'PETR4', nome: 'Petrobras PN', desde: '2026-09-01'),
    ItemRadar(ticker: 'AAPL34', nome: 'Apple', desde: '2026-09-02'),
  ],
  custodia: const {},
  meus: const {'PETR4', 'WEGE3', 'MXRF11'},
  amigo: 'ana@exemplo.com',
);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets('lista rola enquanto as cotações carregam e mostra erro por '
      'linha', (t) async {
    final itens = [
      for (var i = 0; i < 30; i++)
        ItemRadar(
          ticker: 'ATIV${i.toString().padLeft(2, '0')}',
          nome: 'Empresa $i',
          desde: '2026-09-01',
          pos: i,
        ),
    ];
    final s = ServicosFalsos()
      ..visaoRadar = VisaoRadar(
        itens: itens,
        custodia: const {},
        meus: {for (final i in itens) i.ticker},
      );
    final pendentes = {
      for (final i in itens) i.ticker: Completer<CotacaoRadar>(),
    };
    s.cotacaoFn = (ticker, nome) => pendentes[ticker]!.future;
    await _montar(t, servicos: s, assentar: false);

    // todas as cotações pedidas de uma vez, nenhuma respondida
    expect(s.chamadas.where((c) => c.startsWith('cotacao(')).length, 30);
    expect(_na(_linha('ATIV00'), find.text('Carregando…')), findsNothing);
    expect(_na(_linha('ATIV00'), find.text('Empresa 0')), findsOneWidget);

    // a lista rola com tudo pendente
    expect(_linha('ATIV29'), findsNothing);
    await t.drag(find.byKey(const Key('lista-radar')), const Offset(0, -3000));
    await t.pump();
    expect(_linha('ATIV29'), findsOneWidget);
    expect(_linha('ATIV00'), findsNothing);
    await t.drag(find.byKey(const Key('lista-radar')), const Offset(0, 3000));
    await t.pump();
    expect(_linha('ATIV00'), findsOneWidget);

    // metade chega com sucesso e uma com erro: cada linha mostra o seu
    for (var i = 0; i < 30; i += 2) {
      final tk = itens[i].ticker;
      pendentes[tk]!.complete(_ok(tk, preco: 10.0 + i));
    }
    pendentes['ATIV01']!.complete(
      const CotacaoErro(
        'ATIV01',
        'Limite de consultas do Yahoo atingido. Tente em alguns minutos.',
      ),
    );
    await t.pump();
    await t.pump();
    expect(_na(_linha('ATIV00'), find.text(brl(10))), findsOneWidget);
    expect(_na(_linha('ATIV02'), find.text(brl(12))), findsOneWidget);
    expect(
      _na(
        _linha('ATIV01'),
        find.text(
          'Limite de consultas do Yahoo atingido. Tente em alguns minutos.',
        ),
      ),
      findsOneWidget,
    );
    expect(_na(_linha('ATIV01'), find.text('—')), findsWidgets);
    // quem ainda não chegou continua carregando
    expect(_na(_linha('ATIV03'), find.text('Carregando…')), findsNothing);
    expect(_na(_linha('ATIV03'), find.text('Empresa 3')), findsOneWidget);
    // o mini-gráfico vem depois de cada cotação com sucesso, e só nelas
    expect(s.chamadas, contains('grafico(ATIV00, 1D)'));
    expect(s.chamadas, isNot(contains('grafico(ATIV01, 1D)')));
    expect(s.chamadas, isNot(contains('grafico(ATIV03, 1D)')));

    for (var i = 3; i < 30; i += 2) {
      final tk = itens[i].ticker;
      pendentes[tk]!.complete(_ok(tk));
    }
    await t.pumpAndSettle();
  });

  testWidgets('linha mostra logo (ou iniciais), preço, variação colorida, '
      'média 6m, ATR, selo de risco e mini-gráfico', (t) async {
    final s = ServicosFalsos()
      ..visaoRadar = VisaoRadar(
        itens: [
          ItemRadar(ticker: 'PETR4', nome: 'Petrobras PN', desde: '2026-09-01'),
          ItemRadar(ticker: 'WEGE3', nome: 'WEG ON', desde: '2026-09-01'),
        ],
        custodia: const {},
        meus: const {'PETR4', 'WEGE3'},
      )
      ..cotacoesFalsas = {
        'PETR4': CotacaoOk(
          _dados('PETR4', atrPct: 3.0, variacao: 0.48, varPct: 1.5),
        ),
        'WEGE3': CotacaoOk(
          _dados(
            'WEGE3',
            preco: 40,
            media: 42,
            atr: 2.2,
            atrPct: 5.5,
            variacao: -0.8,
            varPct: -1.96,
          ),
        ),
      };
    await _montar(t, servicos: s);
    final cores = CoresApp.de(t.element(find.byType(TelaRadar)));

    final p = _linha('PETR4');
    expect(_na(p, find.byType(LogoAtivo)), findsOneWidget);
    expect(_na(p, find.text('PETR')), findsOneWidget); // iniciais sem logo
    expect(_na(p, find.text('PETR4')), findsOneWidget);
    expect(_na(p, find.text('Nome de PETR4')), findsOneWidget);
    expect(_na(p, find.text(brl(32.5))), findsOneWidget);
    expect(_na(p, find.text('▲ +1,50%')), findsOneWidget);
    expect(_na(p, find.text('+${brl(0.48)}')), findsOneWidget);
    expect(_na(p, find.text(brl(28))), findsOneWidget);
    expect(_na(p, find.text(brl(0.9))), findsOneWidget);
    expect(_na(p, find.text('3,00%')), findsOneWidget);
    expect(_na(p, find.text('Médio Risco')), findsOneWidget);
    expect(_na(p, find.byType(GraficoLinha)), findsOneWidget);
    final alta = t.widget<Text>(_na(p, find.text('▲ +1,50%')));
    expect(alta.style!.color, cores.alta);

    final w = _linha('WEGE3');
    final queda = t.widget<Text>(_na(w, find.text('▼ -1,96%')));
    expect(queda.style!.color, cores.queda);
    expect(_na(w, find.text(brl(-0.8))), findsOneWidget);
    expect(_na(w, find.text('Alto Risco / Muito Alto')), findsOneWidget);

    // cabeçalho e legenda das faixas
    for (final c in [
      'ATIVO',
      'COTAÇÃO',
      'DIA',
      'MÉDIA 6 MESES',
      'ATR (14)',
      'ATR%',
      'RISCO',
    ]) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.text('RISCO PELO ATR%'), findsOneWidget);
    for (final f in [
      'Menor Risco · < 2,2%',
      'Médio Risco · 2,2% a 3,0%',
      'Alto Risco · 3,0% a 4,5%',
      'Alto Risco / Muito Alto · > 4,5%',
    ]) {
      expect(find.text(f), findsOneWidget);
    }
    expect(find.text('Radar de Ações'), findsOneWidget);
  });

  testWidgets('filtros e ordenações reaplicam com as cotações; ordem '
      'escolhida chama definirOrdemRadar', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4', varPct: 2),
        'WEGE3': _ok('WEGE3', varPct: -1),
        'MXRF11': _ok('MXRF11', varPct: 0.5),
      };
    await _montar(t, servicos: s);
    const todos = ['PETR4', 'WEGE3', 'MXRF11'];

    expect(_ordem(t, todos), todos);
    expect(
      find.text('Hoje: 2 em alta · 1 em queda · média +0,50%'),
      findsOneWidget,
    );

    await t.tap(find.text('Em alta'));
    await t.pumpAndSettle();
    expect(_ordem(t, todos), ['PETR4', 'MXRF11']);
    await t.tap(find.text('Em queda'));
    await t.pumpAndSettle();
    expect(_ordem(t, todos), ['WEGE3']);
    await t.tap(find.text('Em carteira'));
    await t.pumpAndSettle();
    expect(_ordem(t, todos), ['PETR4']);
    await t.tap(find.text('Todos'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('menu-ordem')));
    await t.pumpAndSettle();
    await t.tap(find.text('Maior alta do dia').last);
    await t.pumpAndSettle();
    expect(_ordem(t, todos), ['PETR4', 'MXRF11', 'WEGE3']);
    expect(_estado(t).preferencias.ordemRadar, 'alta');
    expect(s.preferenciasSalvas!.ordemRadar, 'alta');

    await t.tap(find.byKey(const Key('menu-ordem')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ticker (A–Z)').last);
    await t.pumpAndSettle();
    expect(_ordem(t, todos), ['MXRF11', 'PETR4', 'WEGE3']);
    expect(s.preferenciasSalvas!.ordemRadar, 'ticker');
  });

  testWidgets('arrastar reordena só em Minha ordem + Todos e chama '
      'reordenarRadar; fora disso mostra a mensagem', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s);
    const todos = ['PETR4', 'WEGE3', 'MXRF11'];
    const aviso = 'Para arrastar, use Ordenar: Minha ordem e o filtro Todos.';

    expect(find.text(aviso), findsNothing);
    await _arrastar(t, find.byKey(const Key('alca-PETR4')), 80);
    await t.pumpAndSettle();
    expect(s.ultimaOrdemRadar, ['WEGE3', 'PETR4', 'MXRF11']);
    expect(_ordem(t, todos), ['WEGE3', 'PETR4', 'MXRF11']);
    expect(find.text(aviso), findsNothing);

    // com filtro: a alça só avisa
    s.chamadas.clear();
    await t.tap(find.text('Em alta'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alca-PETR4')));
    await t.pumpAndSettle();
    expect(find.text(aviso), findsOneWidget);
    await _arrastar(t, find.byKey(const Key('alca-PETR4')), 80);
    await t.pumpAndSettle();
    expect(s.chamadas.where((c) => c.startsWith('reordenarRadar')), isEmpty);

    // com outra ordem: idem
    await t.tap(find.text('Todos'));
    await t.tap(find.byKey(const Key('menu-ordem')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ticker (A–Z)').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alca-PETR4')));
    await t.pumpAndSettle();
    expect(find.text(aviso), findsOneWidget);
    expect(s.chamadas.where((c) => c.startsWith('reordenarRadar')), isEmpty);
  });

  testWidgets('adicionar: erro do serviço vira aviso; sucesso limpa o campo e '
      'busca só aquele ticker', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
        'BBAS3': _ok('BBAS3', preco: 25),
      };
    await _montar(t, servicos: s);

    s.erros['adicionarRadar'] = ErroValidacao('Ticker inválido.');
    await t.enterText(find.byKey(const Key('campo-ticker')), 'xx');
    await t.tap(find.text('+  Adicionar'));
    await t.pumpAndSettle();
    expect(find.text('Radar'), findsOneWidget); // título do diálogo
    expect(find.text('Ticker inválido.'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    final campo = t.widget<TextField>(find.byKey(const Key('campo-ticker')));
    expect(campo.controller!.text, 'xx'); // o texto fica para corrigir

    s.erros.clear();
    s.chamadas.clear();
    await t.enterText(find.byKey(const Key('campo-ticker')), 'bbas3');
    await t.tap(find.text('+  Adicionar'));
    await t.pumpAndSettle();
    expect(campo.controller!.text, '');
    expect(s.chamadas, contains('adicionarRadar(bbas3)'));
    expect(s.chamadas.where((c) => c.startsWith('cotacao(')), [
      'cotacao(BBAS3)',
    ]);
    expect(_linha('BBAS3'), findsOneWidget);
    expect(_na(_linha('BBAS3'), find.text(brl(25))), findsOneWidget);

    // Enter também adiciona
    s.chamadas.clear();
    await t.enterText(find.byKey(const Key('campo-ticker')), 'VALE3');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(s.chamadas, contains('adicionarRadar(VALE3)'));
  });

  testWidgets('Comprar abre compra com ticker, tipo e preço atual; Vender sem '
      'custódia mostra o aviso do Python', (t) async {
    final s = ServicosFalsos()
      ..visaoRadar = VisaoRadar(
        itens: radarExemplo(),
        custodia: const {'PETR4', 'WEGE3'},
        meus: const {'PETR4', 'WEGE3', 'MXRF11'},
      )
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4', preco: 32.5),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s);

    await t.tap(_na(_linha('PETR4'), find.text('Comprar')));
    await t.pumpAndSettle();
    expect(find.text('Novo ativo'), findsOneWidget);
    String texto(String chave) =>
        t.widget<TextField>(find.byKey(Key(chave))).controller!.text;
    expect(texto('ticker'), 'PETR4');
    expect(texto('preco'), '32,50');
    expect(find.text('Tipo: Ação (identificado pelo ticker)'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();

    // Vender sem lote em aberto no mês (WEGE3 só consta na custódia)
    await t.tap(_na(_linha('WEGE3'), find.text('Vender')));
    await t.pumpAndSettle();
    expect(
      find.text('Não há WEGE3 em custódia no mês 10/2026.'),
      findsOneWidget,
    );
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();

    // com lote em aberto abre a venda
    await t.tap(_na(_linha('PETR4'), find.text('Vender')));
    await t.pumpAndSettle();
    expect(find.text('Registrar venda'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();

    // sem custódia o botão fica desabilitado
    final vender = t.widget<OutlinedButton>(
      find.descendant(
        of: _linha('MXRF11'),
        matching: find.widgetWithText(OutlinedButton, 'Vender'),
      ),
    );
    expect(vender.onPressed, isNull);
  });

  testWidgets('remover pergunta antes e some da lista', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s);

    await t.tap(_na(_linha('WEGE3'), find.text('Remover')));
    await t.pumpAndSettle();
    expect(find.text('Remover WEGE3 do radar?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(_linha('WEGE3'), findsOneWidget);

    await t.tap(_na(_linha('WEGE3'), find.text('Remover')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remover'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('removerRadar(WEGE3)'));
    expect(_linha('WEGE3'), findsNothing);
    expect(_linha('PETR4'), findsOneWidget);
  });

  testWidgets('notícias: adicionar e importar buscam as notícias; remover só '
      'relê (py:2488, 2502, 2519, 2528)', (t) async {
    final s = ServicosFalsos()
      ..visaoRadarAmigo = _radarAmigo()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
        'BBAS3': _ok('BBAS3'),
        'AAPL34': _ok('AAPL34'),
      };
    await _montar(t, servicos: s);
    int buscas() =>
        s.chamadas.where((c) => c.startsWith('atualizarNoticias')).length;

    await t.enterText(find.byKey(const Key('campo-ticker')), 'BBAS3');
    await t.tap(find.text('+  Adicionar'));
    await t.pumpAndSettle();
    expect(buscas(), 1);
    expect(s.chamadas, contains('atualizarNoticias(false)'));

    final versao = _estado(t).versaoNoticias;
    await t.tap(_na(_linha('WEGE3'), find.text('Remover')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remover'));
    await t.pumpAndSettle();
    expect(buscas(), 1); // remover não busca
    expect(_estado(t).versaoNoticias, greaterThan(versao));

    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    await t.tap(find.text('+  Meu radar'));
    await t.pumpAndSettle();
    expect(buscas(), 2);
    await t.tap(find.text('+  Importar todos para o meu radar'));
    await t.pumpAndSettle();
    // nada novo: só avisa, sem buscar
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(buscas(), 2);
  });

  testWidgets('notícias: importar todos busca as notícias', (t) async {
    final s = ServicosFalsos()..visaoRadarAmigo = _radarAmigo();
    await _montar(t, servicos: s);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    await t.tap(find.text('+  Importar todos para o meu radar'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Importar'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('atualizarNoticias(false)'));
  });

  testWidgets("radar do amigo: título 'Radar de <email>', '+ Meu radar' some "
      "para quem já tenho, 'Importar todos' confirma e importa", (t) async {
    final s = ServicosFalsos()
      ..visaoRadarAmigo = _radarAmigo()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'AAPL34': _ok('AAPL34'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s);
    expect(find.byKey(const Key('campo-ticker')), findsOneWidget);

    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(s.chamadas, contains('radar(ana@exemplo.com)'));
    expect(find.text('Radar de ana@exemplo.com'), findsOneWidget);
    expect(find.byKey(const Key('campo-ticker')), findsNothing);
    expect(find.text('Comprar'), findsNothing);
    expect(find.byKey(const Key('alca-PETR4')), findsNothing);
    expect(find.text('+  Meu radar'), findsOneWidget);
    expect(_na(_linha('AAPL34'), find.text('+  Meu radar')), findsOneWidget);
    expect(_na(_linha('PETR4'), find.text('✓  No meu radar')), findsOneWidget);
    // custódia vazia no radar do amigo: "Em carteira" não mostra nada
    await t.tap(find.text('Em carteira'));
    await t.pumpAndSettle();
    expect(_linha('PETR4'), findsNothing);
    await t.tap(find.text('Todos'));
    await t.pumpAndSettle();

    // importar um só
    await t.tap(find.text('+  Importar todos para o meu radar'));
    await t.pumpAndSettle();
    expect(find.text('Importar radar'), findsOneWidget);
    expect(
      find.text('Adicionar 1 ativo(s) ao seu radar: AAPL34?'),
      findsOneWidget,
    );
    await t.tap(find.widgetWithText(FilledButton, 'Importar'));
    await t.pumpAndSettle();
    expect([for (final i in s.ultimaImportacao!) i.ticker], ['AAPL34']);
    expect(find.text('+  Meu radar'), findsNothing);
    expect(find.text('✓  No meu radar'), findsNWidgets(2));

    // nada novo: só avisa
    await t.tap(find.text('+  Importar todos para o meu radar'));
    await t.pumpAndSettle();
    expect(
      find.text('Todos os ativos do radar do amigo já estão no seu radar.'),
      findsOneWidget,
    );
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();

    // voltar aos meus dados
    await _estado(t).trocarVisao(null);
    await t.pumpAndSettle();
    expect(find.text('Radar de Ações'), findsOneWidget);
    expect(find.byKey(const Key('campo-ticker')), findsOneWidget);
  });

  testWidgets('"+ Meu radar" importa só aquele ativo', (t) async {
    final s = ServicosFalsos()..visaoRadarAmigo = _radarAmigo();
    await _montar(t, servicos: s);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    await t.tap(find.text('+  Meu radar'));
    await t.pumpAndSettle();
    expect([for (final i in s.ultimaImportacao!) i.ticker], ['AAPL34']);
    expect(find.text('+  Meu radar'), findsNothing);
  });

  testWidgets('tocar na linha abre o gráfico; durante arraste não abre', (
    t,
  ) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    final cena = await _montar(t, servicos: s);

    await t.tap(_na(_linha('WEGE3'), find.text('Nome de WEGE3')));
    await t.pumpAndSettle();
    expect(cena.abertos.length, 1);
    expect(cena.abertos.single.ticker, 'WEGE3');
    expect(cena.abertos.single.nome, 'WEG ON');
    expect(cena.abertos.single.dados?.preco, 32.5);

    // os botões e a alça não abrem
    await t.tap(find.byKey(const Key('alca-WEGE3')));
    await t.pumpAndSettle();
    expect(cena.abertos.length, 1);

    // arrastar pela alça não abre
    await _arrastar(t, find.byKey(const Key('alca-PETR4')), 80);
    await t.pumpAndSettle();
    expect(cena.abertos.length, 1);
    expect(s.ultimaOrdemRadar, isNotNull);
  });

  testWidgets('atualizar: status e espera', (t) async {
    final s = ServicosFalsos();
    var rodada = <String, Completer<CotacaoRadar>>{};
    s.cotacaoFn = (ticker, nome) {
      final c = Completer<CotacaoRadar>();
      rodada[ticker] = c;
      return c.future;
    };
    await _montar(t, servicos: s, assentar: false);
    expect(find.text('Atualizando cotações…'), findsOneWidget);
    expect(rodada.length, 3);

    // pedidos durante a atualização entram na espera, sem chamada nova
    s.chamadas.clear();
    await t.tap(find.text('Atualizar'));
    await t.pump();
    await t.tap(find.text('Atualizar'));
    await t.pump();
    expect(s.chamadas.where((c) => c.startsWith('cotacao(')), isEmpty);
    expect(s.chamadas, isNot(contains('limparCacheCotacoes()')));

    final primeira = rodada;
    rodada = {};
    for (final e in primeira.entries) {
      e.value.complete(_ok(e.key));
    }
    await t.pump();
    await t.pump();
    // a espera roda uma vez, com os tickers pedidos
    expect(s.chamadas.where((c) => c.startsWith('cotacao(')).length, 3);
    for (final e in rodada.entries) {
      e.value.complete(_ok(e.key));
    }
    await t.pumpAndSettle();
    expect(find.textContaining('Atualizado às '), findsOneWidget);
    expect(
      find.textContaining('· Yahoo Finance (atraso de até 15 min)'),
      findsOneWidget,
    );

    // Atualizar com a lista parada limpa o cache e busca de novo
    s.cotacaoFn = null;
    s.cotacoesFalsas = {
      'PETR4': _ok('PETR4'),
      'WEGE3': _ok('WEGE3'),
      'MXRF11': _ok('MXRF11'),
    };
    s.chamadas.clear();
    await t.tap(find.text('Atualizar'));
    await t.pumpAndSettle();
    expect(s.chamadas.first, 'limparCacheCotacoes()');
    expect(s.chamadas.where((c) => c.startsWith('cotacao(')).length, 3);
  });

  testWidgets('um erro novo não apaga a cotação anterior', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4', preco: 32.5),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s);
    expect(_na(_linha('PETR4'), find.text(brl(32.5))), findsOneWidget);

    s.cotacoesFalsas['PETR4'] = const CotacaoErro('PETR4', 'Sem conexão.');
    await t.tap(find.text('Atualizar'));
    await t.pumpAndSettle();
    expect(_na(_linha('PETR4'), find.text(brl(32.5))), findsOneWidget);
  });

  testWidgets('timer de 60 s só com a aba Radar visível', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4'),
        'WEGE3': _ok('WEGE3'),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s);
    int cotacoes() => s.chamadas.where((c) => c.startsWith('cotacao(')).length;
    expect(cotacoes(), 3);

    await t.pump(const Duration(seconds: 60));
    await t.pumpAndSettle();
    expect(cotacoes(), 6);

    // fora da aba o timer não busca
    _estado(t).irPara(Aba.caixa);
    await t.pump();
    await t.pump(const Duration(seconds: 60));
    await t.pump(const Duration(seconds: 60));
    expect(cotacoes(), 6);

    // ao voltar, atualiza na hora
    _estado(t).irPara(Aba.radar);
    await t.pumpAndSettle();
    expect(cotacoes(), 9);
  });

  testWidgets('vazios do radar', (t) async {
    final s = ServicosFalsos()
      ..visaoRadar = const VisaoRadar(itens: [], custodia: {}, meus: {})
      ..visaoRadarAmigo = const VisaoRadar(
        itens: [],
        custodia: {},
        meus: {},
        amigo: 'ana@exemplo.com',
      );
    await _montar(t, servicos: s);
    expect(
      find.text('Nenhum ativo no radar. Adicione um ticker acima.'),
      findsOneWidget,
    );

    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(
      find.text('ana@exemplo.com não tem ativos no radar.'),
      findsOneWidget,
    );
    await _estado(t).trocarVisao(null);
    await t.pumpAndSettle();
  });

  testWidgets('erro ao recarregar mantém a lista', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s);
    expect(_linha('PETR4'), findsOneWidget);

    s.erros['radar'] = ErroValidacao('disco cheio');
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(_linha('PETR4'), findsOneWidget);
    expect(find.textContaining('disco cheio'), findsOneWidget);
  });

  testWidgets('compacto: cartão com logo, ticker, nome, mini-gráfico, preço e '
      'variação; dica de uso', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': _ok('PETR4', varPct: 1.5),
        'WEGE3': _ok('WEGE3', varPct: -1),
        'MXRF11': _ok('MXRF11'),
      };
    await _montar(t, servicos: s, tamanho: const Size(360, 1800));
    final c = _cartao('PETR4');
    expect(c, findsOneWidget);
    expect(_na(c, find.byType(LogoAtivo)), findsOneWidget);
    expect(_na(c, find.text('PETR4')), findsOneWidget);
    expect(_na(c, find.text('Nome de PETR4')), findsOneWidget);
    expect(_na(c, find.byType(GraficoLinha)), findsOneWidget);
    expect(_na(c, find.text(brl(32.5))), findsOneWidget);
    expect(_na(c, find.text('▲ +1,50%')), findsOneWidget);
    expect(_na(c, find.text('Médio Risco')), findsOneWidget);
    expect(
      find.text(
        'Toque para ver o gráfico. Toque e segure e arraste para mudar a '
        'ordem.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Atualizar'), findsOneWidget);
    expect(_ordem(t, ['PETR4', 'WEGE3', 'MXRF11'], achar: _cartao), [
      'PETR4',
      'WEGE3',
      'MXRF11',
    ]);

    // toque e segure arrasta o cartão
    final gesto = await t.startGesture(t.getCenter(_cartao('PETR4')));
    await t.pump(const Duration(milliseconds: 700));
    await gesto.moveBy(const Offset(0, 100));
    await t.pump();
    await gesto.moveBy(const Offset(0, 100));
    await t.pump();
    await gesto.up();
    await t.pumpAndSettle();
    expect(s.ultimaOrdemRadar, isNotNull);
    expect(s.ultimaOrdemRadar!.first, isNot('PETR4'));
  });
}
