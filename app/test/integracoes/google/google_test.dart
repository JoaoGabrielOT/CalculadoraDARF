import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

final _cliente = ClienteOAuth.deTexto(
  jsonEncode({
    'installed': {
      'client_id': 'c.apps.googleusercontent.com',
      'client_secret': 'segredo',
      'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
      'token_uri': 'https://oauth2.googleapis.com/token',
    },
  }),
);

Google _google(ClienteOAuth? cliente) {
  final http = ClienteHttp(
    ClienteFalso.fila([]),
    tempoLimite: const Duration(seconds: 30),
  );
  final sessao = SessaoGoogle(
    http: http,
    armazenamento: ArmazenamentoMemoria(),
    executar: executarDireto,
  );
  return Google(
    sessao: sessao,
    planilha: PlanilhaGoogle(sessao),
    httpLogin: http,
    cliente: cliente,
  );
}

void main() {
  test('login sem credencial → SemCredencial', () async {
    final g = _google(null);
    await expectLater(
      g.login((_) async {}),
      throwsA(
        isA<SemCredencial>().having(
          (e) => e.toString(),
          'mensagem',
          'Arquivo credentials.json não encontrado.',
        ),
      ),
    );
  });

  test('temCredencial reflete o cliente', () {
    expect(_google(null).temCredencial, isFalse);
    expect(_google(_cliente).temCredencial, isTrue);
  });

  test('sem token nem e-mail no início', () {
    final g = _google(_cliente);
    expect(g.email, isNull);
    expect(g.temToken(), isFalse);
  });
}
