// Porte de TestIndicadores (tests/test_sugestoes.py:27-42).

import 'package:calculadoradarf/nucleo/mercado/indicadores.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/barras.dart';

/// `assertAlmostEqual` do unittest (7 casas).
Matcher _quase(double esperado) => closeTo(esperado, 5e-8);

void main() {
  test('TestIndicadores.test_atr_de_barras_planas', () {
    final b = barrasPlanas();
    final h = [for (final x in b) x.alta];
    final l = [for (final x in b) x.baixa];
    final c = [for (final x in b) x.fech];
    expect(calcularAtr(h, l, c, 14), _quase(2.0));
    expect(calcularAtr(h, l, c, 22), _quase(2.0));
  });

  test('TestIndicadores.test_pivos', () {
    final p = calcularPivos(12, 9, 10.5);
    expect(p.pp, _quase(10.5));
    expect(p.r1, _quase(12.0));
    expect(p.s1, _quase(9.0));
  });

  test('TestIndicadores.test_chandelier', () {
    expect(calcularChandelier(barrasPlanas()), _quase(5.0)); // 11 - 3*2
    expect(calcularChandelier(barrasPlanas(n: 22)), isNull); // precisa de 23
    expect(calcularChandelier(barrasPlanas(n: 23)), isNotNull);
  });
}
