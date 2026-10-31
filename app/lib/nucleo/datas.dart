import 'compat/conversao.dart';
import 'compat/numeros.dart';

/// Datas ISO (`AAAA-MM-DD`), meses (`AAAA-MM`), serial do Sheets e instantes
/// com fuso. Toda aritmética usa `DateTime.utc`, nunca `DateTime` local.

/// Fuso de Brasília em segundos (metas.py:22).
const int fusoBrasilia = -10800;

final _epoca = DateTime.utc(1899, 12, 30);
final _dataBr = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
final _dataIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _dataIsoBasica = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final _instante = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[T ](\d{2})(?::(\d{2})(?::(\d{2})(?:\.(\d+))?)?)?'
  r'(Z|[+-]\d{2}(?::\d{2}(?::\d{2})?)?)?)?$',
);

String _pad(int n, int largura) {
  final t = n.abs().toString().padLeft(n < 0 ? largura - 1 : largura, '0');
  return n < 0 ? '-$t' : t;
}

String _formatarData(DateTime d) =>
    '${_pad(d.year, 4)}-${_pad(d.month, 2)}-${_pad(d.day, 2)}';

/// `date(a, m, d)`: nulo se a data não existir (ano 1 a 9999).
DateTime? _dataValida(int a, int m, int d) {
  if (a < 1 || a > 9999) return null;
  final dt = DateTime.utc(a, m, d);
  return dt.year == a && dt.month == m && dt.day == d ? dt : null;
}

DateTime _dataValidaOuErro(int a, int m, int d, String origem) =>
    _dataValida(a, m, d) ?? (throw FormatException('data inválida: "$origem"'));

/// `date.fromisoformat(s)` (`AAAA-MM-DD` ou `AAAAMMDD`).
DateTime _lerIso(String s) {
  final m = _dataIso.firstMatch(s) ?? _dataIsoBasica.firstMatch(s);
  if (m == null) throw FormatException('data ISO inválida: "$s"');
  return _dataValidaOuErro(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    s,
  );
}

DateTime _foraDoIntervalo(DateTime d) => d.year < 1 || d.year > 9999
    ? throw FormatException('data fora do intervalo: $d')
    : d;

/// `iso` mais [dias] dias.
String somarDias(String iso, int dias) =>
    _formatarData(_foraDoIntervalo(_lerIso(iso).add(Duration(days: dias))));

/// `(ate - de).days`.
int diasEntre(String de, String ate) =>
    _lerIso(ate).difference(_lerIso(de)).inDays;

/// `date.weekday()`: 0 = segunda.
int diaDaSemana(String iso) => _lerIso(iso).weekday - 1;

/// Ano, mês e dia de [d], sem conversão de fuso.
String isoDeDateTime(DateTime d) => _formatarData(d);

(int, int) _anoMes(String mes) {
  final partes = mes.split('-');
  if (partes.length != 2) throw FormatException('mês inválido: "$mes"');
  return (intPython(partes[0]), intPython(partes[1]));
}

/// `proximo_mes` (nucleo.py:102-107).
String proximoMes(String mes) {
  var (a, m) = _anoMes(mes);
  m += 1;
  if (m > 12) {
    a += 1;
    m = 1;
  }
  return '${_pad(a, 4)}-${_pad(m, 2)}';
}

/// `limites_mes` (nucleo.py:110-112): primeiro e último dia do mês, em ISO.
(String, String) limitesMes(String mes) {
  final (a, m) = _anoMes(mes);
  if (m < 1 || m > 12) throw FormatException('mês inválido: "$mes"');
  final primeiro = _dataValidaOuErro(a, m, 1, mes);
  final ultimo = DateTime.utc(a, m + 1, 0);
  return (_formatarData(primeiro), _formatarData(ultimo));
}

/// `fmt_data` (nucleo.py:89-90): `AAAA-MM-DD` para `dd/mm/aaaa`.
String fmtData(String iso) {
  final d = _lerIso(iso);
  return '${_pad(d.day, 2)}/${_pad(d.month, 2)}/${_pad(d.year, 4)}';
}

/// `fmt_mes` (nucleo.py:93-95): `AAAA-MM` para `MM/AAAA`.
String fmtMes(String mes) {
  final partes = mes.split('-');
  if (partes.length != 2) throw FormatException('mês inválido: "$mes"');
  return '${partes[1]}/${partes[0]}';
}

/// `parse_data` (nucleo.py:85-86): `dd/mm/aaaa` (dia e mês de 1 ou 2
/// dígitos, como `strptime`) para ISO.
String parseData(String s) {
  final m = _dataBr.firstMatch(s.trim());
  if (m == null) throw FormatException('data inválida: "$s"');
  final d = _dataValidaOuErro(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    s,
  );
  return _formatarData(d);
}

/// `serial` (nucleo.py:748-752): dias desde 30/12/1899.
int serial(String iso) => _lerIso(iso).difference(_epoca).inDays;

/// `de_serial` (nucleo.py:755-762). Número (não bool): dias truncados;
/// texto: `dd/mm/aaaa`, senão ISO.
String deSerial(Object? v) {
  if (v is num) {
    final dias = intPython(v);
    return _formatarData(_foraDoIntervalo(_epoca.add(Duration(days: dias))));
  }
  final s = strPython(v).trim();
  try {
    return parseData(s);
  } on FormatException {
    return _formatarData(_lerIso(s));
  }
}

/// `mes_iso` (nucleo.py:765-767): rótulo `M/AAAA` ou `MM/AAAA` para `AAAA-MM`.
String mesIso(Object? rotulo) {
  final partes = strPython(rotulo).trim().split('/');
  if (partes.length != 2) {
    throw FormatException('rótulo de mês inválido: "$rotulo"');
  }
  final m = intPython(partes[0]);
  final a = intPython(partes[1]);
  return '${_pad(a, 4)}-${_pad(m, 2)}';
}

/// Instante com fuso: `datetime` com `tzinfo` fixo. [desvio] em segundos em
/// relação a UTC; igualdade e ordem pelo instante.
class DataHora implements Comparable<DataHora> {
  DataHora(this.utc, this.desvio)
    : assert(utc.isUtc, 'DataHora exige DateTime em UTC');

  /// `datetime.fromtimestamp(ts, tz)`: microssegundos com meio-para-par.
  factory DataHora.deTimestamp(num ts, int desvio) {
    final t = ts.toDouble();
    if (t.isNaN || t.isInfinite) {
      throw FormatException('timestamp inválido: $t');
    }
    final inteira = t.truncate();
    final micros = arredondar((t - inteira) * 1e6, 0).truncate();
    return DataHora(
      DateTime.fromMicrosecondsSinceEpoch(
        inteira * 1000000 + micros,
        isUtc: true,
      ),
      desvio,
    );
  }

  /// Subconjunto de `datetime.fromisoformat`: `AAAA-MM-DD`, separador `T` ou
  /// espaço, `HH[:MM[:SS[.f]]]`, `Z` ou `±HH[:MM[:SS]]`. Sem fuso vale
  /// Brasília (metas.py:37-39). Frações além de 6 dígitos são truncadas.
  static DataHora parse(String texto) {
    final m = _instante.firstMatch(texto);
    if (m == null) throw FormatException('data/hora inválida: "$texto"');
    final dia = _dataValidaOuErro(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      texto,
    );
    final hora = int.parse(m.group(4) ?? '0');
    final minuto = int.parse(m.group(5) ?? '0');
    final segundo = int.parse(m.group(6) ?? '0');
    if (hora > 23 || minuto > 59 || segundo > 59) {
      throw FormatException('hora inválida: "$texto"');
    }
    final fracao = (m.group(7) ?? '').padRight(6, '0').substring(0, 6);
    final micros = int.parse(fracao);
    final desvio = _lerDesvio(m.group(8), texto);
    final local = DateTime.utc(
      dia.year,
      dia.month,
      dia.day,
      hora,
      minuto,
      segundo,
      micros ~/ 1000,
      micros % 1000,
    );
    return DataHora(local.subtract(Duration(seconds: desvio)), desvio);
  }

  /// [parse], ou nulo se o texto for inválido.
  static DataHora? tentarParse(String texto) {
    try {
      return parse(texto);
    } on FormatException {
      return null;
    }
  }

  static int _lerDesvio(String? z, String texto) {
    if (z == null) return fusoBrasilia;
    if (z == 'Z') return 0;
    final partes = z.substring(1).split(':').map(int.parse).toList();
    if (partes[0] > 23 ||
        (partes.length > 1 && partes[1] > 59) ||
        (partes.length > 2 && partes[2] > 59)) {
      throw FormatException('fuso inválido: "$texto"');
    }
    final seg =
        partes[0] * 3600 +
        (partes.length > 1 ? partes[1] * 60 : 0) +
        (partes.length > 2 ? partes[2] : 0);
    return z.startsWith('-') ? -seg : seg;
  }

  /// O instante, em UTC.
  final DateTime utc;

  /// Desvio do fuso em segundos (Brasília = [fusoBrasilia]).
  final int desvio;

  DateTime get _local => utc.add(Duration(seconds: desvio));

  /// Data (`AAAA-MM-DD`) no fuso do próprio instante.
  String get data => _formatarData(_local);

  /// `HH:MM` no fuso do próprio instante.
  String get horaMinuto => '${_pad(_local.hour, 2)}:${_pad(_local.minute, 2)}';

  /// `isoformat(timespec="seconds")`: trunca frações de segundo.
  String iso() {
    final l = _local;
    final sinal = desvio < 0 ? '-' : '+';
    final a = desvio.abs();
    final seg = a % 60;
    final off =
        '$sinal${_pad(a ~/ 3600, 2)}:${_pad(a % 3600 ~/ 60, 2)}'
        '${seg == 0 ? '' : ':${_pad(seg, 2)}'}';
    return '${_formatarData(l)}T${_pad(l.hour, 2)}:${_pad(l.minute, 2)}:'
        '${_pad(l.second, 2)}$off';
  }

  /// O mesmo instante expresso em outro fuso (`astimezone`).
  DataHora noFuso(int novoDesvio) => DataHora(utc, novoDesvio);

  /// `datetime.timestamp()`: segundos desde a época.
  double get timestamp => utc.microsecondsSinceEpoch / 1e6;

  @override
  int compareTo(DataHora outro) => utc.compareTo(outro.utc);

  bool operator <(DataHora o) => compareTo(o) < 0;
  bool operator <=(DataHora o) => compareTo(o) <= 0;
  bool operator >(DataHora o) => compareTo(o) > 0;
  bool operator >=(DataHora o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) => other is DataHora && utc == other.utc;

  @override
  int get hashCode => utc.hashCode;

  @override
  String toString() => iso();
}
