import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/regras/filtros.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/nucleo/extremos.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 1800);
const _celular = Size(360, 3000);

const _nota = 'Estimativa por compra; não altera o resultado fiscal.';

BarraDiaria _b(String d, double alta, double baixa) =>
    BarraDiaria(data: d, alta: alta, baixa: baixa, fech: (alta + baixa) / 2);

/// PETR4, comprada em 05/10: de 05/10 a 28/10 a máxima é 38 (14/10) e a
/// mínima 5 (21/10). 30/09 e 01/10 são anteriores à compra e 29/10 é depois
/// de hoje; os três ficam de fora.
Diarias _petr4() => Diarias(
  barras: [
    _b('2026-09-30', 99, 1),
    _b('2026-10-01', 50, 2),
    _b('2026-10-14', 38, 30),
    _b('2026-10-21', 36, 5),
    _b('2026-10-29', 90, 2),
  ],
);

const _ext = Extremos(
  maximo: Extremo(preco: 38, data: '2026-10-14'),
  minimo: Extremo(preco: 5, data: '2026-10-21'),
);

Lote _l1() => mesAbertoExemplo().lotes.first;

Future<ServicosFalsos> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  bool windows = true,
}) async {
  final s = servicos ?? ServicosFalsos();
  s.barrasFalsas.putIfAbsent('PETR4', _petr4);
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

ControleApuracao _controle(WidgetTester t) => Provider.of<ControleApuracao>(
  t.element(find.byKey(const Key('tabela-vendas'))),
  listen: false,
);

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaApuracao)), listen: false);

String _ref(Extremos e, String periodo) {
  String dm(String d) => '${d.substring(8)}/${d.substring(5, 7)}';
  return 'máx ${brl(e.maximo.preco)} (${dm(e.maximo.data)}) · '
      'mín ${brl(e.minimo.preco)} (${dm(e.minimo.data)}) · período: $periodo';
}

Finder _em(String chave, String texto) =>
    find.descendant(of: find.byKey(Key(chave)), matching: find.text(texto));

int _chamadas(ServicosFalsos s, String ticker) =>
    s.chamadas.where((c) => c.startsWith('barrasDiarias($ticker,')).length;

/// Troca o relógio e o "hoje" do ambiente, para os testes de expiração.
class _Relogio {
  _Relogio() {
    final base = Ambiente.fixo(hoje: hojeExemplo);
    ambiente = Ambiente(
      agora: () => agora,
      novoId: base.novoId,
      hoje: () => hoje,
      agoraBr: base.agoraBr,
    );
  }

  double agora = 1761000000.0;
  String hoje = hojeExemplo;
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  group('Vendas do mês (PC)', () {
    testWidgets('sem colunas novas na tabela; cartão logo abaixo', (t) async {
      final s = await _montar(t);
      expect(
        find.descendant(
          of: find.byKey(const Key('tabela-vendas')),
          matching: find.byKey(const Key('coluna-10')),
        ),
        findsNothing,
      );
      final lotes = find.byKey(const Key('tabela-lotes'));
      expect(
        find.descendant(of: lotes, matching: find.text('Pior possível')),
        findsNothing,
      );
      final cartao = find.byKey(const Key('extremos-vendas'));
      expect(cartao, findsOneWidget);
      expect(
        _em('extremos-vendas', 'Melhor e pior resultado possível no mês'),
        findsOneWidget,
      );
      expect(_em('extremos-vendas', _nota), findsOneWidget);
      // abaixo da tabela de vendas
      expect(
        t.getTopLeft(cartao).dy,
        greaterThan(t.getBottomLeft(find.byKey(const Key('tabela-vendas'))).dy),
      );
      // uma busca por ticker, desde a compra (que é do meio do mês)
      expect(_chamadas(s, 'PETR4'), 1);
      expect(s.chamadas, contains('barrasDiarias(PETR4, 2026-10-05)'));
    });

    testWidgets('linha da venda: valores como a coluna Resultado e período', (
      t,
    ) async {
      await _montar(t);
      final melhor = resultadoHipotetico(_l1(), 40, _ext.maximo);
      final pior = resultadoHipotetico(_l1(), 40, _ext.minimo);
      expect(pior, lessThan(0));
      const linha = 'extremo-venda-V1';
      expect(
        find.descendant(
          of: find.byKey(const Key(linha)),
          matching: find.textContaining('PETR4 · 20/10/2026'),
        ),
        findsOneWidget,
      );
      expect(_em(linha, 'Melhor possível'), findsOneWidget);
      expect(_em(linha, 'Pior possível'), findsOneWidget);
      // brl puro: sem "+" e cor só no negativo
      final tMelhor = t.widget<Text>(_em(linha, brl(melhor)));
      final tPior = t.widget<Text>(_em(linha, brl(pior)));
      expect(brl(melhor), isNot(contains('+')));
      expect(tMelhor.style?.color, isNull);
      final ctx = t.element(find.byKey(const Key(linha)));
      expect(tPior.style?.color, CoresApp.de(ctx).queda);
      // o período começa na compra (05/10), não no início do mês
      expect(_em(linha, _ref(_ext, '05/10 a 28/10')), findsOneWidget);
    });

    testWidgets('lote comprado antes do mês: período do início do mês', (
      t,
    ) async {
      final base = mesAbertoExemplo();
      final antigo = Lote(
        id: 'A1',
        ticker: 'ITUB4',
        tipo: 'Ação',
        dataCompra: '2026-09-20',
        qtd: 10,
        preco: 30,
        vendas: [Venda(id: 'AV1', data: '2026-10-10', qtd: 10, preco: 31)],
      );
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(mes: base.mes, lotes: [...base.lotes, antigo]),
      );
      s.barrasFalsas['ITUB4'] = Diarias(
        barras: [_b('2026-09-25', 90, 1), _b('2026-10-01', 34, 29)],
      );
      await _montar(t, servicos: s);
      const e = Extremos(
        maximo: Extremo(preco: 34, data: '2026-10-01'),
        minimo: Extremo(preco: 29, data: '2026-10-01'),
      );
      expect(
        _em('extremo-venda-AV1', _ref(e, '01/10 a 28/10')),
        findsOneWidget,
      );
    });

    testWidgets('mês passado inteiro: do início ao último dia do mês', (
      t,
    ) async {
      final s = ServicosFalsos();
      s.barrasFalsas['ITUB4'] = Diarias(
        barras: [
          _b('2026-09-01', 90, 1),
          _b('2026-09-10', 40, 28),
          _b('2026-09-30', 36, 30),
          _b('2026-10-05', 99, 2),
        ],
      );
      await _montar(t, servicos: s);
      _estado(t).trocarMes('2026-09');
      await t.pumpAndSettle();
      const e = Extremos(
        maximo: Extremo(preco: 40, data: '2026-09-10'),
        minimo: Extremo(preco: 28, data: '2026-09-10'),
      );
      final lote = mesFechadoExemplo().lotes.first;
      expect(
        _em('extremo-venda-FV1', _ref(e, '02/09 a 30/09')),
        findsOneWidget,
      );
      expect(
        _em('extremo-venda-FV1', brl(resultadoHipotetico(lote, 100, e.maximo))),
        findsOneWidget,
      );
    });

    testWidgets('sem barras no período ou erro: Indisponível', (t) async {
      final s = ServicosFalsos();
      s.barrasFalsas['PETR4'] = Diarias(barras: [_b('2026-09-10', 40, 30)]);
      await _montar(t, servicos: s);
      expect(_em('extremo-venda-V1', 'Indisponível'), findsNWidgets(2));
      expect(_em('extremos-vendas', _nota), findsOneWidget);

      final e = ServicosFalsos();
      e.erros['barrasDiarias'] = StateError('sem rede');
      await _montar(t, servicos: e);
      expect(_em('extremo-venda-V1', 'Indisponível'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('mostra Carregando… enquanto a busca não volta', (t) async {
      final s = ServicosFalsos();
      final espera = Completer<Diarias>();
      s.barrasFn = (_, _) => espera.future;
      await _montar(t, servicos: s);
      expect(_em('extremo-venda-V1', 'Carregando…'), findsNWidgets(2));
      espera.complete(_petr4());
      await t.pumpAndSettle();
      expect(_em('extremo-venda-V1', 'Carregando…'), findsNothing);
    });

    testWidgets('grupo soma os hipotéticos de cada venda', (t) async {
      final base = mesAbertoExemplo();
      Lote lote(String id, int qtd, double preco, String dia, String v) => Lote(
        id: id,
        ticker: 'ITUB4',
        tipo: 'Ação',
        dataCompra: dia,
        qtd: qtd,
        preco: preco,
        vendas: [Venda(id: v, data: '2026-10-08', qtd: qtd, preco: 31)],
      );
      final a = lote('G-A', 10, 30, '2026-10-02', 'G1.1');
      final b = lote('G-B', 6, 28, '2026-10-02', 'G1.2');
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(mes: base.mes, lotes: [...base.lotes, a, b]),
      );
      s.barrasFalsas['ITUB4'] = Diarias(
        barras: [_b('2026-10-06', 40, 25), _b('2026-10-07', 33, 29)],
      );
      await _montar(t, servicos: s);
      const max = Extremo(preco: 40, data: '2026-10-06');
      const min = Extremo(preco: 25, data: '2026-10-06');
      expect(
        _em(
          'extremo-venda-G1',
          brl(resultadoHipotetico(a, 10, max) + resultadoHipotetico(b, 6, max)),
        ),
        findsOneWidget,
      );
      expect(
        _em(
          'extremo-venda-G1',
          brl(resultadoHipotetico(a, 10, min) + resultadoHipotetico(b, 6, min)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('compacto em 360 px: linhas no cartão, sem overflow', (
      t,
    ) async {
      await _montar(t, tamanho: _celular, windows: false);
      final melhor = resultadoHipotetico(_l1(), 40, _ext.maximo);
      final pior = resultadoHipotetico(_l1(), 40, _ext.minimo);
      expect(_em('cartao-venda-V1', 'Melhor possível'), findsOneWidget);
      expect(_em('cartao-venda-V1', 'Pior possível'), findsOneWidget);
      expect(_em('cartao-venda-V1', brl(melhor)), findsOneWidget);
      expect(_em('cartao-venda-V1', brl(pior)), findsOneWidget);
      expect(
        _em('cartao-venda-V1', _ref(_ext, '05/10 a 28/10')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('extremos-vendas')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('Ativos comprados (PC)', () {
    testWidgets('sem colunas novas; cartão logo abaixo, só lotes com saldo', (
      t,
    ) async {
      final base = mesAbertoExemplo();
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(
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
        ),
      );
      await _montar(t, servicos: s);
      expect(find.byKey(const Key('coluna-11')), findsNothing);
      final cartao = find.byKey(const Key('extremos-lotes'));
      expect(
        _em('extremos-lotes', 'Maior lucro e maior perda possíveis até agora'),
        findsOneWidget,
      );
      expect(_em('extremos-lotes', _nota), findsOneWidget);
      expect(
        t.getTopLeft(cartao).dy,
        greaterThan(t.getBottomLeft(find.byKey(const Key('tabela-lotes'))).dy),
      );
      expect(find.byKey(const Key('extremo-lote-L1')), findsOneWidget);
      expect(find.byKey(const Key('extremo-lote-L2')), findsOneWidget);
      expect(find.byKey(const Key('extremo-lote-L4')), findsNothing);
    });

    testWidgets('linha do lote: saldo, brl puro e período desde a compra', (
      t,
    ) async {
      await _montar(t);
      final lucro = resultadoHipotetico(_l1(), 60, _ext.maximo);
      final perda = resultadoHipotetico(_l1(), 60, _ext.minimo);
      const linha = 'extremo-lote-L1';
      expect(_em(linha, 'Maior lucro possível até agora'), findsOneWidget);
      expect(_em(linha, 'Maior perda possível até agora'), findsOneWidget);
      expect(_em(linha, brl(lucro)), findsOneWidget);
      expect(_em(linha, brl(perda)), findsOneWidget);
      expect(_em(linha, _ref(_ext, '05/10 a 28/10')), findsOneWidget);
    });

    testWidgets('segue o filtro da tabela', (t) async {
      await _montar(t);
      _controle(t).definirFiltroLotes(FiltroLotes(busca: 'VALE'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('extremo-lote-L1')), findsNothing);
      expect(find.byKey(const Key('extremo-lote-L2')), findsOneWidget);
    });

    testWidgets('sem barras: Indisponível', (t) async {
      final s = ServicosFalsos();
      s.barrasFalsas['PETR4'] = Diarias(barras: []);
      await _montar(t, servicos: s);
      expect(_em('extremo-lote-L1', 'Indisponível'), findsNWidgets(2));
    });

    testWidgets('compra de hoje usa o próprio dia', (t) async {
      final base = mesAbertoExemplo();
      final lote = Lote(
        id: 'L9',
        ticker: 'WEGE3',
        tipo: 'Ação',
        dataCompra: hojeExemplo,
        qtd: 10,
        preco: 40,
      );
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(mes: base.mes, lotes: [...base.lotes, lote]),
      );
      s.barrasFalsas['WEGE3'] = Diarias(
        barras: [_b('2026-10-27', 99, 1), _b(hojeExemplo, 42, 39)],
      );
      await _montar(t, servicos: s);
      const alta = Extremo(preco: 42, data: hojeExemplo);
      const baixa = Extremo(preco: 39, data: hojeExemplo);
      expect(
        _em('extremo-lote-L9', brl(resultadoHipotetico(lote, 10, alta))),
        findsOneWidget,
      );
      expect(
        _em('extremo-lote-L9', brl(resultadoHipotetico(lote, 10, baixa))),
        findsOneWidget,
      );
      expect(
        _em(
          'extremo-lote-L9',
          _ref(const Extremos(maximo: alta, minimo: baixa), '28/10 a 28/10'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('compacto em 360 px: linhas no cartão, sem overflow', (
      t,
    ) async {
      await _montar(t, tamanho: _celular, windows: false);
      final lucro = resultadoHipotetico(_l1(), 60, _ext.maximo);
      const c = 'cartao-lote-L1';
      expect(_em(c, 'Maior lucro possível até agora'), findsOneWidget);
      expect(_em(c, 'Maior perda possível até agora'), findsOneWidget);
      expect(_em(c, brl(lucro)), findsOneWidget);
      expect(find.byKey(const Key('extremos-lotes')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('visão de amigo mostra igual e não quebra', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(mesAbertoExemplo(), amigo: 'ana');
      await _montar(t, servicos: s);
      expect(find.byKey(const Key('extremo-lote-L1')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('cache das barras', () {
    testWidgets('erro: tenta de novo na próxima verificação', (t) async {
      final s = ServicosFalsos();
      s.erros['barrasDiarias'] = StateError('sem rede');
      await _montar(t, servicos: s);
      expect(_em('extremo-venda-V1', 'Indisponível'), findsNWidgets(2));
      expect(_chamadas(s, 'PETR4'), 1);
      s.erros.remove('barrasDiarias');
      await t.pump(const Duration(seconds: 60));
      await t.pumpAndSettle();
      expect(_chamadas(s, 'PETR4'), 2);
      expect(_em('extremo-venda-V1', 'Indisponível'), findsNothing);
    });

    testWidgets('antes de 15 min reaproveita; depois refaz sem piscar', (
      t,
    ) async {
      final r = _Relogio();
      final s = ServicosFalsos();
      await _montar(t, servicos: s);
      expect(_chamadas(s, 'PETR4'), 1);
      r.agora += 14 * 60;
      await t.pump(const Duration(seconds: 60));
      expect(_chamadas(s, 'PETR4'), 1);

      // passou de 15 min: refaz, e as barras antigas continuam à vista
      r.agora += 2 * 60;
      final espera = Completer<Diarias>();
      s.barrasFn = (_, _) => espera.future;
      await t.pump(const Duration(seconds: 60));
      expect(_chamadas(s, 'PETR4'), 2);
      expect(_em('extremo-venda-V1', 'Carregando…'), findsNothing);
      expect(_em('extremo-venda-V1', 'Indisponível'), findsNothing);
      final melhor = resultadoHipotetico(_l1(), 40, _ext.maximo);
      expect(_em('extremo-venda-V1', brl(melhor)), findsOneWidget);
      // a resposta nova troca os valores
      espera.complete(
        Diarias(barras: [_b('2026-10-14', 50, 30), _b('2026-10-21', 36, 5)]),
      );
      await t.pumpAndSettle();
      const novo = Extremo(preco: 50, data: '2026-10-14');
      expect(
        _em('extremo-venda-V1', brl(resultadoHipotetico(_l1(), 40, novo))),
        findsOneWidget,
      );
    });

    testWidgets('troca do dia refaz a busca', (t) async {
      final r = _Relogio();
      final s = ServicosFalsos();
      await _montar(t, servicos: s);
      r.hoje = '2026-10-29';
      await t.pump(const Duration(seconds: 60));
      expect(_chamadas(s, 'PETR4'), 2);
    });

    testWidgets('trocar de mês reaproveita o cache que já cobre o período', (
      t,
    ) async {
      final s = ServicosFalsos();
      s.visoes['2026-09'] = visaoExemplo(
        Mes(
          mes: '2026-09',
          fechado: true,
          lotes: [
            Lote(
              id: 'P1',
              ticker: 'PETR4',
              tipo: 'Ação',
              dataCompra: '2026-09-10',
              qtd: 10,
              preco: 30,
              vendas: [
                Venda(id: 'PV1', data: '2026-09-20', qtd: 10, preco: 31),
              ],
            ),
          ],
        ),
      );
      await _montar(t, servicos: s);
      expect(_chamadas(s, 'PETR4'), 1);
      // setembro precisa de data mais antiga: busca de novo
      _estado(t).trocarMes('2026-09');
      await t.pumpAndSettle();
      expect(_chamadas(s, 'PETR4'), 2);
      // outubro já está coberto pelas barras de setembro: sem nova busca
      _estado(t).trocarMes('2026-10');
      await t.pumpAndSettle();
      expect(_chamadas(s, 'PETR4'), 2);
      expect(find.byKey(const Key('extremo-venda-V1')), findsOneWidget);
      expect(_em('extremo-venda-V1', 'Carregando…'), findsNothing);
    });

    testWidgets('resposta atrasada de outro mês é ignorada', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-09'] = visaoExemplo(
        Mes(
          mes: '2026-09',
          fechado: true,
          lotes: [
            Lote(
              id: 'P1',
              ticker: 'PETR4',
              tipo: 'Ação',
              dataCompra: '2026-09-10',
              qtd: 10,
              preco: 30,
              vendas: [
                Venda(id: 'PV1', data: '2026-09-20', qtd: 10, preco: 31),
              ],
            ),
          ],
        ),
      );
      final pedidos = <String?, Completer<Diarias>>{};
      s.barrasFn = (_, desde) => (pedidos[desde] = Completer<Diarias>()).future;
      await _montar(t, servicos: s);
      final outubro = pedidos['2026-10-05']!;
      _estado(t).trocarMes('2026-09');
      await t.pumpAndSettle();
      final setembro = pedidos['2026-09-10']!;
      setembro.complete(
        Diarias(barras: [_b('2026-09-15', 40, 28), _b('2026-09-25', 36, 30)]),
      );
      await t.pumpAndSettle();
      // a de outubro chega depois e não pode sobrescrever
      outubro.complete(Diarias(barras: [_b('2026-10-14', 38, 5)]));
      await t.pumpAndSettle();
      final lote = Lote(
        id: 'P1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-09-10',
        qtd: 10,
        preco: 30,
      );
      const alta = Extremo(preco: 40, data: '2026-09-15');
      expect(
        _em('extremo-venda-PV1', brl(resultadoHipotetico(lote, 10, alta))),
        findsOneWidget,
      );
      expect(_em('extremo-venda-PV1', 'Indisponível'), findsNothing);
    });

    testWidgets('memoiza a análise e invalida quando as barras mudam', (
      t,
    ) async {
      final r = _Relogio();
      final s = ServicosFalsos();
      await _montar(t, servicos: s);
      final c = _controle(t);
      final g = agruparVendas(c.visao!.apuracao.ops).first;
      final lote = c.visao!.dados.lotes.first;
      final v1 = c.analiseVenda(g);
      final l1 = c.analiseLote(lote);
      expect(identical(c.analiseVenda(g), v1), isTrue);
      expect(identical(c.analiseLote(lote), l1), isTrue);
      // barras novas (depois de 15 min) invalidam
      r.agora += 16 * 60;
      s.barrasFalsas['PETR4'] = Diarias(
        barras: [_b('2026-10-14', 50, 30), _b('2026-10-21', 36, 5)],
      );
      await t.pump(const Duration(seconds: 60));
      await t.pumpAndSettle();
      expect(identical(c.analiseVenda(g), v1), isFalse);
      expect(identical(c.analiseLote(lote), l1), isFalse);
    });
  });
}
