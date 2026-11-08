@Tags(['vivo'])
library;

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Consulta a release publicada de verdade (rede). Roda só no job
/// conferir-atualizador: flutter test --tags vivo --dart-define=VERSAO_ESPERADA=x.y.z
const _versaoEsperada = String.fromEnvironment('VERSAO_ESPERADA');

void main() {
  for (final asset in [nomeAssetWindows, nomeAssetAndroid]) {
    test('$asset: a última release é detectada como atualização', () async {
      expect(_versaoEsperada, isNotEmpty, reason: 'faltou VERSAO_ESPERADA');
      final cliente = http.Client();
      addTearDown(cliente.close);
      final info = await verificarAtualizacao(
        ClienteHttp(cliente),
        nomeAsset: asset,
        versaoAtual: '2.0.0',
      );
      expect(info, isNotNull);
      expect(info!.versao, _versaoEsperada);
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(info.sha256.toLowerCase()),
        isTrue,
      );
      expect(info.tamanho, greaterThan(0));
    });
  }
}
