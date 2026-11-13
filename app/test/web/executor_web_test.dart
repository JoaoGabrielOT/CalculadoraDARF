@TestOn('browser')
library;

import 'package:calculadoradarf/integracoes/executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('executarEmIsolate roda direto na Web', () async {
    expect(await executarEmIsolate(() => 2 + 3), 5);
  });

  test('executarEmIsolate propaga exceções', () {
    expect(
      executarEmIsolate<int>(() => throw const FormatException('x')),
      throwsFormatException,
    );
  });
}
