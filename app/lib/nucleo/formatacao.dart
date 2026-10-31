import 'compat/conversao.dart';
import 'compat/numeros.dart';

/// Formatação de moeda, percentuais e leitura de valores digitados
/// (nucleo.py:45-99, 527-533; mercado.py:551-563; sugestoes.py:44-45).

final _milharBr = RegExp(r'^\d{1,3}(\.\d{3})+$');
final _zerosFinais = RegExp(r'0+$');

/// `1234.5` -> `R$ 1.234,50`; negativos (abaixo de -0,004) levam `-R$ `.
String brl(double v) {
  final s = fixoPython(v.abs(), 2, milhar: true)
      .replaceAll(',', 'X')
      .replaceAll('.', ',')
      .replaceAll('X', '.');
  return (v < -0.004 ? '-R\$ ' : 'R\$ ') + s;
}

/// Número positivo digitado: "1.234,56" ou "12.5". Lança [FormatException]
/// se não for número ou se for menor ou igual a zero.
double parseNum(String s) {
  s = s.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final v = floatPython(s);
  if (v <= 0) throw const FormatException('valor deve ser positivo');
  return v;
}

/// Valor em reais que aceita zero e negativo: "10.000,50", "-250", "R$ 0".
double parseValor(String? s) {
  s = (s ?? '').trim().replaceAll('R\$', '').replaceAll(' ', '');
  final negativo = s.startsWith('-');
  s = s.replaceFirst(RegExp(r'^-+'), '');
  if (s.contains(',') || _milharBr.hasMatch(s)) {
    // "10.000" é dez mil
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final v = floatPython(s);
  return negativo ? -v : v;
}

/// Número para preencher um campo de edição: 32.5 -> "32,50".
String fmtNum(double v) {
  final t = fixoPython(v, 8).replaceFirst(_zerosFinais, '');
  final i = t.indexOf('.');
  if (i < 0) throw FormatException('fmtNum não aceita $t');
  return '${t.substring(0, i)},${t.substring(i + 1).padRight(2, '0')}';
}

/// Quantidade inteira positiva; "1.000" é mil.
int parseQtd(String s) {
  final v = intPython(s.trim().replaceAll('.', ''));
  if (v <= 0) throw const FormatException('quantidade deve ser positiva');
  return v;
}

/// `32.5` -> `32,50`.
String precoTexto(double v) => fixoPython(v, 2).replaceAll('.', ',');

/// Ganho ou perda aberto: `+R$ 10,00 (+2,50%)`; `—` se não houver.
String fmtResultado((double, double)? res) {
  if (res == null) return '—';
  final (valor, pct) = res;
  final sinal = valor > 0.004 ? '+' : '';
  final pctTxt = fixoPython(pct, 2).replaceAll('.', ',');
  return '$sinal${brl(valor)} ($sinal$pctTxt%)';
}

/// Percentual com vírgula; [sinal] força `+` nos positivos.
String fmtPct(double? v, {bool sinal = true}) {
  if (v == null) return '—';
  return '${fixoPython(v, 2, sinal: sinal).replaceAll('.', ',')}%';
}

/// Volume abreviado: 1,5 mi, 2,3 bi.
String fmtVolume(num? v) {
  if (v == null || v == 0) return '—';
  for (final (lim, suf) in [(1e9, ' bi'), (1e6, ' mi'), (1e3, ' mil')]) {
    if (v >= lim) {
      return fixoPython(v / lim, 1).replaceAll('.', ',') + suf;
    }
  }
  return v.truncate().toString();
}

/// Decimal com vírgula e [casas] casas.
String fmtDec(double v, [int casas = 1]) =>
    fixoPython(v, casas).replaceAll('.', ',');
