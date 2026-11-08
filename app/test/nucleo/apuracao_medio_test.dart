import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/apuracao_medio.dart';
import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:flutter_test/flutter_test.dart';

Lote _lote(
  String id,
  String ticker,
  String data,
  int qtd,
  double preco, {
  String? origem,
  List<Venda>? vendas,
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: tipoPorTicker(ticker),
  dataCompra: data,
  qtd: qtd,
  preco: preco,
  origem: origem,
  vendas: vendas,
);

Venda _v(String id, String data, int qtd, double preco) =>
    Venda(id: id, data: data, qtd: qtd, preco: preco);

/// Mês por custo médio com a posição inicial e o prejuízo dados.
Mes _mes(
  String mes,
  List<Lote> lotes,
  Map<String, (int, double)> posicao, {
  double comum = 0,
  double dayTrade = 0,
}) => Mes(
  mes: mes,
  lotes: lotes,
  metodo: metodoCustoMedio,
  posicaoInicial: {
    for (final e in posicao.entries)
      e.key: PosicaoFiscal(qtd: e.value.$1, custo: e.value.$2),
  },
  prejuizoAnterior: PrejuizoAcumulado(comum: comum, dayTrade: dayTrade),
);

double _soma(Iterable<double> xs) => xs.fold(0.0, (s, x) => s + x);

/// PETR4 com 100 levadas a R$ 1.000,00; em 03-10 compras X 100 @ 10,00 e
/// Y 100 @ 11,00 e as vendas dadas, todas @ 12,00.
Mes _casoDt(
  List<(String loteId, String vendaId, int qtd)> vendas, {
  double comum = 0,
  double dayTrade = 0,
}) {
  final lotes = [
    _lote('P0', 'PETR4', '2026-02-10', 100, 10.0, origem: 'P'),
    _lote('X', 'PETR4', '2026-03-10', 100, 10.0),
    _lote('Y', 'PETR4', '2026-03-10', 100, 11.0),
  ];
  for (final (loteId, vendaId, q) in vendas) {
    lotes
        .firstWhere((l) => l.id == loteId)
        .vendas
        .add(_v(vendaId, '2026-03-10', q, 12.0));
  }
  return _mes(
    '2026-03',
    lotes,
    {'PETR4': (100, 1000.00)},
    comum: comum,
    dayTrade: dayTrade,
  );
}

void main() {
  setUp(() => corretagemPorOrdem = 0.0);
  tearDown(() => corretagemPorOrdem = 0.0);

  test('comum por custo médio, isento', () {
    // Posição 100 por 1.000,30. Compra 100 @ 12,00 em 03-10:
    //   custo += round(100 × 12 × 1,0003, 2) = 1.200,36 → {200, 2.200,66}.
    // Venda 100 @ 13,00 em 03-20 (sem compra no dia, tudo comum):
    //   custo baixado = round(100 × 2.200,66 / 200, 2) = 1.100,33;
    //   resultado = 1.300 − 1.100,33 − 1.300 × 0,0003 (0,39) = 199,28.
    // Vendas de ações 1.300 ≤ 20.000 → isento.
    final d = _mes(
      '2026-03',
      [
        _lote('P0', 'PETR4', '2026-02-05', 100, 10.0, origem: 'P'),
        _lote(
          'N',
          'PETR4',
          '2026-03-10',
          100,
          12.0,
          vendas: [_v('V', '2026-03-20', 100, 13.0)],
        ),
      ],
      {'PETR4': (100, 1000.30)},
    );
    final r = apurarCustoMedio(d);
    final o = r.ops.single;
    expect(o.custoFiscal, closeTo(1100.33, 1e-9));
    expect(o.resultadoFiscal, closeTo(199.28, 1e-9));
    expect(o.liquido, closeTo(199.28, 1e-9));
    expect(o.compra, closeTo(1100.33, 1e-9));
    expect(o.qtdDt, 0);
    expect(o.dt, isFalse);
    expect(o.regime, 'Swing (isento)');
    expect(r.isento, isTrue);
    expect(r.vendasAcoesSt, closeTo(1300, 1e-9));
    expect(r.impSt, 0);
    expect(r.metodo, metodoCustoMedio);
    expect(r.posicaoFinal!['PETR4']!.qtd, 100);
    expect(r.posicaoFinal!['PETR4']!.custo, closeTo(1100.33, 1e-9));
    expect(r.inconsistentes, isEmpty);
  });

  test('comum tributável com compensação', () {
    // VALE3 {1.000, 50.015,00}, prejuízo comum anterior 1.000.
    // Venda 500 @ 60,00: baixado = round(500 × 50.015 / 1.000, 2) = 25.007,50;
    //   resultado = 30.000 − 25.007,50 − 30.000 × 0,0003 (9,00) = 4.983,50.
    // 30.000 > 20.000 → tributável. Compensa 1.000:
    //   impSt = (4.983,50 − 1.000) × 15% = 597,525.
    // IRRF = 30.000 × 0,005% = 1,50 (> R$ 1, retido).
    final d = _mes(
      '2026-04',
      [
        _lote(
          'V0',
          'VALE3',
          '2026-01-15',
          1000,
          50.0,
          origem: 'V',
          vendas: [_v('S', '2026-04-20', 500, 60.0)],
        ),
      ],
      {'VALE3': (1000, 50015.00)},
      comum: 1000,
    );
    final r = apurarCustoMedio(d);
    expect(r.ops.single.resultadoFiscal, closeTo(4983.50, 1e-9));
    expect(r.ops.single.regime, 'Swing');
    expect(r.isento, isFalse);
    expect(r.compensadoComum, closeTo(1000, 1e-9));
    expect(r.impSt, closeTo(597.525, 1e-9));
    expect(r.impDt, 0);
    expect(r.irrf, closeTo(1.50, 1e-9));
    expect(r.prejuizoComumFinal, closeTo(0, 1e-9));
    expect(r.prejuizoDtFinal, 0);
    expect(r.darfMes, closeTo(597.525 - 1.50, 1e-9));
    expect(r.posicaoFinal!['VALE3']!.qtd, 500);
    expect(r.posicaoFinal!['VALE3']!.custo, closeTo(25007.50, 1e-9));
  });

  test('day trade com compras de lotes diferentes e estoque anterior '
      'desconsiderado', () {
    // Dia 03-10: B = 200 (X 100 @ 10 + Y 100 @ 11), S = 150 (100 da cópia
    // antiga + 50 de X, @ 12). dt = min(200, 150) = 150: a venda da cópia
    // antiga também é day trade (o estoque anterior não conta).
    //   pc = 2.100 / 200 = 10,50; pv = 1.800 / 150 = 12,00.
    //   DT = 150 × 12 − 150 × 10,50 − (1.800 + 1.575) × 0,023% =
    //        1.800 − 1.575 − 0,77625 = 224,22375. impDt = 20% = 44,84475.
    // Sobram 50 compradas: custo += round(50 × 10,50 × 1,0003, 2) = 525,16
    //   → posição {150, 1.525,16}.
    final r = apurarCustoMedio(_casoDt([('P0', 'A', 100), ('X', 'B', 50)]));
    expect(r.ops.map((o) => o.regime), ['Day trade', 'Day trade']);
    expect(r.ops.map((o) => o.dt), [true, true]);
    expect(r.ops.map((o) => o.qtdDt), [100, 50]);
    expect(
      _soma(r.ops.map((o) => o.resultadoFiscal!)),
      closeTo(224.22375, 1e-9),
    );
    // atribuição por quantidade: 100/150 e 50/150 do resultado do dia
    expect(r.ops[0].resultadoFiscal, closeTo(224.22375 * 100 / 150, 1e-9));
    expect(r.impDt, closeTo(44.84475, 1e-9));
    expect(r.impSt, 0);
    expect(r.vendasAcoesSt, 0);
    expect(r.posicaoFinal!['PETR4']!.qtd, 150);
    expect(r.posicaoFinal!['PETR4']!.custo, closeTo(1525.16, 1e-9));
    expect(r.inconsistentes, isEmpty);
  });

  test('misto: day trade e comum no mesmo dia e no mesmo ativo', () {
    // Duas vendas no dia 03-10 @ 12,00: 150 (cópia 100 + X 50) e 100
    // (X 50 + Y 50). B = 200, S = 250 → dt = 200, comum = 50.
    //   DT = 200 × 12 − 200 × 10,50 − (2.400 + 2.100) × 0,023% =
    //        2.400 − 2.100 − 1,035 = 298,965.
    //   Comum: baixado = round(50 × 1.000 / 100, 2) = 500,00;
    //          resultado = 600 − 500 − 600 × 0,03% (0,18) = 99,82.
    // Fração DT = 200/250 = 0,8 em cada linha: 80, 40, 40, 40.
    // Posição {100 − 50, 1.000 − 500} = {50, 500,00}.
    final r = apurarCustoMedio(
      _casoDt([
        ('P0', 'A.1', 100),
        ('X', 'A.2', 50),
        ('X', 'B.1', 50),
        ('Y', 'B.2', 50),
      ]),
    );
    expect(r.ops.map((o) => o.regime).toSet(), {'Misto'});
    expect(r.ops.map((o) => o.dt).toSet(), {false});
    expect(r.ops.map((o) => o.qtdDt), [80, 40, 40, 40]);
    expect(r.impDt, closeTo(298.965 * 0.20, 1e-9));
    // comum de ações 600 ≤ 20.000: isento
    expect(r.isento, isTrue);
    expect(r.vendasAcoesSt, closeTo(600, 1e-9));
    expect(r.impSt, 0);
    expect(
      _soma(r.ops.map((o) => o.resultadoFiscal!)),
      closeTo(298.965 + 99.82, 1e-9),
    );
    expect(
      _soma(r.ops.map((o) => o.custoFiscal!)),
      closeTo(200 * 10.5 + 500, 1e-9),
    );
    expect(r.posicaoFinal!['PETR4']!.qtd, 50);
    expect(r.posicaoFinal!['PETR4']!.custo, closeTo(500.00, 1e-9));
    expect(r.inconsistentes, isEmpty);
  });

  group('compensações separadas', () {
    final vendas = [('P0', 'A', 100), ('X', 'B', 50)];

    test('prejuízo de day trade abate o day trade', () {
      // DT 224,22375 com prejuízo DT 300: compensa 224,22375, sobra
      // 300 − 224,22375 = 75,77625, impDt = 0.
      final r = apurarCustoMedio(_casoDt(vendas, dayTrade: 300));
      expect(r.compensadoDt, closeTo(224.22375, 1e-9));
      expect(r.prejuizoDtFinal, closeTo(75.77625, 1e-9));
      expect(r.impDt, closeTo(0, 1e-9));
    });

    test('prejuízo comum não abate o day trade', () {
      final r = apurarCustoMedio(_casoDt(vendas, comum: 500));
      expect(r.impDt, closeTo(44.84475, 1e-9));
      expect(r.compensadoComum, 0);
      expect(r.prejuizoComumFinal, closeTo(500, 1e-9));
      expect(r.compensadoDt, 0);
    });

    test('perda comum aumenta o prejuízo levado', () {
      // ITUB4 {100, 3.000} vendida a 29,00 com prejuízo comum anterior 50:
      //   resultado = 2.900 − 3.000 − 0,87 = −100,87;
      //   prejuízo final = 50 − (−100,87) = 150,87.
      final d = _mes(
        '2026-03',
        [
          _lote(
            'I0',
            'ITUB4',
            '2026-02-01',
            100,
            30.0,
            origem: 'I',
            vendas: [_v('S', '2026-03-05', 100, 29.0)],
          ),
        ],
        {'ITUB4': (100, 3000.00)},
        comum: 50,
        dayTrade: 20,
      );
      final r = apurarCustoMedio(d);
      expect(r.compensadoComum, 0);
      expect(r.prejuizoComumFinal, closeTo(150.87, 1e-9));
      expect(r.prejuizoDtFinal, closeTo(20, 1e-9));
      expect(r.impSt, 0);
      expect(r.posicaoFinal, isEmpty);
    });
  });

  test('mês isento com perda de ações e ganho de BDR', () {
    // ITUB4: 2.900 − 3.000 − 0,87 = −100,87. AAPL34: 5.300 − 5.000 − 1,59 =
    // 298,41. Ações 2.900 ≤ 20.000 → isento, mas a perda de ações entra e o
    // BDR nunca é isento: base = min(−100,87, 0) + 298,41 = 197,54.
    final d = _mes(
      '2026-03',
      [
        _lote(
          'I0',
          'ITUB4',
          '2026-02-01',
          100,
          30.0,
          origem: 'I',
          vendas: [_v('S1', '2026-03-05', 100, 29.0)],
        ),
        _lote(
          'A0',
          'AAPL34',
          '2026-02-01',
          100,
          50.0,
          origem: 'A',
          vendas: [_v('S2', '2026-03-06', 100, 53.0)],
        ),
      ],
      {'ITUB4': (100, 3000.00), 'AAPL34': (100, 5000.00)},
    );
    final r = apurarCustoMedio(d);
    expect(r.isento, isTrue);
    expect(r.vendasAcoesSt, 2900);
    expect(r.ops[0].resultadoFiscal, closeTo(-100.87, 1e-9));
    expect(r.ops[1].resultadoFiscal, closeTo(298.41, 1e-9));
    expect(r.ops[0].regime, 'Swing (isento)');
    expect(r.ops[1].regime, 'Swing');
    expect(r.impSt, closeTo(197.54 * 0.15, 1e-9));
  });

  group('limite de isenção', () {
    // PETR4 {1.000, 15.004,50}.
    Mes caso(List<Lote> extra, List<Venda> vendas) => _mes(
      '2026-03',
      [
        _lote('P0', 'PETR4', '2026-02-01', 1000, 15.0, origem: 'P')
          ..vendas.addAll(vendas),
        ...extra,
      ],
      {'PETR4': (1000, 15004.50)},
    );

    test('só a parte comum das ações conta; 20.000 exatos é isento', () {
      // Dia 03-10: compra 100 @ 19,00 e venda de 1.100 @ 20,00 (1.000 da
      // cópia, 100 da compra do dia). dt = 100, comum = 1.000.
      //   Vendas comuns de ações = 1.000 × 20 = 20.000 ≤ 20.000 → isento
      //   (o total vendido, 22.000, passa do limite, mas o day trade não
      //   conta).
      //   Comum = 20.000 − 15.004,50 − 6,00 = 4.989,50 (isento).
      //   DT = 2.000 − 1.900 − (2.000 + 1.900) × 0,023% = 99,103;
      //   impDt = 19,8206.
      //   IRRF: comum 20.000 × 0,005% = 1,00 (não passa de R$ 1); DT
      //   99,103 × 1% = 0,99 → nada retido.
      final r = apurarCustoMedio(
        caso(
          [
            _lote(
              'N',
              'PETR4',
              '2026-03-10',
              100,
              19.0,
              vendas: [_v('G.2', '2026-03-10', 100, 20.0)],
            ),
          ],
          [_v('G.1', '2026-03-10', 1000, 20.0)],
        ),
      );
      expect(r.vendasAcoesSt, closeTo(20000, 1e-9));
      expect(r.isento, isTrue);
      expect(r.impSt, 0);
      expect(r.impDt, closeTo(99.103 * 0.20, 1e-9));
      expect(r.irrf, 0);
      // 1.000 × 100/1.100 = 90,9 e 100 × 100/1.100 = 9,09: maiores restos
      expect(r.ops.map((o) => o.qtdDt), [91, 9]);
      expect(r.ops.map((o) => o.regime).toSet(), {'Misto'});
      expect(r.posicaoFinal, isEmpty);
    });

    test('um centavo acima do limite tributa', () {
      // 1.000 @ 20,01 = 20.010 > 20.000:
      //   resultado = 20.010 − 15.004,50 − 6,003 = 4.999,497;
      //   impSt = 749,92455.
      final r = apurarCustoMedio(
        caso([], [_v('S', '2026-03-10', 1000, 20.01)]),
      );
      expect(r.isento, isFalse);
      expect(r.impSt, closeTo(4999.497 * 0.15, 1e-9));
    });
  });

  test('vender tudo zera o custo exatamente', () {
    // {3, 10,00} vendida 1 a 1: round(10/3, 2) = 3,33 → {2, 6,67};
    // round(6,67/2, 2) = 3,33 → {1, 3,34}; a última leva o resto, 3,34.
    final d = _mes(
      '2026-03',
      [
        _lote(
          'P0',
          'PETR4',
          '2026-02-01',
          3,
          3.0,
          origem: 'P',
          vendas: [
            _v('A', '2026-03-02', 1, 4.0),
            _v('B', '2026-03-03', 1, 4.0),
            _v('C', '2026-03-04', 1, 4.0),
          ],
        ),
      ],
      {'PETR4': (3, 10.00)},
    );
    final r = apurarCustoMedio(d);
    expect(r.ops.map((o) => arredondar(o.custoFiscal!, 2)), [3.33, 3.33, 3.34]);
    expect(_soma(r.ops.map((o) => o.custoFiscal!)), closeTo(10.00, 1e-9));
    expect(r.posicaoFinal!.containsKey('PETR4'), isFalse);
  });

  test('venda acima da posição não inventa custo', () {
    // Posição fiscal 10 por 100,00 e venda de 20 @ 12,00: só as 10 cobertas
    // são apuradas (120 − 100 − 0,036), as outras 10 não ganham custo.
    final d = _mes(
      '2026-03',
      [
        _lote(
          'P0',
          'PETR4',
          '2026-02-01',
          20,
          10.0,
          origem: 'P',
          vendas: [_v('S', '2026-03-05', 20, 12.0)],
        ),
      ],
      {'PETR4': (10, 100.00)},
    );
    final r = apurarCustoMedio(d);
    expect(r.inconsistentes, ['PETR4']);
    expect(r.ops.single.custoFiscal, closeTo(100.00, 1e-9));
    expect(r.ops.single.resultadoFiscal, closeTo(120 - 100 - 0.036, 1e-9));
    expect(r.posicaoFinal!.containsKey('PETR4'), isFalse);
    expect(
      avisoSaldoInconsistente('PETR4'),
      'Saldo inconsistente em PETR4: confira as vendas',
    );
  });

  test('saldo dos lotes diferente da posição fiscal é inconsistente', () {
    final d = _mes(
      '2026-03',
      [_lote('P0', 'PETR4', '2026-02-01', 100, 10.0, origem: 'P')],
      {'PETR4': (90, 900.00)},
    );
    expect(apurarCustoMedio(d).inconsistentes, ['PETR4']);
  });

  test('posição inicial derivada usa a qtd levada, não o restante', () {
    // Cópia levada de 100 @ 10,00 com venda de 40 no próprio mês; a compra
    // nova do mês (VALE3) não entra na posição inicial.
    //   custo = round(100 × 10 × 1,0003, 2) = 1.000,30.
    final d = Mes(
      mes: '2026-03',
      lotes: [
        _lote(
          'P0',
          'PETR4',
          '2026-02-10',
          100,
          10.0,
          origem: 'P',
          vendas: [_v('S', '2026-03-15', 40, 12.0)],
        ),
        _lote('N', 'VALE3', '2026-03-02', 10, 11.0),
        _lote('B0', 'BBAS3', '2026-01-20', 30, 20.0),
      ],
    );
    final p = posicaoInicialDerivada(d);
    expect(p.keys, ['BBAS3', 'PETR4']);
    expect(p['PETR4']!.qtd, 100);
    expect(p['PETR4']!.custo, closeTo(1000.30, 1e-9));
    expect(p['BBAS3']!.qtd, 30);
    expect(p['BBAS3']!.custo, closeTo(600.18, 1e-9));
    marcarCustoMedio(d);
    expect(d.metodo, metodoCustoMedio);
    expect(d.prejuizoAnterior!.comum, 0);
    expect(d.prejuizoAnterior!.dayTrade, 0);
    final r = apurar(d);
    final restantePetr = d.lotes
        .where((l) => l.ticker == 'PETR4')
        .fold(0, (s, l) => s + restante(l));
    expect(restantePetr, 60);
    expect(r.posicaoFinal!['PETR4']!.qtd, restantePetr);
    expect(r.posicaoFinal!['BBAS3']!.qtd, 30);
    expect(r.posicaoFinal!['VALE3']!.qtd, 10);
    expect(r.inconsistentes, isEmpty);
  });

  test('marcarCustoMedio grava o prejuízo dado', () {
    final d = Mes(mes: '2026-03');
    marcarCustoMedio(d, prejuizo: PrejuizoAcumulado(comum: 10, dayTrade: 5));
    expect(d.posicaoInicial, isEmpty);
    expect(d.prejuizoAnterior!.comum, 10);
    expect(d.prejuizoAnterior!.dayTrade, 5);
  });

  test('corretagem rateada por quantidade entre day trade e comum', () {
    // corretagem 10 por ordem. Dia 03-10: compra N 100 @ 11 (1 ordem) e o
    // grupo g de 150 @ 12 (1 ordem: g.1 da cópia, g.2 de N). B = 100,
    // S = 150, dt = 100.
    //   corretagem DT = 10 × 100/100 + 10 × 100/150;
    //   DT = 1.200 − 1.100 − 2.300 × 0,023% − corretagem DT.
    //   Comum (50): baixado 500; 600 − 500 − 0,18 − 10 × 50/150.
    corretagemPorOrdem = 10.0;
    final d = _mes(
      '2026-03',
      [
        _lote(
          'P0',
          'PETR4',
          '2026-02-01',
          100,
          10.0,
          origem: 'P',
          vendas: [_v('g.1', '2026-03-10', 100, 12.0)],
        ),
        _lote(
          'N',
          'PETR4',
          '2026-03-10',
          100,
          11.0,
          vendas: [_v('g.2', '2026-03-10', 50, 12.0)],
        ),
      ],
      {'PETR4': (100, 1000.00)},
    );
    final r = apurarCustoMedio(d);
    final dt = 1200 - 1100 - 2300 * 0.00023 - (10 + 10 * 100 / 150);
    final comum = 600 - 500 - 0.18 - 10 * 50 / 150;
    expect(r.impDt, closeTo(dt * 0.20, 1e-9));
    expect(
      _soma(r.ops.map((o) => o.resultadoFiscal!)),
      closeTo(dt + comum, 1e-9),
    );
    expect(r.posicaoFinal!['PETR4']!.custo, closeTo(500.00, 1e-9));
  });

  group('despacho e corte', () {
    test('mês sem marcador usa o método por compra sem mudança', () {
      final d = Mes(
        mes: '2026-03',
        lotes: [
          _lote(
            'A',
            'PETR4',
            '2026-03-02',
            100,
            10.0,
            vendas: [_v('S', '2026-03-10', 60, 12.0)],
          ),
        ],
      );
      final r = apurar(d);
      expect(r.metodo, isNull);
      expect(r.posicaoFinal, isNull);
      expect(r.toJson(), apurarPorCompra(d).toJson());
      expect(r.ops.single.resultadoFiscal, isNull);
    });

    test('mês marcado vai para o custo médio', () {
      final d = _casoDt([('P0', 'A', 100)]);
      expect(apurar(d).metodo, metodoCustoMedio);
    });

    test('mesDeCorte e usaCustoMedio', () {
      final fev = Mes(mes: '2026-02', fechado: true);
      final mar = Mes(mes: '2026-03', fechado: true, metodo: metodoCustoMedio);
      final abr = Mes(mes: '2026-04');
      final mai = Mes(mes: '2026-05', metodo: metodoCustoMedio);
      expect(mesDeCorte([fev, abr]), isNull);
      expect(mesDeCorte([mai, abr, mar, fev]), '2026-03');
      final corte = mesDeCorte([fev, mar, abr, mai]);
      expect(usaCustoMedio(fev, corte), isFalse); // fechado sem marcador
      expect(usaCustoMedio(mar, corte), isTrue);
      expect(usaCustoMedio(abr, corte), isTrue); // aberto depois do corte
      expect(usaCustoMedio(Mes(mes: '2026-01'), corte), isFalse);
      expect(usaCustoMedio(abr, null), isFalse);
    });
  });
}
