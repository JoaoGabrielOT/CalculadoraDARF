import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/referencias.dart';

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('soma_mista'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('soma_mista')) {
    test('sum misto: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      final atual = somaPythonNum((e['valores']! as List<Object?>).cast<num>());
      conferir(atual, caso.saida);
      expect(atual is int, caso.saida is int); // int só quando o Python devolve int
    });
  }
}
