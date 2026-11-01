import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/mercado/chart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('yahoo_inteiros'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('yahoo_inteiros')) {
    test('dados_api com inteiros: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      Object? atual;
      try {
        atual = dadosAtivoDeChart(
          e['ticker']! as String,
          e['resposta']! as Map<String, Object?>,
          nomeConhecido: e['nome_conhecido']! as String,
          hora: 1761000000.123,
        ).toJson();
      } on ErroNucleo catch (erro) {
        atual = {
          'erro': erro.runtimeType.toString(),
          'mensagem': erro.toString(),
        };
      }
      conferir(atual, caso.saida);
    });
  }
}
