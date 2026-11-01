import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(r'\b é fronteira de palavra Unicode em qualquer posição', () {
    expect(erPython(r'\bação\b').hasMatch('uma ação boa'), isTrue);
    expect(erPython(r'\bação\b').hasMatch('reação'), isFalse);
    expect(erPython(r'(\bação)').hasMatch('uma ação'), isTrue);
    expect(erPython(r'(?:\bação)').hasMatch('reação'), isFalse);
    expect(erPython(r'\(\bação').hasMatch('(ação'), isTrue);
    expect(erPython(r'\(\bação').hasMatch('(reação'), isFalse);
    expect(erPython(r'^\bação').hasMatch('ação'), isTrue);
    expect(erPython(r'a\b').hasMatch('á'), isFalse);
  });

  test(r'\w \d \s Unicode e . sem \n', () {
    expect(erPython(r'^\w+$').hasMatch('ação'), isTrue);
    expect(erPython(r'^\d$').hasMatch('٣'), isTrue);
    expect(erPython(r'^\s$').hasMatch(' '), isTrue);
    expect(erPython(r'a.b').hasMatch('a\nb'), isFalse);
  });

  test('ignorarCaixa', () {
    expect(erPython('abc', ignorarCaixa: true).hasMatch('ABC'), isTrue);
    expect(erPython('abc').hasMatch('ABC'), isFalse);
  });
}
