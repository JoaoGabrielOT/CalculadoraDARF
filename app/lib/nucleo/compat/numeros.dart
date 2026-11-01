import 'dart:typed_data';

/// Aritmética e formatação idênticas às do Python 3.12 (`round`, `format`,
/// `repr`, `sum`, `max`, `min`). Único lugar do núcleo onde `toStringAsFixed`,
/// `.round()` e afins são permitidos.

/// Valor absoluto de [x] como `mantissa * 2^expoente` exato (x finito).
(BigInt, int) _decompor(double x) {
  final dados = ByteData(8)..setFloat64(0, x);
  final alto = dados.getUint32(0);
  final baixo = dados.getUint32(4);
  final expBits = (alto >> 20) & 0x7ff;
  final fracao = (BigInt.from(alto & 0xfffff) << 32) | BigInt.from(baixo);
  if (expBits == 0) return (fracao, -1074);
  return (fracao | (BigInt.one << 52), expBits - 1075);
}

/// `|x| * 10^casas` arredondado para inteiro, meio-para-par, sobre o valor
/// binário exato de `x`.
BigInt _escalado(double x, int casas) {
  final (mantissa, expoente) = _decompor(x);
  final numerador =mantissa * BigInt.from(10).pow(casas);
  if (expoente >= 0) return numerador << expoente;
  final denominador = BigInt.one << -expoente;
  final q = numerador ~/ denominador;
  final dobroResto = (numerador - q * denominador) << 1;
  final c = dobroResto.compareTo(denominador);
  if (c > 0 || (c == 0 && q.isOdd)) return q + BigInt.one;
  return q;
}

/// Dígitos de `|x|` com [casas] decimais: parte inteira e parte fracionária.
(String, String) _digitos(double x, int casas) {
  final texto = _escalado(x, casas).toString().padLeft(casas + 1, '0');
  final corte = texto.length - casas;
  return (texto.substring(0, corte), texto.substring(corte));
}

/// `round(x, casas)` do Python para float.
double arredondar(double x, int casas) {
  if (!x.isFinite) return x;
  final (inteira, fracao) = _digitos(x, casas);
  final sinal = x.isNegative ? '-' : '';
  return double.parse(
    fracao.isEmpty ? '$sinal$inteira' : '$sinal$inteira.$fracao',
  );
}

/// `format(x, '.{casas}f')` do Python; [sinal] equivale a `'+.nf'` e [milhar]
/// a `',.nf'`.
String fixoPython(
  double x,
  int casas, {
  bool sinal = false,
  bool milhar = false,
}) {
  final prefixo = x.isNegative ? '-' : (sinal ? '+' : '');
  if (x.isNaN) return '${sinal ? '+' : ''}nan';
  if (x.isInfinite) return '${prefixo}inf';
  var (inteira, fracao) = _digitos(x, casas);
  if (milhar) {
    final b = StringBuffer();
    for (var i = 0; i < inteira.length; i++) {
      if (i > 0 && (inteira.length - i) % 3 == 0) b.write(',');
      b.write(inteira[i]);
    }
    inteira = b.toString();
  }
  return fracao.isEmpty ? '$prefixo$inteira' : '$prefixo$inteira.$fracao';
}

/// `repr(x)` do Python para float.
String reprPython(double x) {
  if (x.isNaN) return 'nan';
  if (x.isInfinite) return x.isNegative ? '-inf' : 'inf';
  if (x == 0) return x.isNegative ? '-0.0' : '0.0';
  final sinal = x.isNegative ? '-' : '';
  final partes = x.abs().toStringAsExponential().split('e');
  final digitos = partes[0].replaceAll('.', '');
  final e = int.parse(partes[1]);
  if (e < -4 || e >= 16) {
    final mantissa = digitos.length == 1
        ? digitos
        : '${digitos[0]}.${digitos.substring(1)}';
    final absE = e.abs().toString().padLeft(2, '0');
    return '$sinal${mantissa}e${e < 0 ? '-' : '+'}$absE';
  }
  if (e >= 0) {
    final inteira = digitos.length > e + 1
        ? digitos.substring(0, e + 1)
        : digitos.padRight(e + 1, '0');
    final fracao = digitos.length > e + 1 ? digitos.substring(e + 1) : '0';
    return '$sinal$inteira.$fracao';
  }
  return '${sinal}0.${'0' * (-e - 1)}$digitos';
}

/// `sum()` do Python 3.12 sobre floats (soma compensada de Neumaier, como em
/// `builtin_sum_impl`).
double somaPython(Iterable<double> valores) {
  var f = 0.0;
  var c = 0.0;
  for (final x in valores) {
    final t = f + x;
    c += f.abs() >= x.abs() ? (f - t) + x : (x - t) + f;
    f = t;
  }
  return (c != 0.0 && c.isFinite) ? f + c : f;
}

/// `sum()` do Python 3.12 sobre `int` e `float` misturados (`builtin_sum_impl`):
/// fase inteira exata; a primeira parcela `float` entra por soma simples; depois
/// os `float` somam com Neumaier e os `int` entram sem compensação. Devolve
/// `int` quando todos os valores são `int`.
num somaPythonNum(Iterable<num> valores) {
  var i = 0;
  var f = 0.0;
  var c = 0.0;
  var real = false;
  for (final x in valores) {
    if (!real) {
      if (x is int) {
        i += x;
        continue;
      }
      real = true;
      f = i.toDouble() + x;
      continue;
    }
    if (x is double) {
      final t = f + x;
      c += f.abs() >= x.abs() ? (f - t) + x : (x - t) + f;
      f = t;
    } else {
      f += x.toDouble();
    }
  }
  if (!real) return i;
  return (c != 0.0 && c.isFinite) ? f + c : f;
}

/// `max(a, b)` do Python: devolve [a] nos empates (max(-0.0, 0) = -0.0).
T maxPython<T extends num>(T a, T b) => b > a ? b : a;

/// `min(a, b)` do Python: devolve [a] nos empates.
T minPython<T extends num>(T a, T b) => b < a ? b : a;

/// `max(iterável)` do Python: o primeiro máximo.
double maxDe(Iterable<double> v) => v.reduce(maxPython);

/// `min(iterável)` do Python: o primeiro mínimo.
double minDe(Iterable<double> v) => v.reduce(minPython);
