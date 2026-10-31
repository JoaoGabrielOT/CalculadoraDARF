import 'conversao.dart';
import 'numeros.dart';

/// `json.dumps(valor, ensure_ascii=False)`; com [compacto], separadores
/// `","` e `":"`. Mapas mantêm a ordem de inserção.
String jsonPython(Object? valor, {bool compacto = false}) {
  final saida = StringBuffer();
  _escrever(saida, valor, compacto ? ',' : ', ', compacto ? ':' : ': ');
  return saida.toString();
}

void _escrever(StringBuffer s, Object? v, String sepItem, String sepChave) {
  switch (v) {
    case null:
      s.write('null');
    case bool():
      s.write(v ? 'true' : 'false');
    case int():
      s.write(v);
    case double():
      s.write(
        v.isNaN
            ? 'NaN'
            : v.isInfinite
            ? (v < 0 ? '-Infinity' : 'Infinity')
            : reprPython(v),
      );
    case String():
      _texto(s, v);
    case Iterable():
      s.write('[');
      var primeiro = true;
      for (final item in v) {
        if (!primeiro) s.write(sepItem);
        primeiro = false;
        _escrever(s, item, sepItem, sepChave);
      }
      s.write(']');
    case Map():
      s.write('{');
      var primeiro = true;
      for (final e in v.entries) {
        if (!primeiro) s.write(sepItem);
        primeiro = false;
        _texto(s, e.key is String ? e.key as String : strPython(e.key));
        s.write(sepChave);
        _escrever(s, e.value, sepItem, sepChave);
      }
      s.write('}');
    default:
      throw ArgumentError('jsonPython não suporta ${v.runtimeType}');
  }
}

void _texto(StringBuffer s, String texto) {
  s.write('"');
  for (final u in texto.codeUnits) {
    switch (u) {
      case 0x22:
        s.write(r'\"');
      case 0x5c:
        s.write(r'\\');
      case 0x0a:
        s.write(r'\n');
      case 0x0d:
        s.write(r'\r');
      case 0x09:
        s.write(r'\t');
      case 0x08:
        s.write(r'\b');
      case 0x0c:
        s.write(r'\f');
      case < 0x20:
        s.write('\\u00${u.toRadixString(16).padLeft(2, '0')}');
      default:
        s.writeCharCode(u);
    }
  }
  s.write('"');
}
