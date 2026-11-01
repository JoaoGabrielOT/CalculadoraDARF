import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executarEmIsolate devolve o resultado e propaga a exceção', () async {
    expect(await executarEmIsolate(() => 2 + 3), 5);
    expect(
      () => executarEmIsolate<int>(() => throw const FormatException('x')),
      throwsFormatException,
    );
  });

  test('executarDireto roda na hora', () async {
    expect(await executarDireto(() => 'a'), 'a');
  });
}
