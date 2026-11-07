import 'dart:async';

import 'package:calculadoradarf/app/componentes/grafico_linha.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/grafico/tela_grafico.dart';
import 'package:calculadoradarf/app/telas/radar/tela_radar.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 900);
const _celular = Size(400, 800);

// 13:00 UTC; com desvio de -3 h o gráfico mostra 10:00.
final _t0 = DateTime.utc(2026, 11, 6, 13).millisecondsSinceEpoch ~/ 1000;

Grafico _grafico(String periodo, {String ticker = 'PETR4'}) => Grafico(
  ticker: ticker,
  periodo: periodo,
  pontos: [
    (_t0, 10.4),
    (_t0 + 300, 10.5),
    (_t0 + 600, 10.2),
    (_t0 + 900, 10.8),
  ],
  referencia: 10,
  desvio: -10800,
  intradiario: periodo == '1D' || periodo == '5D',
);

DadosAtivo _dados([String ticker = 'PETR4']) => DadosAtivo(
  ticker: ticker,
  nome: 'Petrobras PN',
  preco: 32.5,
  anterior: 32,
  variacao: 0.5,
  variacaoPct: 1.56,
  minDia: 31.9,
  maxDia: 32.8,
  min52: 25,
  max52: 40,
  media6m: 28,
  vsMediaPct: 16.07,
  atr: 0.9,
  atrPct: 3.0,
  volume: 1500000,
);

class _Cena {
  final List<String> chamadas = [];
}

Future<_Cena> _abrir(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  DadosAtivo? dados,
  bool amigo = false,
  bool jaTenho = true,
  bool comVender = true,
  bool comComprar = true,
}) async {
  final cena = _Cena();
  final s = servicos ?? ServicosFalsos();
  s.graficoFn ??= (tk, p) => Future.value(_grafico(p, ticker: tk));
  await montarApp(
    t,
    servicos: s,
    tamanho: tamanho,
    tela: Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          onPressed: () => abrirGrafico(
            c,
            ticker: 'PETR4',
            nome: 'Petrobras PN',
            dados: dados ?? _dados(),
            amigo: amigo,
            jaTenho: jaTenho,
            aoComprar: comComprar ? () => cena.chamadas.add('comprar') : null,
            aoVender: comVender ? () => cena.chamadas.add('vender') : null,
            aoImportar: () => cena.chamadas.add('importar'),
            aoVerNoticias: () => cena.chamadas.add('noticias'),
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return cena;
}

Finder _linha() => find.byType(GraficoLinha);

Future<void> _tocarBorda(WidgetTester t, {required bool esquerda}) async {
  final r = t.getRect(_linha());
  await t.tapAt(Offset(esquerda ? r.left + 9 : r.right - 9, r.center.dy));
  await t.pump();
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets('abre no 1D, troca de período e mostra carregando sem travar', (
    t,
  ) async {
    final s = ServicosFalsos();
    final espera = Completer<Grafico>();
    s.graficoFn = (tk, p) =>
        p == '5D' ? espera.future : Future.value(_grafico(p));
    await _abrir(t, servicos: s);

    expect(s.chamadas, contains('grafico(PETR4, 1D)'));
    expect(find.byKey(const Key('grafico-dialogo')), findsOneWidget);
    expect(_linha(), findsOneWidget);
    // último ponto contra a referência: 10,80 / 10 -> +8%
    expect(find.text('+8,00% hoje'), findsOneWidget);
    expect(find.text('Fech. anterior R\$ 10,00'), findsOneWidget);
    for (final p in ['1D', '5D', '1M', '6M', '1A', '5A', 'Máx']) {
      expect(find.text(p), findsOneWidget);
    }

    await t.tap(find.text('5D'));
    await t.pump();
    expect(s.chamadas.last, 'grafico(PETR4, 5D)');
    expect(find.text('Carregando…'), findsOneWidget);
    expect(_linha(), findsNothing);
    // a tela segue viva: outro período pode ser pedido enquanto espera
    await t.tap(find.text('1M'));
    await t.pumpAndSettle();
    expect(find.text('+8,00% em 1M'), findsOneWidget);
    expect(_linha(), findsOneWidget);
    espera.complete(_grafico('5D'));
    await t.pumpAndSettle();
  });

  testWidgets('resposta atrasada de outro período é descartada', (t) async {
    final s = ServicosFalsos();
    final lenta = Completer<Grafico>();
    s.graficoFn = (tk, p) =>
        p == '5D' ? lenta.future : Future.value(_grafico(p));
    await _abrir(t, servicos: s);
    await t.tap(find.text('5D'));
    await t.pump();
    await t.tap(find.text('Máx'));
    await t.pumpAndSettle();
    expect(find.text('+8,00% desde o início'), findsOneWidget);
    lenta.complete(_grafico('5D'));
    await t.pumpAndSettle();
    expect(find.text('+8,00% desde o início'), findsOneWidget);
    expect(find.text('+8,00% em 5D'), findsNothing);
  });

  testWidgets('erro mostra mensagemErro e outro período tenta de novo', (
    t,
  ) async {
    final erro = SemDados('Sem dados de 1D.');
    final s = ServicosFalsos()..erros['grafico'] = erro;
    await _abrir(t, servicos: s);
    expect(find.byKey(const Key('grafico-erro')), findsOneWidget);
    expect(find.text(textoErro(erro)), findsOneWidget);
    expect(_linha(), findsNothing);

    s.erros.remove('grafico');
    await t.tap(find.text('1M'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grafico-erro')), findsNothing);
    expect(_linha(), findsOneWidget);
  });

  testWidgets('tocar e arrastar mostra preço e data do ponto', (t) async {
    await _abrir(t);
    expect(
      find.text('Passe o mouse sobre o gráfico para ver o preço de cada ponto'),
      findsOneWidget,
    );
    await _tocarBorda(t, esquerda: true);
    // 1D: rótulo curto HH:MM, no fuso do gráfico
    expect(find.text('10:00 · R\$ 10,40 · +4,00%'), findsOneWidget);

    final r = t.getRect(_linha());
    final gesto = await t.startGesture(Offset(r.left + 9, r.center.dy));
    await gesto.moveTo(Offset(r.right - 9, r.center.dy));
    await t.pump();
    expect(find.text('10:15 · R\$ 10,80 · +8,00%'), findsOneWidget);
    await gesto.up();
  });

  testWidgets('rótulos de tempo: curtos no eixo, longos no toque', (t) async {
    await _abrir(t);
    expect(find.text('10:00'), findsOneWidget);
    await t.tap(find.text('5D'));
    await t.pumpAndSettle();
    expect(find.text('06/11'), findsWidgets);
    await _tocarBorda(t, esquerda: true);
    expect(find.text('06/11 10:00 · R\$ 10,40 · +4,00%'), findsOneWidget);
    await t.tap(find.text('1A'));
    await t.pumpAndSettle();
    expect(find.text('06/11/26'), findsWidgets);
    await _tocarBorda(t, esquerda: true);
    expect(find.text('06/11/2026 · R\$ 10,40 · +4,00%'), findsOneWidget);
    await t.tap(find.text('Máx'));
    await t.pumpAndSettle();
    expect(find.text('11/2026'), findsWidgets);
  });

  Grafico graficoCom(
    String tk,
    String p,
    List<double> valores, {
    double ref = 10,
  }) => Grafico(
    ticker: tk,
    periodo: p,
    pontos: [for (final (i, v) in valores.indexed) (_t0 + i * 60, v)],
    referencia: ref,
    desvio: -10800,
    intradiario: false,
  );

  testWidgets('marcas de tempo ficam sob os pontos mesmo com vão grande', (
    t,
  ) async {
    final s = ServicosFalsos()
      ..graficoFn = (tk, p) => Future.value(
        Grafico(
          ticker: tk,
          periodo: p,
          pontos: [
            for (final (i, d) in [0, 60, 120, 180, 864000, 864060].indexed)
              (_t0 + d, 10.0 + i),
          ],
          referencia: 10,
          desvio: -10800,
          intradiario: false,
        ),
      );
    await _abrir(t, servicos: s);
    await t.tap(find.text('6M'));
    await t.pumpAndSettle();
    final r = t.getRect(_linha());
    final util = r.width - 16;
    // n = 6, 4 marcas: índices 0, 2, 3 e 5
    for (final (k, i) in [0, 2, 3, 5].indexed) {
      final x = t.getCenter(find.byKey(Key('marca-tempo-$k'))).dx;
      expect(x, closeTo(r.left + 8 + util * i / 5, 1.5), reason: 'marca $k');
      // tocar sob a marca mostra o ponto dela
      await t.tapAt(Offset(x, r.center.dy));
      await t.pump();
      expect(find.textContaining(brl(10.0 + i)), findsWidgets);
    }
  });

  testWidgets('eixo de preços tem 5 rótulos de grade em brl', (t) async {
    await _abrir(t);
    // pontos 10,2..10,8 e referência 10 no 1D: de 10,00 a 10,80
    final esperados = [
      'R\$ 10,00',
      'R\$ 10,20',
      'R\$ 10,40',
      'R\$ 10,60',
      'R\$ 10,80',
    ];
    for (final (k, v) in esperados.indexed) {
      expect(t.widget<Text>(find.byKey(Key('eixo-preco-$k'))).data, v);
    }
    expect(find.byKey(const Key('eixo-preco-5')), findsNothing);
  });

  testWidgets('cor da linha: >= a referência é alta, também fora do 1D', (
    t,
  ) async {
    final s = ServicosFalsos()
      ..graficoFn = (tk, p) => Future.value(graficoCom(tk, p, [10, 11, 10]));
    await _abrir(t, servicos: s);
    await t.tap(find.text('1M'));
    await t.pumpAndSettle();
    final cores = CoresApp.de(t.element(_linha()));
    PintorLinha pintor() =>
        t
                .widget<CustomPaint>(
                  find.descendant(
                    of: _linha(),
                    matching: find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is PintorLinha,
                    ),
                  ),
                )
                .painter!
            as PintorLinha;
    expect(pintor().cor, cores.alta); // empate: alta
    s.graficoFn = (tk, p) => Future.value(graficoCom(tk, p, [10, 11, 9]));
    await t.tap(find.text('6M'));
    await t.pumpAndSettle();
    expect(pintor().cor, cores.queda);
  });

  testWidgets('janela baixa rola em vez de estourar', (t) async {
    final cena = await _abrir(t, tamanho: const Size(900, 480));
    expect(t.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await t.ensureVisible(find.text('Ver notícias'));
    await t.tap(find.text('Ver notícias'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['noticias']);
  });

  testWidgets('gráfico sem pontos não quebra', (t) async {
    final s = ServicosFalsos()
      ..graficoFn = (tk, p) => Future.value(graficoCom(tk, p, []));
    await _abrir(t, servicos: s);
    expect(find.byKey(const Key('grafico-vazio')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('estatísticas com os valores de DadosAtivo', (t) async {
    await _abrir(t);
    expect(find.text('R\$ 32,50'), findsOneWidget);
    expect(find.text('+1,56%  (+R\$ 0,50) hoje'), findsOneWidget);
    expect(find.text('Fech. anterior'), findsOneWidget);
    expect(find.text('R\$ 32,00'), findsOneWidget);
    expect(find.text('Mín./máx. do dia'), findsOneWidget);
    expect(find.text('R\$ 31,90 – R\$ 32,80'), findsOneWidget);
    expect(find.text('Mín./máx. 52 sem.'), findsOneWidget);
    expect(find.text('R\$ 25,00 – R\$ 40,00'), findsOneWidget);
    expect(find.text('Média 6 meses'), findsOneWidget);
    expect(find.text('R\$ 28,00 (+16,07%)'), findsOneWidget);
    expect(find.text('ATR (14)'), findsOneWidget);
    expect(find.text('R\$ 0,90 · 3,00%'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('1,5 mi'), findsOneWidget);
    expect(find.text('Petrobras PN'), findsOneWidget);
  });

  testWidgets('sem dados do ativo o cabeçalho e as estatísticas mostram '
      'traço', (t) async {
    await _abrir(t, dados: DadosAtivo(ticker: 'PETR4'));
    expect(find.text('variação do dia indisponível'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(7)); // preço + 6 estatísticas
  });

  testWidgets('Ver notícias, Comprar e Vender chamam os callbacks e fecham', (
    t,
  ) async {
    final cena = await _abrir(t);
    expect(find.text('Meu radar'), findsNothing);
    await t.tap(find.text('Comprar'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['comprar']);
    expect(find.byKey(const Key('grafico-dialogo')), findsNothing);

    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Vender'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['comprar', 'vender']);

    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ver notícias'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['comprar', 'vender', 'noticias']);
    expect(find.byKey(const Key('grafico-dialogo')), findsNothing);
  });

  testWidgets('sem custódia não há Vender; Fechar não chama nada', (t) async {
    final cena = await _abrir(t, comVender: false);
    expect(find.text('Vender'), findsNothing);
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grafico-dialogo')), findsNothing);
    expect(cena.chamadas, isEmpty);
  });

  testWidgets('amigo: importar quando não tenho, nada de comprar', (t) async {
    final cena = await _abrir(
      t,
      amigo: true,
      jaTenho: false,
      comComprar: false,
      comVender: false,
    );
    expect(find.text('Comprar'), findsNothing);
    await t.tap(find.text('Meu radar'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['importar']);
  });

  testWidgets('amigo com o ativo já no meu radar não mostra importar', (
    t,
  ) async {
    await _abrir(t, amigo: true, jaTenho: true, comComprar: false);
    expect(find.text('Meu radar'), findsNothing);
  });

  testWidgets('Esc fecha o diálogo', (t) async {
    await _abrir(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grafico-dialogo')), findsNothing);
  });

  testWidgets('compacto abre em tela cheia', (t) async {
    final cena = await _abrir(t, tamanho: _celular);
    expect(find.byKey(const Key('grafico-tela')), findsOneWidget);
    expect(find.byKey(const Key('grafico-dialogo')), findsNothing);
    expect(
      find.text('Toque no gráfico para ver o preço de cada ponto'),
      findsOneWidget,
    );
    expect(_linha(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Ver notícias'));
    await t.tap(find.text('Ver notícias'));
    await t.pumpAndSettle();
    expect(cena.chamadas, ['noticias']);
    expect(find.byKey(const Key('grafico-tela')), findsNothing);
  });

  testWidgets('radar abre o gráfico ao tocar na linha e Ver notícias vai '
      'para Notícias filtrada', (t) async {
    final s = ServicosFalsos()
      ..cotacoesFalsas = {
        'PETR4': CotacaoOk(_dados()),
        'WEGE3': CotacaoOk(_dados('WEGE3')),
        'MXRF11': CotacaoOk(_dados('MXRF11')),
      };
    await montarApp(t, servicos: s, tela: const TelaRadar());
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('linha-radar-WEGE3')),
        matching: find.text('WEG ON'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grafico-dialogo')), findsOneWidget);
    expect(s.chamadas, contains('grafico(WEGE3, 1D)'));

    await t.tap(find.text('Ver notícias'));
    await t.pumpAndSettle();
    final estado = Provider.of<EstadoApp>(
      t.element(find.byType(TelaRadar)),
      listen: false,
    );
    expect(estado.filtroNoticias, 'WEGE3');
    expect(estado.aba, Aba.noticias);
  });
}
