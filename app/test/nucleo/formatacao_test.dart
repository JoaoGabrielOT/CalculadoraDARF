import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:calculadoradarf/nucleo/formatacao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

/// Se o Python gravou `{"erro": ...}`, o Dart deve lançar `FormatException`
/// (ValueError) e o caso termina aqui.
void _comErro(Object? saida, Object? Function() f, void Function(Object?) ok) {
  if (saida is Map && saida.containsKey('erro')) {
    expect(f, throwsFormatException);
    return;
  }
  ok(f());
}

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('formatacao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('formatacao')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      switch (caso.funcao) {
        case 'brl':
          conferir(brl((e['v']! as num).toDouble()), caso.saida);
        case 'parse_num':
          _comErro(
            caso.saida,
            () => parseNum(e['s']! as String),
            (r) => conferir(reprPython(r! as double), caso.saida),
          );
        case 'parse_valor':
          _comErro(
            caso.saida,
            () => parseValor(e['s'] as String?),
            (r) => conferir(reprPython(r! as double), caso.saida),
          );
        case 'fmt_num':
          conferir(fmtNum((e['v']! as num).toDouble()), caso.saida);
        case 'parse_qtd':
          _comErro(
            caso.saida,
            () => parseQtd(e['s']! as String),
            (r) => conferir(r, caso.saida),
          );
        case 'preco_texto':
          conferir(precoTexto((e['v']! as num).toDouble()), caso.saida);
        case 'fmt_resultado':
          final res = e['res'] as List<Object?>?;
          conferir(
            fmtResultado(
              res == null
                  ? null
                  : ((res[0]! as num).toDouble(), (res[1]! as num).toDouble()),
            ),
            caso.saida,
          );
        case 'fmt_pct':
          conferir(
            fmtPct((e['v'] as num?)?.toDouble(), sinal: e['sinal']! as bool),
            caso.saida,
          );
        case 'fmt_volume':
          conferir(fmtVolume(e['v'] as num?), caso.saida);
        case 'fmt_dec':
          final v = (e['v']! as num).toDouble();
          final casas = e['casas'] as int?;
          conferir(casas == null ? fmtDec(v) : fmtDec(v, casas), caso.saida);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }
}
