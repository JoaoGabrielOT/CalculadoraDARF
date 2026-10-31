// Porte de TestPrecoAlvo (tests/test_metas.py:59-125) e de
// TestIndicadores.test_piso_e_teto_de_centavo (tests/test_sugestoes.py:44-47).

import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/metas/preco_alvo.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';

/// `assertAlmostEqual(a, b, places=n)`: `round(a - b, n) == 0`.
void quaseIgual(double a, double b, {int casas = 7}) {
  final limite = 0.5 / _pot10(casas);
  expect((a - b).abs() <= limite, isTrue, reason: 'obtido $a, esperado $b');
}

double _pot10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  // TestPrecoAlvo.conferir
  PrecoAlvo conferir(
    num qtd,
    double lucro,
    bool dayTrade, {
    double corretagem = 0.0,
  }) {
    corretagemPorOrdem = corretagem;
    final lote = base.lote();
    final r = calcularPrecoAlvo(lote, qtd, lucro, dayTrade: dayTrade);
    // com o preço exato, o lucro após imposto é exatamente o desejado
    final p = projetar(lote, qtd, r.precoExato, dayTrade: dayTrade);
    expect((p.lucroAposImposto - lucro).abs() <= 0.01, isTrue);
    // com o preço arredondado para cima nunca fica abaixo do desejado
    expect(r.lucroAposImposto >= lucro - 1e-9, isTrue);
    expect(r.lucroAposImposto - lucro < qtd * 0.01 + 0.01, isTrue);
    // coerente com o cálculo do app
    final dia = dayTrade ? lote.dataCompra : '';
    final c = calcularVendaQtd(lote, qtd, r.preco, dia);
    quaseIgual(c.liquido, r.liquido, casas: 9);
    return r;
  }

  test('TestPrecoAlvo.test_exemplo_de_referencia', () {
    final r = calcularPrecoAlvo(base.lote(), 100, 1000);
    quaseIgual(r.precoExato, 21.7743, casas: 3);
    expect(r.preco, 21.78);
  });

  test('TestPrecoAlvo.test_swing', () {
    final r = conferir(100, 1000, false);
    expect(r.dt, isFalse);
    quaseIgual(r.imposto, r.liquido * 0.15, casas: 9);
  });

  test('TestPrecoAlvo.test_day_trade', () {
    final r = conferir(100, 1000, true);
    expect(r.dt, isTrue);
    quaseIgual(r.imposto, r.liquido * 0.20, casas: 9);
    final swing = calcularPrecoAlvo(base.lote(), 100, 1000);
    // 20% de imposto exige lucro bruto maior
    expect(r.precoExato > swing.precoExato, isTrue);
  });

  test('TestPrecoAlvo.test_com_corretagem', () {
    final sem = calcularPrecoAlvo(base.lote(), 50, 500);
    final r = conferir(50, 500, false, corretagem: 2.5);
    expect(r.precoExato > sem.precoExato, isTrue);
    quaseIgual(r.corretagem, 2.5 * (1 + 50 / 100));
  });

  test('TestPrecoAlvo.test_lucro_zero_e_negativo', () {
    final r0 = conferir(100, 0, false);
    // só o arredondamento para cima do centavo
    expect(r0.imposto < 0.15 * (100 * 0.01 + 0.01), isTrue);
    expect(r0.preco > 10.0, isTrue); // cobre as taxas
    final rn = conferir(100, -200, false);
    expect(rn.imposto < 0.15 * (100 * 0.01 + 0.01), isTrue);
    expect(rn.preco < 10.0, isTrue);
    expect(
      () => calcularPrecoAlvo(base.lote(), 100, -5000),
      throwsA(isA<ErroValidacao>()),
    );
  });

  test('TestPrecoAlvo.test_irrf_nao_altera_preco_nem_imposto', () {
    final lote = base.lote();
    final r = calcularPrecoAlvo(lote, 100, 1000);
    // 0,005% de R$ 2.178 = R$ 0,11: abaixo de R$ 1 não há retenção
    expect(r.irrf, 0);
    final grande = Lote(
      id: lote.id,
      ticker: lote.ticker,
      tipo: lote.tipo,
      dataCompra: lote.dataCompra,
      qtd: 100000,
      preco: 10.0,
    );
    final rg = calcularPrecoAlvo(grande, 100000, 1000000);
    expect(rg.irrf > 1, isTrue);
    // com IRRF o imposto total é o mesmo da fórmula; o IRRF só abate o que
    // sobra para a DARF
    quaseIgual(rg.imposto, rg.liquido * 0.15, casas: 6);
    quaseIgual(rg.darfEstimado, rg.imposto - rg.irrf, casas: 6);
    final pg = projetar(grande, 100000, rg.precoExato);
    expect((pg.lucroAposImposto - 1000000).abs() <= 0.01, isTrue);
  });

  test('TestPrecoAlvo.test_teto_centavo', () {
    expect(tetoCentavo(21.7743), 21.78);
    expect(tetoCentavo(21.77), 21.77);
    expect(tetoCentavo(21.770000000001), 21.77);
  });

  test('TestIndicadores.test_piso_e_teto_de_centavo', () {
    expect(pisoCentavo(5.999999999), 6.0);
    expect(pisoCentavo(5.989), 5.98);
    expect(tetoCentavo(5.981), 5.99);
  });
}
