import 'package:calculadoradarf/nucleo/compat/json_python.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jsonPythonDecode', () {
    test('aceita NaN, Infinity e -Infinity soltos como o json.loads', () {
      final r =
          jsonPythonDecode('{"a": NaN, "b": [Infinity, -Infinity], "c": 1.5}')!
              as Map;
      expect((r['a']! as double).isNaN, isTrue);
      expect(r['b'], [double.infinity, double.negativeInfinity]);
      expect(r['c'], 1.5);
    });

    test('não mexe em texto dentro de strings', () {
      const texto =
          r'{"n": "NaN", "i": "x Infinity y", "e": "\"NaN\"", "k NaN": NaN}';
      final r = jsonPythonDecode(texto)! as Map;
      expect(r['n'], 'NaN');
      expect(r['i'], 'x Infinity y');
      expect(r['e'], '"NaN"');
      expect((r['k NaN']! as double).isNaN, isTrue);
    });

    test('sem os tokens, igual ao jsonDecode', () {
      expect(jsonPythonDecode('{"a": [1, 2.0, "x", null, true]}'), {
        'a': [1, 2.0, 'x', null, true],
      });
    });

    test('JSON inválido continua lançando FormatException', () {
      expect(() => jsonPythonDecode('{quebrado'), throwsFormatException);
      expect(() => jsonPythonDecode('[NaNx]'), throwsFormatException);
    });

    test('ida e volta com jsonPython', () {
      final v = {
        'x': double.nan,
        'y': [double.infinity, double.negativeInfinity],
      };
      final lido = jsonPythonDecode(jsonPython(v))! as Map;
      expect((lido['x']! as double).isNaN, isTrue);
      expect(lido['y'], [double.infinity, double.negativeInfinity]);
    });
  });
}
