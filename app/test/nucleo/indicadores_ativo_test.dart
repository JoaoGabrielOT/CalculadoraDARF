import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/indicadores_ativo.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/posicoes.dart';
import 'package:flutter_test/flutter_test.dart';

Lote _lote(
  String id,
  String ticker,
  int qtd,
  double preco, {
  String data = '2026-11-03',
  List<Venda>? vendas,
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: preco,
  vendas: vendas,
);

Venda _venda(String id, int qtd, double preco, {String data = '2026-11-10'}) =>
    Venda(id: id, data: data, qtd: qtd, preco: preco);

Map<String, Mes> _aberto(List<Lote> lotes, {String mes = '2026-11'}) => {
  mes: Mes(mes: mes, fechado: false, lotes: lotes),
};

List<IndicadoresAtivo> _calc(
  Map<String, Mes> meses, {
  String mes = '2026-11',
  String corte = '2026-11-28',
  Map<String, double?> cotacoes = const {},
}) => indicadoresPorAtivo(
  meses: meses,
  mes: mes,
  posicao: posicoesEm(meses, corte),
  cotacoes: cotacoes,
);

IndicadoresAtivo _de(List<IndicadoresAtivo> l, String t) =>
    l.firstWhere((i) => i.ticker == t);

void main() {
  setUp(() => corretagemPorOrdem = 0.0);

  test('médias ponderadas com taxas', () {
    final i = _de(
      _calc(
        _aberto([
          _lote('A', 'PETR4', 100, 10.0, vendas: [_venda('V1', 50, 12.0)]),
          _lote('B', 'PETR4', 200, 13.0),
        ]),
      ),
      'PETR4',
    );
    expect(i.qtdAberta, 250);
    expect(i.custoRemanescente, 3100.0);
    expect(i.custoPorCompra, isTrue);
    expect(i.precoMedioCompras, 12.40);
    expect(i.pontoEquilibrio, 12.41);
    expect(i.precoMedioVendasMes, 12.00);
    expect(i.resultadoMes, closeTo(99.67, 1e-9));
    expect(i.ganhoPorUnidade, closeTo(1.9934, 1e-9));
    expect(i.rentabilidadeRealizada, closeTo(0.19934, 1e-9));
    expect(i.taxasMes, closeTo(0.33, 1e-9));
  });

  test('resultado negativo', () {
    final i = _de(
      _calc(
        _aberto([
          _lote('A', 'PETR4', 100, 10.0, vendas: [_venda('V1', 50, 9.0)]),
          _lote('B', 'PETR4', 200, 13.0),
        ]),
      ),
      'PETR4',
    );
    expect(i.resultadoMes, closeTo(-50.285, 1e-9));
    expect(i.rentabilidadeRealizada! < 0, isTrue);
  });

  test('sem vendas no mês dá "—" e não zero', () {
    final i = _de(_calc(_aberto([_lote('A', 'PETR4', 100, 10.0)])), 'PETR4');
    expect(i.precoMedioVendasMes, isNull);
    expect(i.ganhoPorUnidade, isNull);
    expect(i.rentabilidadeRealizada, isNull);
    expect(i.resultadoMes, 0.0);
    expect(i.taxasMes, 0.0);
  });

  test('saldo zerado', () {
    final i = _de(
      _calc(
        _aberto([
          _lote('A', 'PETR4', 100, 10.0, vendas: [_venda('V1', 100, 12.0)]),
        ]),
      ),
      'PETR4',
    );
    expect(i.qtdAberta, 0);
    expect(i.precoMedioCompras, isNull);
    expect(i.pontoEquilibrio, isNull);
    expect(i.precoMedioVendasMes, 12.0);
  });

  test('rentabilidade não é média simples de percentuais', () {
    // +10% sobre 100 e -50% sobre 1000 (sem taxas): (10 - 500) / 1100.
    final meses = _aberto([
      _lote('A', 'PETR4', 10, 10.0, vendas: [_venda('V1', 10, 11.0)]),
      _lote('B', 'PETR4', 100, 10.0, vendas: [_venda('V2', 100, 5.0)]),
    ]);
    final antes = _calc(meses);
    final i = _de(antes, 'PETR4');
    final taxas = i.taxasMes;
    expect(i.rentabilidadeRealizada, closeTo((10 - 500 - taxas) / 1100, 1e-9));
    expect(i.rentabilidadeRealizada, isNot(closeTo((0.1 - 0.5) / 2, 1e-3)));
  });

  test('exposição indisponível com cotação ausente', () {
    final meses = _aberto([
      _lote('A', 'PETR4', 100, 10.0),
      _lote('B', 'VALE3', 50, 60.0),
    ]);
    final l = _calc(meses, cotacoes: {'PETR4': 12.0, 'VALE3': null});
    expect(_de(l, 'PETR4').exposicao, isNull);
    expect(_de(l, 'VALE3').exposicao, isNull);
    expect(_de(l, 'PETR4').valorMercado, 1200.0);
    expect(_de(l, 'PETR4').naoRealizado, 200.0);
    expect(_de(l, 'VALE3').valorMercado, isNull);
    expect(_de(l, 'VALE3').naoRealizado, isNull);
  });

  test('exposição é fração do valor da carteira com todas as cotações', () {
    final meses = _aberto([
      _lote('A', 'PETR4', 100, 10.0),
      _lote('B', 'VALE3', 50, 60.0),
    ]);
    final l = _calc(meses, cotacoes: {'PETR4': 10.0, 'VALE3': 60.0});
    expect(_de(l, 'PETR4').exposicao, closeTo(1000 / 4000, 1e-12));
    expect(_de(l, 'VALE3').exposicao, closeTo(3000 / 4000, 1e-12));
  });

  test('sem cotações nada de mercado', () {
    final i = _de(_calc(_aberto([_lote('A', 'PETR4', 100, 10.0)])), 'PETR4');
    expect(i.valorMercado, isNull);
    expect(i.naoRealizado, isNull);
    expect(i.exposicao, isNull);
  });

  test('acumulado desde o primeiro mês', () {
    final meses = {
      '2026-01': Mes(
        mes: '2026-01',
        fechado: true,
        lotes: [
          _lote(
            'A',
            'PETR4',
            100,
            10.0,
            data: '2026-01-05',
            vendas: [_venda('V1', 100, 11.0, data: '2026-01-20')],
          ),
        ],
      ),
      '2026-02': Mes(
        mes: '2026-02',
        fechado: false,
        lotes: [
          _lote(
            'B',
            'PETR4',
            100,
            10.0,
            data: '2026-02-03',
            vendas: [_venda('V2', 100, 9.7, data: '2026-02-12')],
          ),
        ],
      ),
    };
    final i = _de(
      indicadoresPorAtivo(
        meses: meses,
        mes: '2026-02',
        posicao: posicoesEm(meses, '2026-02-28'),
      ),
      'PETR4',
    );
    final jan = (1100 - 1000) - (1000 + 1100) * taxaB3Swing;
    final fev = (970 - 1000) - (1000 + 970) * taxaB3Swing;
    expect(i.resultadoMes, closeTo(fev, 1e-9));
    expect(i.resultadoAcumulado, closeTo(jan + fev, 1e-9));
    expect(i.desde, '01/2026');
  });

  test('ponto de equilíbrio respeita a corretagem por ordem', () {
    corretagemPorOrdem = 5.0;
    expect(pontoEquilibrio('PETR4', 100, 1000.0), 10.06);
    expect(pontoEquilibrio('PETR4', 0, 0.0), isNull);
  });

  test('ativo vendido por inteiro no mês aparece mesmo sem posição', () {
    final meses = _aberto([
      _lote('A', 'PETR4', 100, 10.0, vendas: [_venda('V1', 100, 12.0)]),
    ]);
    final l = _calc(meses);
    expect(l.map((i) => i.ticker), ['PETR4']);
  });
}
