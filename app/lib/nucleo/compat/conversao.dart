import 'numeros.dart';

/// Conversões com a semântica de `str`, `float`, `int`, `bool` e `_num` do
/// Python. Valores sem equivalente (listas, mapas, nulo onde o Python lança
/// `TypeError`) resultam em `FormatException`.

const _digitos = r'\d+(?:_\d+)*';
final _naoFinito = RegExp(r'^([+-]?)(inf|infinity|nan)$', caseSensitive: false);
final _decimal = RegExp(
  '^([+-]?)(?:($_digitos)(?:\\.($_digitos)?)?|\\.($_digitos))'
  '(?:[eE]([+-]?$_digitos))?\$',
);
final _inteiro = RegExp('^([+-]?)($_digitos)\$');

/// `str(v)`.
String strPython(Object? v) {
  if (v == null) return 'None';
  if (v is bool) return v ? 'True' : 'False';
  if (v is int) return v.toString();
  if (v is double) return reprPython(v);
  if (v is String) return v;
  throw ArgumentError('strPython não suporta ${v.runtimeType}');
}

/// `float(v)`.
double floatPython(Object? v) {
  if (v is bool) return v ? 1.0 : 0.0;
  if (v is num) return v.toDouble();
  if (v is! String) {
    throw FormatException('float() não aceita ${v.runtimeType}');
  }
  final s = v.trim();
  final especial = _naoFinito.firstMatch(s);
  if (especial != null) {
    final negativo = especial.group(1) == '-';
    if (especial.group(2)!.toLowerCase() == 'nan') return double.nan;
    return negativo ? double.negativeInfinity : double.infinity;
  }
  final m = _decimal.firstMatch(s);
  if (m == null) throw FormatException('float inválido: "$v"');
  final inteira = (m.group(2) ?? '').replaceAll('_', '');
  final fracao = (m.group(3) ?? m.group(4) ?? '').replaceAll('_', '');
  final expoente = m.group(5)?.replaceAll('_', '');
  final texto = StringBuffer(m.group(1)!)
    ..write(inteira.isEmpty ? '0' : inteira)
    ..write('.')
    ..write(fracao.isEmpty ? '0' : fracao);
  if (expoente != null) texto.write('e$expoente');
  return double.parse(texto.toString());
}

/// `int(v)`.
int intPython(Object? v) {
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is double) {
    if (v.isNaN || v.isInfinite) {
      throw FormatException('int() não aceita $v');
    }
    return v.truncate();
  }
  if (v is! String) {
    throw FormatException('int() não aceita ${v.runtimeType}');
  }
  final m = _inteiro.firstMatch(v.trim());
  if (m == null) throw FormatException('int inválido: "$v"');
  return int.parse('${m.group(1)}${m.group(2)!.replaceAll('_', '')}');
}

/// `bool(v)`.
bool verdadeiroPython(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is Iterable) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}

/// `_num` de nucleo.py:770-774: `float(v)`, ou [padrao] se `v` for vazio, nulo
/// ou não convertível.
double numOuPadrao(Object? v, [double padrao = 0.0]) {
  if (v == null || v == '') return padrao;
  try {
    return floatPython(v);
  } on FormatException {
    return padrao;
  }
}
