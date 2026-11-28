import 'dart:async';
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

Google _google(
  ClienteOAuth? cliente, {
  Armazenamento? armazenamento,
  FazerLogin? fazerLogin,
  void Function(TokenGoogle? token)? aoSair,
}) {
  final http = ClienteHttp(
    ClienteFalso.fila([]),
    tempoLimite: const Duration(seconds: 30),
  );
  final sessao = SessaoGoogle(
    http: http,
    armazenamento: armazenamento ?? ArmazenamentoMemoria(),
    executar: executarDireto,
  );
  return Google(
    sessao: sessao,
    planilha: PlanilhaGoogle(sessao),
    httpLogin: http,
    cliente: cliente,
    fazerLogin: fazerLogin,
    aoSair: aoSair,
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

  test('fazerLogin sem cliente: temCredencial e login delega', () async {
    Future<void>? recebido;
    String? conta;
    List<String>? extras;
    final cancelar = Completer<void>().future;
    final g = _google(
      null,
      fazerLogin:
          (abrirUrl, {cancelar, mesmaConta, escoposExtras = const []}) async {
            recebido = cancelar;
            conta = mesmaConta;
            extras = escoposExtras;
            return 'ana@gmail.com';
          },
    );
    expect(g.temCredencial, isTrue);
    expect(await g.login((_) async {}, cancelar: cancelar), 'ana@gmail.com');
    expect(recebido, same(cancelar));
    expect(conta, isNull);
    expect(extras, isEmpty);
    await g.login((_) async {}, mesmaConta: 'ana@gmail.com');
    expect(conta, 'ana@gmail.com');
    await g.login(
      (_) async {},
      mesmaConta: 'ana@gmail.com',
      escoposExtras: const [escopoDrive],
    );
    expect(extras, [escopoDrive]);
  });

  test('sair entrega o token do pacote ao aoSair e apaga o token.json', () {
    final a = ArmazenamentoMemoria();
    gravarPacoteWeb(a, 'v1.p');
    TokenGoogle? entregue;
    var chamadas = 0;
    final g = _google(
      null,
      armazenamento: a,
      aoSair: (t) {
        chamadas++;
        entregue = t;
      },
    );
    g.sair();
    expect(chamadas, 1);
    expect(entregue?.refreshToken, 'v1.p');
    expect(a.existe(arquivoToken), isFalse);
  });

  test('sair com token.json ilegível → aoSair(null), sem exceção', () {
    final a = ArmazenamentoMemoria()..gravar(arquivoToken, 'lixo');
    final recebidos = <TokenGoogle?>[];
    final g = _google(null, armazenamento: a, aoSair: recebidos.add);
    g.sair();
    expect(recebidos, [null]);
    expect(a.existe(arquivoToken), isFalse);
  });
}
