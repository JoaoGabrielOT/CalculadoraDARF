import 'package:calculadoradarf/nucleo/compat/json_python.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/posicoes.dart';
import 'package:flutter_test/flutter_test.dart';

Lote _lote(String id, {String? origem, int qtd = 100, List<Venda>? vendas}) =>
    Lote(
      id: id,
      origem: origem,
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-01-05',
      qtd: qtd,
      preco: 10.0,
      vendas: vendas,
    );

Venda _venda(String id, String data, int qtd) =>
    Venda(id: id, data: data, qtd: qtd, preco: 12.0);

Mes _mes(
  String mes,
  List<Lote> lotes, {
  bool fechado = true,
  bool retro = false,
}) => Mes(mes: mes, fechado: fechado, retroativo: retro, lotes: lotes);

/// L1 comprado em janeiro e levado por cópias até [ate] meses.
Map<String, Mes> _cadeia(List<String> copias, {List<Venda>? vendasJan}) => {
  '2026-01': _mes('2026-01', [_lote('L1', vendas: vendasJan)]),
  for (final m in copias) m: _mes(m, [_lote('L1~$m', origem: 'L1')]),
};

void main() {
  test('posição aberta aparece em mês sem movimentação e sem arquivo', () {
    final meses = _cadeia(['2026-02']);
    final p = posicoesEm(meses, '2026-03-31').single;
    expect(p.ticker, 'PETR4');
    expect(p.qtd, 100);
    expect(p.custoGerencial, 1000.0);
    expect(p.custoPorCompra, isTrue);
    expect(p.precoMedio, 10.0);
  });

  test('cópias levadas não somam compra', () {
    final meses = _cadeia(['2026-02', '2026-03', '2026-04']);
    expect(posicoesEm(meses, '2026-04-30').single.qtd, 100);
  });

  test('compra futura ausente da posição anterior', () {
    final meses = {
      '2026-02': _mes('2026-02', [
        Lote(
          id: 'L2',
          ticker: 'VALE3',
          tipo: 'Ação',
          dataCompra: '2026-02-10',
          qtd: 10,
          preco: 50,
        ),
      ]),
    };
    expect(posicoesEm(meses, '2026-01-31'), isEmpty);
    expect(posicoesEm(meses, '2026-02-10').single.qtd, 10);
  });

  test('posição encerrada visível nos meses certos', () {
    final meses = _cadeia(['2026-02']);
    meses['2026-03'] = _mes('2026-03', [
      _lote(
        'L1~2026-03',
        origem: 'L1',
        vendas: [_venda('V1', '2026-03-05', 100)],
      ),
    ]);
    expect(posicoesEm(meses, '2026-02-28').single.qtd, 100);
    expect(posicoesEm(meses, '2026-03-31'), isEmpty);
  });

  test('venda parcial conta só até a data', () {
    final meses = _cadeia(['2026-02']);
    meses['2026-02'] = _mes('2026-02', [
      _lote(
        'L1~2026-02',
        origem: 'L1',
        vendas: [_venda('V1', '2026-02-15', 40)],
      ),
    ]);
    expect(posicoesEm(meses, '2026-02-10').single.qtd, 100);
    final p = posicoesEm(meses, '2026-02-28').single;
    expect(p.qtd, 60);
    expect(p.compras.single.restante, 60);
  });

  test('retroativo forma cadeia própria', () {
    // venda retroativa sobre a compra do próprio mês aberto: o lote original
    // perde 40 e o novo lote (sem origem) nasce comprado e vendido
    final meses = {
      '2026-03': _mes('2026-03', [_lote('L1', qtd: 60)]),
      '2026-02': _mes('2026-02', [
        _lote('R1', qtd: 40, vendas: [_venda('V1', '2026-02-20', 40)]),
      ]),
    };
    expect(posicoesEm(meses, '2026-02-28').single.qtd, 60);
    expect(posicoesEm(meses, '2026-02-10').single.qtd, 100);
    expect(posicoesEm(meses, '2026-03-31').single.qtd, 60);
  });

  test('retroativo com origem não altera a cadeia original', () {
    final meses = _cadeia(['2026-03']);
    meses['2026-03']!.lotes.single.qtd = 60;
    meses['2026-02'] = _mes('2026-02', [
      _lote(
        'R1',
        origem: 'L1',
        qtd: 40,
        vendas: [_venda('V1', '2026-02-20', 40)],
      ),
    ]);
    expect(posicoesEm(meses, '2026-02-10').single.qtd, 100);
    expect(posicoesEm(meses, '2026-03-31').single.qtd, 60);
  });

  test('cadeia sem lote raiz usa a qtd do lote mais antigo', () {
    final meses = {
      '2026-02': _mes('2026-02', [_lote('L1~2026-02', origem: 'L1', qtd: 70)]),
      '2026-03': _mes('2026-03', [_lote('L1~2026-03', origem: 'L1', qtd: 70)]),
    };
    expect(posicoesEm(meses, '2026-03-31').single.qtd, 70);
  });

  test('reconstrução sem efeitos', () {
    final meses = _cadeia(['2026-02']);
    final antes = {
      for (final e in meses.entries) e.key: jsonPython(e.value.toJson()),
    };
    posicoesEm(meses, '2026-03-31');
    final depois = {
      for (final e in meses.entries) e.key: jsonPython(e.value.toJson()),
    };
    expect(depois, antes);
  });

  group('mês aberto', () {
    // jan e fev fechados; mar aberto com a cópia L1~2026-03
    Map<String, Mes> base() => {
      '2026-01': _mes('2026-01', [_lote('L1')]),
      '2026-02': _mes('2026-02', [_lote('L1~2026-02', origem: 'L1')]),
      '2026-03': _mes('2026-03', [
        _lote('L1~2026-03', origem: 'L1'),
      ], fechado: false),
    };

    test('cópia excluída no mês aberto zera hoje e preserva o histórico', () {
      final meses = base();
      meses['2026-03']!.lotes.clear();
      expect(posicoesEm(meses, '2026-03-20'), isEmpty);
      expect(posicoesEm(meses, '2026-04-10'), isEmpty);
      expect(posicoesEm(meses, '2026-02-28').single.qtd, 100);
    });

    test('vendida e depois excluída não ressuscita', () {
      final meses = base();
      meses['2026-02'] = _mes('2026-02', [
        _lote(
          'L1~2026-02',
          origem: 'L1',
          vendas: [_venda('V1', '2026-02-15', 100)],
        ),
      ]);
      meses['2026-03']!.lotes.clear();
      expect(posicoesEm(meses, '2026-03-20'), isEmpty);
      expect(posicoesEm(meses, '2026-02-10').single.qtd, 100);
      expect(posicoesEm(meses, '2026-02-28'), isEmpty);
    });

    test('qtd e preço editados no mês aberto valem hoje', () {
      final meses = base();
      meses['2026-03']!.lotes.single
        ..qtd = 80
        ..preco = 11.0;
      final p = posicoesEm(meses, '2026-03-20').single;
      expect(p.qtd, 80);
      expect(p.custoGerencial, 880.0);
      expect(p.compras.single.preco, 11.0);
      expect(posicoesEm(meses, '2026-02-28').single.qtd, 100);
    });

    test('corte hoje coincide com a carteira do mês aberto', () {
      final meses = base();
      meses['2026-03']!.lotes
        ..first.vendas.add(_venda('V1', '2026-03-05', 30))
        ..add(
          Lote(
            id: 'L9',
            ticker: 'VALE3',
            tipo: 'Ação',
            dataCompra: '2026-03-02',
            qtd: 5,
            preco: 50,
          ),
        )
        ..add(_lote('L8', qtd: 10, vendas: [_venda('V2', '2026-03-06', 10)]));
      final pos = posicoesEm(meses, '2026-03-20');
      expect({for (final p in pos) p.ticker: p.qtd}, {'PETR4': 70, 'VALE3': 5});
    });
  });

  test('cadeia sem raiz ignora lote retroativo mais antigo', () {
    final meses = {
      '2026-02': _mes('2026-02', [
        _lote(
          'R1',
          origem: 'L1',
          qtd: 40,
          vendas: [_venda('V1', '2026-02-20', 40)],
        ),
      ], retro: true),
      '2026-03': _mes('2026-03', [_lote('L1~2026-03', origem: 'L1', qtd: 60)]),
    };
    expect(posicoesEm(meses, '2026-03-31').single.qtd, 20);
    expect(posicoesEm(meses, '2026-02-10').single.qtd, 60);
  });

  test('dois tickers: ordenação e agregação', () {
    final meses = {
      '2026-01': _mes('2026-01', [
        Lote(
          id: 'V',
          ticker: 'VALE3',
          tipo: 'Ação',
          dataCompra: '2026-01-02',
          qtd: 10,
          preco: 50,
        ),
        _lote('P'),
      ]),
    };
    final pos = posicoesEm(meses, '2026-01-31');
    expect([for (final p in pos) p.ticker], ['PETR4', 'VALE3']);
    expect(pos.last.custoGerencial, 500.0);
  });

  test('duas compras do mesmo ticker: ordem e quantidades', () {
    final meses = {
      '2026-01': _mes('2026-01', [
        Lote(
          id: 'B',
          ticker: 'PETR4',
          tipo: 'Ação',
          dataCompra: '2026-01-20',
          qtd: 50,
          preco: 12,
        ),
        _lote('A', vendas: [_venda('V1', '2026-01-25', 30)]),
      ]),
    };
    final p = posicoesEm(meses, '2026-01-31').single;
    expect([for (final c in p.compras) c.loteId], ['A', 'B']);
    expect(p.compras.first.qtdOriginal, 100);
    expect(p.compras.first.restante, 70);
    expect(p.qtd, 120);
    expect(p.custoGerencial, 70 * 10.0 + 50 * 12.0);
    expect(p.precoMedio, p.custoGerencial / 120);
  });

  test('venda parcial em dois lotes da mesma cadeia', () {
    final meses = _cadeia(
      ['2026-02'],
      vendasJan: [_venda('V1', '2026-01-20', 10)],
    );
    meses['2026-02'] = _mes('2026-02', [
      _lote(
        'L1~2026-02',
        origem: 'L1',
        qtd: 90,
        vendas: [_venda('V2', '2026-02-10', 30)],
      ),
    ]);
    expect(posicoesEm(meses, '2026-01-31').single.qtd, 90);
    expect(posicoesEm(meses, '2026-02-05').single.qtd, 90);
    expect(posicoesEm(meses, '2026-02-28').single.qtd, 60);
  });

  test('dataCorteDoMes', () {
    expect(dataCorteDoMes('2026-02', '2026-11-07'), '2026-02-28');
    expect(dataCorteDoMes('2024-02', '2026-11-07'), '2024-02-29');
    expect(dataCorteDoMes('2026-12', '2026-11-07'), '2026-12-31');
    expect(dataCorteDoMes('2026-11', '2026-11-07'), '2026-11-07');
  });

  group('custo fiscal', () {
    /// 03/2026 aberto pelo custo médio: 100 levadas a R$ 1.000,30; compra X
    /// de 100 a 11,00 em 05/03 e venda de 50 de X a 12,00 em 20/03.
    Map<String, Mes> meses() => {
      '2026-02': _mes('2026-02', [
        Lote(
          id: 'P',
          ticker: 'PETR4',
          tipo: 'Ação',
          dataCompra: '2026-02-10',
          qtd: 100,
          preco: 10.0,
        ),
      ]),
      '2026-03': Mes(
        mes: '2026-03',
        metodo: metodoCustoMedio,
        posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1000.30)},
        prejuizoAnterior: PrejuizoAcumulado(),
        lotes: [
          Lote(
            id: 'P~2026-03',
            origem: 'P',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: '2026-02-10',
            qtd: 100,
            preco: 10.0,
          ),
          Lote(
            id: 'X',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: '2026-03-05',
            qtd: 100,
            preco: 11.0,
            vendas: [_venda('V1', '2026-03-20', 50)],
          ),
        ],
      ),
    };

    test('posição fiscal na data de corte', () {
      // compra: 1000,30 + arredondar(100 × 11 × 1,0003) = 2100,63 (200)
      // venda: baixa arredondar(50 × 2100,63 / 200) = 525,16 → 1575,47 (150)
      final fim = posicoesEm(meses(), '2026-03-31').single;
      expect(fim.qtd, 150);
      expect(fim.custoPorCompra, isFalse);
      expect(fim.custoFiscal, closeTo(1575.47, 1e-9));
      expect(fim.precoMedio, closeTo(1575.47 / 150, 1e-12));
      expect(fim.custoGerencial, 1550.0);
      final antes = posicoesEm(meses(), '2026-03-10').single;
      expect(antes.qtd, 200);
      expect(antes.custoFiscal, closeTo(2100.63, 1e-9));
      final inicio = posicoesEm(meses(), '2026-03-01').single;
      expect(inicio.qtd, 100);
      expect(inicio.custoFiscal, closeTo(1000.30, 1e-9));
    });

    test('mês por compra continua sem custo fiscal', () {
      final fev = posicoesEm(meses(), '2026-02-28').single;
      expect(fev.custoPorCompra, isTrue);
      expect(fev.custoFiscal, isNull);
    });

    Mes abrilSemMarcador() => Mes(
      mes: '2026-04',
      lotes: [
        Lote(
          id: 'P~2026-04',
          origem: 'P',
          ticker: 'PETR4',
          tipo: 'Ação',
          dataCompra: '2026-02-10',
          qtd: 100,
          preco: 10.0,
        ),
      ],
    );

    test('mês aberto sem marcador, sem antecessor pelo custo médio, usa a '
        'posição derivada', () {
      final m = {
        '2026-02': Mes(mes: '2026-02', fechado: true, metodo: metodoCustoMedio),
        '2026-04': abrilSemMarcador(),
      };
      // derivada: arredondar(100 × 10 × 1,0003) = 1000,30
      final p = posicoesEm(m, '2026-04-30').single;
      expect(p.custoFiscal, closeTo(1000.30, 1e-9));
    });

    test('mês aberto sem marcador depois de um fechado pelo custo médio herda '
        'a posição final dele, sem gravar', () {
      final abril = abrilSemMarcador();
      final m = {
        '2026-03': Mes(
          mes: '2026-03',
          fechado: true,
          metodo: metodoCustoMedio,
          posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1234.56)},
          prejuizoAnterior: PrejuizoAcumulado(),
        ),
        '2026-04': abril,
      };
      final antes = jsonPython(abril.toJson());
      // como marcarAoCarregar: a posição final de março, não a derivada
      final p = posicoesEm(m, '2026-04-30').single;
      expect(p.custoFiscal, closeTo(1234.56, 1e-9));
      expect(jsonPython(abril.toJson()), antes);
      expect(abril.metodo, isNull);
    });

    test('quantidade fiscal diferente não inventa custo', () {
      final m = meses();
      m['2026-03']!.posicaoInicial = {
        'PETR4': PosicaoFiscal(qtd: 80, custo: 800.0),
      };
      expect(posicoesEm(m, '2026-03-31').single.custoFiscal, isNull);
    });
  });
}
