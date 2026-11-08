import 'package:calculadoradarf/versao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versaoApp tem formato x.y.z e vale 2.3.1', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versaoApp), isTrue);
    expect(versaoApp, '2.3.1');
  });
}
