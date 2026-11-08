import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tetoTick arredonda para cima ao tick', () {
    expect(tetoTick('PETR4', 7.601), 7.61);
    expect(tetoTick('PETR4', 7.60), 7.60); // já no tick não sobe
    expect(tetoTick('AAPL34', 12.0036), 12.01);
  });
  test('pisoTick arredonda para baixo ao tick', () {
    expect(pisoTick('PETR4', 7.609), 7.60);
    expect(pisoTick('PETR4', 10.63333), 10.63);
  });
  test('tickDe da faixa única', () => expect(tickDe('VALE3', 63.2), 0.01));
  test('valores não finitos lançam', () {
    expect(() => tetoTick('PETR4', double.nan), throwsArgumentError);
    expect(() => pisoTick('PETR4', double.infinity), throwsArgumentError);
    expect(() => tickDe('PETR4', double.nan), throwsArgumentError);
  });
  test('faixas cobrem todo preço', () {
    expect(faixasTick.last.ate, double.infinity);
  });
}
