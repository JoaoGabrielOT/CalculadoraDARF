import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/metas/preco_alvo.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

double _num(Object? v) {
  if (v is String) {
    return switch (v) {
      'inf' => double.infinity,
      '-inf' => double.negativeInfinity,
      'nan' => double.nan,
      _ => throw ArgumentError(v),
    };
  }
  return (v! as num).toDouble();
}

/// qtd pode ser inteira (grade) ou fracionária; o texto vira não finito.
num _qtd(Object? v) => v is String ? _num(v) : v! as num;

void main() {
  tearDown(() => corretagemPorOrdem = 0.0);

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('metas_preco'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('metas_preco')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = _mapa(caso.entrada);
      switch (caso.funcao) {
        case 'preco_alvo':
          corretagemPorOrdem = _num(e['corretagem']);
          final lote = Lote.fromJson(_mapa(e['lote']));
          final esperado = _mapa(caso.saida);
          Object? obtido;
          try {
            obtido = calcularPrecoAlvo(
              lote,
              _qtd(e['qtd']),
              _num(e['lucro']),
              dayTrade: e['day_trade']! as bool,
            ).toJson();
          } on ErroValidacao catch (erro) {
            obtido = {'erro': erro.mensagem};
          }
          conferir(obtido, esperado);
        case 'centavo':
          final valores = [
            for (final v in e['valores']! as List<Object?>) _num(v),
          ];
          final s = _mapa(caso.saida);
          conferir([for (final v in valores) tetoCentavo(v)], s['teto']);
          conferir([for (final v in valores) pisoCentavo(v)], s['piso']);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }
}
