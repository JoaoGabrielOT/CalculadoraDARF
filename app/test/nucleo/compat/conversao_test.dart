import 'package:calculadoradarf/nucleo/compat/conversao.dart';
import 'package:calculadoradarf/nucleo/compat/json_python.dart';
import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:calculadoradarf/nucleo/compat/ordenacao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/referencias.dart';

/// Executa [f]; se o Python gravou `{"erro": ...}`, o Dart deve lançar
/// `FormatException` (ValueError) e o caso termina aqui.
void _comErro(Object? saida, Object? Function() f, void Function(Object?) ok) {
  if (saida is Map && saida.containsKey('erro')) {
    expect(f, throwsFormatException);
    return;
  }
  ok(f());
}

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('conversao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('conversao')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      switch (caso.funcao) {
        case 'str':
          conferir(strPython(e['v']), caso.saida);
        case 'float':
          _comErro(
            caso.saida,
            () => floatPython(e['v']),
            (r) => conferir(reprPython(r! as double), caso.saida),
          );
        case 'int':
          _comErro(
            caso.saida,
            () => intPython(e['v']),
            (r) => conferir(r, caso.saida),
          );
        case 'bool':
          conferir(verdadeiroPython(e['v']), caso.saida);
        case 'num':
          final padrao = e['padrao'] as double?;
          final r = padrao == null
              ? numOuPadrao(e['v'])
              : numOuPadrao(e['v'], padrao);
          conferir(reprPython(r), caso.saida);
        case 'json':
          conferir(
            jsonPython(e['v'], compacto: e['compacto']! as bool),
            caso.saida,
          );
        case 'sorted':
          final chaves = [
            for (final c in e['chaves']! as List<Object?>)
              (c! as List<Object?>).cast<Object>(),
          ];
          final idx = ordenadoPor<int>(
            List.generate(chaves.length, (i) => i),
            (i) => chaves[i],
            reverso: e['reverso']! as bool,
          );
          conferir(idx, caso.saida);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }

  test('ordenação reversa mantém a ordem original dos empates', () {
    expect(
      ordenadoPor(
        [(1, 'a'), (2, 'b'), (1, 'c')],
        (e) => [e.$1],
        reverso: true,
      ).map((e) => e.$2),
      ['b', 'a', 'c'],
    );
  });

  test('ordenadoCom é estável e não altera a entrada', () {
    final itens = [(2, 'a'), (1, 'b'), (2, 'c'), (1, 'd')];
    final r = ordenadoCom(itens, (a, b) => a.$1.compareTo(b.$1));
    expect(r.map((e) => e.$2), ['b', 'd', 'a', 'c']);
    expect(itens.first.$2, 'a');
  });

  test('compararChaves: prefixo vem antes e bool vale como número', () {
    expect(compararChaves([1], [1, 0]), lessThan(0));
    expect(compararChaves([true], [1]), 0);
    expect(compararChaves(['b'], ['a']), greaterThan(0));
  });

  test('não finitos: float, str e json', () {
    expect(floatPython('inf'), double.infinity);
    expect(floatPython(' -Infinity '), double.negativeInfinity);
    expect(floatPython('NaN').isNaN, isTrue);
    expect(strPython(double.infinity), 'inf');
    expect(strPython(double.nan), 'nan');
    expect(
      jsonPython([double.infinity, double.negativeInfinity, double.nan]),
      '[Infinity, -Infinity, NaN]',
    );
  });

  test('int de float não finito lança FormatException', () {
    expect(() => intPython(double.infinity), throwsFormatException);
    expect(() => intPython(double.nan), throwsFormatException);
  });
}
