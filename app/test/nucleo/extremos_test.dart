import 'package:calculadoradarf/nucleo/extremos.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

BarraDiaria _b(String data, double alta, double baixa) =>
    BarraDiaria(data: data, alta: alta, baixa: baixa, fech: (alta + baixa) / 2);

Lote _lote({String data = '2026-10-05'}) => Lote(
  id: 'L1',
  ticker: 'PETR4',
  tipo: 'Ação',
  dataCompra: data,
  qtd: 100,
  preco: 32.5,
);

void main() {
  group('extremosDe', () {
    final barras = [
      _b('2026-09-30', 99, 1),
      _b('2026-10-01', 34, 30),
      _b('2026-10-02', 36, 31),
      _b('2026-10-03', 35, 28),
      _b('2026-11-01', 90, 2),
    ];

    test('máx das altas e mín das baixas só dentro do intervalo', () {
      final e = extremosDe(barras, '2026-10-01', '2026-10-31')!;
      expect(e.maximo.preco, 36);
      expect(e.maximo.data, '2026-10-02');
      expect(e.minimo.preco, 28);
      expect(e.minimo.data, '2026-10-03');
    });

    test('limites do intervalo são inclusivos', () {
      final e = extremosDe(barras, '2026-10-03', '2026-10-03')!;
      expect(e.maximo.preco, 35);
      expect(e.minimo.preco, 28);
    });

    test('lista vazia ou sem barra no intervalo devolve null', () {
      expect(extremosDe([], '2026-10-01', '2026-10-31'), isNull);
      expect(extremosDe(barras, '2026-12-01', '2026-12-31'), isNull);
    });
  });

  group('resultadoHipotetico', () {
    test('igual à fórmula oficial, em lucro e em prejuízo', () {
      final l = _lote();
      for (final p in [40.0, 20.0]) {
        final e = Extremo(preco: p, data: '2026-10-10');
        expect(
          resultadoHipotetico(l, 60, e),
          calcularVendaQtd(l, 60, p, '2026-10-10').liquido,
        );
      }
      expect(
        resultadoHipotetico(l, 60, Extremo(preco: 40, data: '2026-10-10')),
        greaterThan(0),
      );
      expect(
        resultadoHipotetico(l, 60, Extremo(preco: 20, data: '2026-10-10')),
        lessThan(0),
      );
    });

    test('day trade quando a data do extremo é a da compra', () {
      final l = _lote();
      final dt = resultadoHipotetico(
        l,
        100,
        Extremo(preco: 35, data: l.dataCompra),
      );
      final swing = resultadoHipotetico(
        l,
        100,
        Extremo(preco: 35, data: '2026-10-06'),
      );
      expect(dt, calcularVendaQtd(l, 100, 35, l.dataCompra).liquido);
      expect(calcularVendaQtd(l, 100, 35, l.dataCompra).dt, isTrue);
      expect(dt, isNot(swing));
    });
  });
}
