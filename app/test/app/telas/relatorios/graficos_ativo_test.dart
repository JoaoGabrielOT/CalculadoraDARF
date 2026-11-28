import 'package:calculadoradarf/app/componentes/grafico_barras.dart';
import 'package:calculadoradarf/app/componentes/grafico_linha.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/relatorios/cartao_ativo.dart';
import 'package:calculadoradarf/app/telas/relatorios/graficos_ativo.dart';
import 'package:calculadoradarf/app/telas/relatorios/vista_relatorio.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/apoio/fixture_relatorio.dart';
import '../../apoio/montar_componente.dart';
import '../../apoio/servicos_falsos.dart';

const _celular = Size(360, 3000);

AtivoRelatorio _ativo(String ticker) =>
    Relatorio.deJson(fixtureRelatorioGuia()).ativos
        .firstWhere((a) => a.ticker == ticker);

Future<void> _monta(WidgetTester t, ServicosFalsos s, String ticker) =>
    montarComponente(
      t,
      SingleChildScrollView(
        child: CartaoAtivo(_ativo(ticker), aoAbrirLink: (_) {}),
      ),
      tamanho: _celular,
      envolver: (app) => Provider<ServicosApp>.value(value: s, child: app),
    );

Future<void> _abrirGraficos(WidgetTester t) async {
  await t.tap(find.text('Gráficos'));
  await t.pumpAndSettle();
}

int _pedidos(ServicosFalsos s) =>
    s.chamadas.where((c) => c.startsWith('barrasDiarias')).length;

PosicaoAtivo _posicao(String ticker) => PosicaoAtivo(
  ticker: ticker,
  tipo: 'Ação',
  qtd: 100,
  custoGerencial: 5000,
  compras: [
    CompraNaPosicao(
      loteId: 'L1',
      mes: '2026-09',
      dataCompra: '2026-09-02',
      qtdOriginal: 100,
      restante: 100,
      preco: 50,
    ),
  ],
);

void main() {
  late ServicosFalsos s;

  setUp(() {
    ambiente = Ambiente.fixo();
    s = ServicosFalsos();
  });

  tearDown(() => ambiente = Ambiente.sistema());

  group('alvos comparáveis', () {
    const verde = Colors.green, vermelho = Colors.red, cinza = Colors.grey;
    List<BarraGrafico>? alvos(Especialistas e) =>
        barrasDeAlvo(e, null, verde, vermelho, cinza);

    test('mesma moeda: último, médio, mín e máx', () {
      final b = alvos(
        const Especialistas(
          precoReferencia: 'R\$ 56,90 em 26/11',
          alvoMedio: 'R\$ 67,67',
          alvoMin: 'R\$ 60,00',
          alvoMax: 'R\$ 72,00',
        ),
      )!;
      expect(b.map((x) => x.rotulo), [
        'Último preço',
        'Alvo médio',
        'Alvo mín',
        'Alvo máx',
      ]);
      expect(b.map((x) => x.valor), [56.9, 67.67, 60, 72]);
      expect(b[1].texto, 'R\$ 67,67');
      expect(b[1].cor, verde);
    });

    test('US\$ com preço em US\$ entra, com o prefixo certo', () {
      final b = alvos(
        const Especialistas(
          precoReferencia: 'US\$ 149,30 em 25/11',
          alvoMedio: 'US\$ 195,33',
        ),
      )!;
      expect(b.map((x) => x.texto), ['US\$ 149,30', 'US\$ 195,33']);
    });

    test('moedas diferentes ou sem alvo médio: sem gráfico', () {
      expect(
        alvos(
          const Especialistas(
            precoReferencia: 'R\$ 10,00',
            alvoMedio: 'US\$ 12,00',
          ),
        ),
        isNull,
      );
      expect(alvos(const Especialistas(precoReferencia: 'R\$ 10,00')), isNull);
    });

    test('mín em outra moeda fica de fora', () {
      final b = alvos(
        const Especialistas(
          precoReferencia: 'R\$ 10,00',
          alvoMedio: 'R\$ 12,00',
          alvoMin: 'US\$ 9,00',
          alvoMax: 'R\$ 14,00',
        ),
      )!;
      expect(b.map((x) => x.rotulo), [
        'Último preço',
        'Alvo médio',
        'Alvo máx',
      ]);
    });
  });

  group('cartão', () {
    testWidgets('começa em Relatório e não busca nada antes do toque', (
      t,
    ) async {
      await _monta(t, s, 'BPAC11');
      expect(find.text('Relatório'), findsOneWidget);
      expect(find.text('Gráficos'), findsOneWidget);
      expect(find.byType(GraficosAtivo), findsNothing);
      expect(find.byKey(const Key('comparacao-BPAC11')), findsOneWidget);
      expect(_pedidos(s), 0);
      expect(s.chamadas, isEmpty);
    });

    testWidgets('toque em Gráficos busca uma vez e mostra a linha', (t) async {
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(_pedidos(s), 1);
      expect(find.byKey(const Key('graficos-BPAC11')), findsOneWidget);
      expect(find.byType(GraficoLinha), findsOneWidget);
      expect(find.byType(GraficoBarras), findsOneWidget);
      expect(find.byKey(const Key('comparacao-BPAC11')), findsNothing);
      expect(t.takeException(), isNull);
      // voltar e abrir de novo não deixa o gráfico antigo na tela
      await t.tap(find.text('Relatório'));
      await t.pumpAndSettle();
      expect(find.byType(GraficosAtivo), findsNothing);
      expect(find.byKey(const Key('comparacao-BPAC11')), findsOneWidget);
    });

    testWidgets('1 barra: Dados insuficientes para o gráfico', (t) async {
      s.barrasFalsas['BPAC11'] = barrasPadrao(n: 1);
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(find.text('Dados insuficientes para o gráfico'), findsOneWidget);
      expect(find.byType(GraficoLinha), findsNothing);
    });

    testWidgets('erro: mensagem e Tentar de novo', (t) async {
      s.erros['barrasDiarias'] = Exception('sem rede');
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(
        find.text('Não foi possível carregar os gráficos de BPAC11.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      s.erros.remove('barrasDiarias');
      await t.tap(find.text('Tentar de novo'));
      await t.pumpAndSettle();
      expect(_pedidos(s), 2);
      expect(find.text('Tentar de novo'), findsNothing);
      expect(find.byType(GraficoLinha), findsOneWidget);
    });

    testWidgets('carregando: indicador até a resposta', (t) async {
      final espera = Future<Diarias>.delayed(
        const Duration(seconds: 1),
        barrasPadrao,
      );
      s.barrasFn = (_, _) => espera;
      await _monta(t, s, 'BPAC11');
      await t.tap(find.text('Gráficos'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('BPAC11: barras do último preço e dos alvos em R\$', (t) async {
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      for (final x in ['Alvo médio', 'Alvo mín', 'Alvo máx']) {
        expect(find.text(x), findsOneWidget);
      }
      expect(find.text('R\$ 67,67'), findsOneWidget);
      expect(find.text('R\$ 56,90'), findsOneWidget);
    });

    testWidgets('NVDC34: alvos em US\$ com o preço em US\$', (t) async {
      await _monta(t, s, 'NVDC34');
      await _abrirGraficos(t);
      expect(find.text('US\$ 195,33'), findsOneWidget);
      expect(find.text('US\$ 149,30'), findsOneWidget);
    });

    testWidgets('EMBJ3: só os campos agregados, sem o item em US\$', (t) async {
      await _monta(t, s, 'EMBJ3');
      await _abrirGraficos(t);
      expect(find.text('R\$ 123,00'), findsWidgets);
      expect(find.textContaining('US\$'), findsNothing);
    });

    testWidgets('sem posição: só linha e alvos', (t) async {
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(find.text('Preço médio'), findsNothing);
      expect(find.byType(GraficoLinha), findsOneWidget);
    });

    testWidgets('posição aberta: preço médio × último e resultado bruto', (
      t,
    ) async {
      s.posicoesPorMes['2026-10'] = VisaoPosicoes(
        dataCorte: '2026-10-28',
        corrente: true,
        posicoes: [_posicao('BPAC11')],
      );
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      // `posicoes` e as barras saem juntas; a compra de 02/09 não cabe nas
      // barras padrão, então busca de novo com `desde`.
      expect(s.chamadas, contains('barrasDiarias(BPAC11, null)'));
      expect(s.chamadas, contains('barrasDiarias(BPAC11, 2026-09-02)'));
      expect(_pedidos(s), 2);
      // 100 × (10,00 − 50,00) a 100 × (12,90 − 50,00), de 29/09 a 28/10
      expect(
        find.text(
          'Resultado bruto de -R\$ 4.000,00 a -R\$ 3.710,00 entre 29/09 e 28/10',
        ),
        findsOneWidget,
      );
      expect(find.text('Preço médio'), findsOneWidget);
      expect(find.text('R\$ 50,00'), findsOneWidget);
      expect(
        find.text('Resultado bruto da posição desde a compra mais antiga'),
        findsOneWidget,
      );
      // fechamento, resultado: duas linhas; alvos e preço médio: duas barras
      expect(find.byType(GraficoLinha), findsNWidgets(2));
      expect(find.byType(GraficoBarras), findsNWidgets(2));
    });

    testWidgets('falha ao ler a posição não impede os outros gráficos', (
      t,
    ) async {
      s.posicoesFn = (_, _) => Future.error(Exception('x'));
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(find.byType(GraficoLinha), findsOneWidget);
      expect(find.text('Preço médio'), findsNothing);
    });

    testWidgets('Semantics com o resumo do fechamento', (t) async {
      final sem = t.ensureSemantics();
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Fechamento de R\$ 10,00 a R\$ 12,90 entre 29/09 e 28/10'),
        ),
        findsWidgets,
      );
      sem.dispose();
    });

    testWidgets('recorte de 3 meses sobre barras de 6 meses', (t) async {
      s.barrasFalsas['BPAC11'] = barrasPadrao(n: 180);
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      // hoje 28/10: 92 dias antes é 28/07
      expect(find.textContaining('entre 28/07 e 28/10'), findsOneWidget);
    });

    testWidgets('recorte em 31/05 não pula para o mês seguinte', (t) async {
      ambiente = Ambiente.fixo(hoje: '2026-05-31');
      s.barrasFalsas['BPAC11'] = barrasPadrao(n: 180, ate: '2026-05-31');
      await _monta(t, s, 'BPAC11');
      await _abrirGraficos(t);
      expect(find.textContaining('entre 28/02 e 31/05'), findsOneWidget);
    });
  });

  group('na lista', () {
    final relatorio = Relatorio.deJson(fixtureRelatorioGuia());

    Future<void> monta(
      WidgetTester t, {
      Size tamanho = const Size(360, 20000),
    }) => montarComponente(
      t,
      VistaRelatorio(relatorio: relatorio, aoAbrirLink: (_) {}),
      tamanho: tamanho,
      envolver: (app) => Provider<ServicosApp>.value(value: s, child: app),
    );

    testWidgets('filtro que troca o ativo da posição fecha a aba Gráficos', (
      t,
    ) async {
      final primeiro = relatorio.ativos.first.ticker;
      final ultimo = relatorio.ativos.last.ticker;
      await monta(t);
      await t.tap(
        find.descendant(
          of: find.byKey(Key('abas-$primeiro')),
          matching: find.text('Gráficos'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(Key('graficos-$primeiro')), findsOneWidget);
      await t.enterText(find.byKey(const Key('filtro-busca')), ultimo);
      await t.pumpAndSettle();
      expect(find.byKey(Key('graficos-$primeiro')), findsNothing);
      expect(find.byKey(Key('graficos-$ultimo')), findsNothing);
      expect(find.byKey(Key('abas-$ultimo')), findsOneWidget);
      expect(find.byKey(Key('comparacao-$ultimo')), findsOneWidget);
    });

    testWidgets('GraficosAtivo recarrega quando o ativo muda', (t) async {
      final a = relatorio.ativos[0], b = relatorio.ativos[1];
      final ativo = ValueNotifier(a);
      await montarComponente(
        t,
        ValueListenableBuilder(
          valueListenable: ativo,
          builder: (_, v, _) => SingleChildScrollView(child: GraficosAtivo(v)),
        ),
        tamanho: _celular,
        envolver: (app) => Provider<ServicosApp>.value(value: s, child: app),
      );
      await t.pumpAndSettle();
      expect(s.chamadas, contains('barrasDiarias(${a.ticker}, null)'));
      ativo.value = b;
      await t.pumpAndSettle();
      expect(s.chamadas, contains('barrasDiarias(${b.ticker}, null)'));
      expect(find.byKey(Key('graficos-${b.ticker}')), findsOneWidget);
    });

    testWidgets('cartão com Gráficos aberto sobrevive à rolagem', (t) async {
      await monta(t, tamanho: const Size(360, 700));
      final lista = find.byType(Scrollable).first;
      // primeiro cartão da lista (a ordem não é a do JSON)
      final abas = find.byWidgetPredicate(
        (w) => w.key.toString().startsWith("[<'abas-"),
      );
      for (var i = 0; i < 40 && abas.evaluate().isEmpty; i++) {
        await t.drag(lista, const Offset(0, -300));
        await t.pump();
      }
      await t.pumpAndSettle();
      final chave = abas.first.evaluate().single.widget.key!;
      final ticker = (chave as ValueKey<String>).value.substring(5);
      await t.tap(
        find.descendant(of: find.byKey(chave), matching: find.text('Gráficos')),
      );
      await t.pumpAndSettle();
      expect(_pedidos(s), 1);
      // rola para longe (o cartão sai da janela) e volta
      await t.drag(lista, const Offset(0, -6000));
      await t.pumpAndSettle();
      expect(find.byKey(Key('abas-$ticker')), findsNothing);
      await t.drag(lista, const Offset(0, 6000));
      await t.pumpAndSettle();
      expect(find.byKey(Key('graficos-$ticker')), findsOneWidget);
      expect(_pedidos(s), 1);
    });
  });
}
