import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/referencias.dart';

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('numeros'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('numeros')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      double d(String chave) => (e[chave]! as num).toDouble();
      final atual = switch (caso.funcao) {
        'round' => arredondar(d('x'), e['casas']! as int),
        'format' => fixoPython(
          d('x'),
          e['casas']! as int,
          sinal: e['sinal']! as bool,
          milhar: e['milhar']! as bool,
        ),
        'repr' => reprPython(d('x')),
        'sum' => somaPython(
          (e['valores']! as List<Object?>).map((v) => (v! as num).toDouble()),
        ),
        'max' => maxPython<num>(e['a']! as num, e['b']! as num),
        'min' => minPython<num>(e['a']! as num, e['b']! as num),
        _ => fail('função desconhecida: ${caso.funcao}'),
      };
      conferir(atual, caso.saida);
    });
  }

  test('round do Python é meio-para-par sobre o binário exato', () {
    expect(arredondar(1.125, 2), 1.12);
    expect(arredondar(2.675, 2), 2.67);
    expect(arredondar(0.375, 2), 0.38);
    expect(fixoPython(-0.001, 2), '-0.00');
    expect(fixoPython(1234567.891, 2, milhar: true), '1,234,567.89');
  });

  test('sum do Python 3.12 é compensada', () {
    expect(somaPython(List.filled(10, 0.1)), 1.0);
  });

  test('conferir distingue o sinal do zero e aceita int contra double', () {
    conferir(0, 0.0);
    expect(() => conferir(-0.0, 0.0), throwsA(isA<TestFailure>()));
    expect(() => conferir(1, 2, caminho: r'$.a'), throwsA(isA<TestFailure>()));
    conferir([2, 1], [1, 2], semOrdem: {r'$'});
    expect(() => conferir([2, 1], [1, 2]), throwsA(isA<TestFailure>()));
    expect(() => conferir({'a': 1}, {'b': 1}), throwsA(isA<TestFailure>()));
  });
}
