import 'dart:isolate';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executarEmIsolate devolve o resultado e propaga a exceção', () async {
    expect(await executarEmIsolate(() => 2 + 3), 5);
    await expectLater(
      executarEmIsolate<int>(() => throw const FormatException('x')),
      throwsFormatException,
    );
  });

  test('executarEmIsolate roda em outro isolate', () async {
    final fora = Isolate.current.controlPort;
    final dentro = await executarEmIsolate(() => Isolate.current.controlPort);
    expect(dentro, isNot(fora));
  });

  test('executarDireto roda na hora, no mesmo isolate', () async {
    expect(await executarDireto(() => 'a'), 'a');
    final fora = Isolate.current.controlPort;
    expect(await executarDireto(() => Isolate.current.controlPort), fora);
  });

  test('executarDireto propaga a exceção', () async {
    await expectLater(
      executarDireto<int>(() => throw const FormatException('x')),
      throwsFormatException,
    );
  });
}
