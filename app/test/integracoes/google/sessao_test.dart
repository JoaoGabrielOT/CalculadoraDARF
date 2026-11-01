import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _agora = 1761000000.0;

TokenGoogle _token({DateTime? expiry, String? refresh = '1//r'}) => TokenGoogle(
  token: 'ya29.a',
  refreshToken: refresh,
  clientId: 'c.apps.googleusercontent.com',
  clientSecret: 's',
  expiry: expiry ?? DateTime.utc(2030),
);

RespostaFalsa _about([String email = 'Ana@Gmail.com']) => RespostaFalsa(
  200,
  json: {
    'user': {'emailAddress': email},
  },
);

RespostaFalsa _renovou([String token = 'ya29.novo']) =>
    RespostaFalsa(200, json: {'access_token': token, 'expires_in': 3599});

(SessaoGoogle, ClienteFalso, ArmazenamentoMemoria) _montar(
  List<RespostaFalsa> respostas,
) {
  final falso = ClienteFalso.fila(respostas);
  final a = ArmazenamentoMemoria();
  final s = SessaoGoogle(
    http: ClienteHttp(falso, tempoLimite: const Duration(seconds: 30)),
    armazenamento: a,
    executar: executarDireto,
  );
  return (s, falso, a);
}

Matcher _erro<T extends ErroGoogle>(String msg, [int? status]) => throwsA(
  isA<T>()
      .having((e) => e.mensagem, 'mensagem', msg)
      .having((e) => e.status, 'status', status ?? 0),
);

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  test(
    'carregarToken sem arquivo → LoginNecessario("Faça login com o Google.")',
    () async {
      final (s, falso, _) = _montar([]);
      expect(s.temToken(), isFalse);
      await expectLater(
        s.carregarToken(),
        _erro<LoginNecessario>('Faça login com o Google.'),
      );
      expect(falso.pedidos, isEmpty);
    },
  );

  test(
    'token válido: só o GET do about; e-mail em minúsculas; Bearer',
    () async {
      final (s, falso, a) = _montar([_about()]);
      gravarToken(a, _token());
      expect(s.temToken(), isTrue);
      expect(await s.carregarToken(), 'ana@gmail.com');
      expect(s.email, 'ana@gmail.com');
      expect(falso.pedidos, hasLength(1));
      final p = falso.pedidos.single;
      expect(p.metodo, 'GET');
      expect(p.url.toString().startsWith('$urlDrive/about?'), isTrue);
      expect(p.url.queryParameters, {'fields': 'user(emailAddress)'});
      expect(p.cabecalhos['authorization'], 'Bearer ya29.a');
    },
  );

  test(
    'token vencido: renova, grava token.json novo e então pede o about',
    () async {
      final (s, falso, a) = _montar([_renovou(), _about()]);
      gravarToken(a, _token(expiry: DateTime.utc(2025, 10, 1)));
      await s.carregarToken();
      expect(falso.pedidos, hasLength(2));
      expect(falso.pedidos[0].url.host, 'oauth2.googleapis.com');
      expect(falso.pedidos[1].cabecalhos['authorization'], 'Bearer ya29.novo');
      expect(lerToken(a)!.token, 'ya29.novo');
    },
  );

  test('sem rede na renovação → Offline e token.json intacto', () async {
    final (s, _, a) = _montar([
      RespostaFalsa(200, erro: const SocketException('sem rede')),
    ]);
    gravarToken(a, _token(expiry: DateTime.utc(2025, 10, 1)));
    final antes = a.ler(arquivoToken);
    await expectLater(s.carregarToken(), throwsA(isA<Offline>()));
    expect(a.ler(arquivoToken), antes);
    expect(s.email, isNull);
  });

  test('token.json inválido → LoginNecessario', () async {
    final (s, _, a) = _montar([]);
    a.gravar(arquivoToken, 'lixo');
    await expectLater(
      s.carregarToken(),
      _erro<LoginNecessario>('Faça login com o Google.'),
    );
  });

  test('req sem token → LoginNecessario("Faça login com o Google.")', () async {
    final (s, falso, _) = _montar([]);
    await expectLater(
      s.req('GET', '$urlSheets/x'),
      _erro<LoginNecessario>('Faça login com o Google.'),
    );
    expect(falso.pedidos, isEmpty);
  });

  test(
    'req: 401 renova e repete uma vez; 401 de novo → LoginNecessario',
    () async {
      final (s, falso, _) = _montar([
        _about(),
        RespostaFalsa(
          401,
          json: {
            'error': {'message': 'x'},
          },
        ),
        _renovou(),
        RespostaFalsa(200, json: {'ok': 1}),
        RespostaFalsa(401, texto: ''),
        _renovou('ya29.outro'),
        RespostaFalsa(401, texto: ''),
      ]);
      await s.iniciar(_token());
      expect(await s.req('GET', '$urlSheets/x'), {'ok': 1});
      expect(falso.pedidos[1].cabecalhos['authorization'], 'Bearer ya29.a');
      expect(falso.pedidos[3].cabecalhos['authorization'], 'Bearer ya29.novo');
      await expectLater(
        s.req('GET', '$urlSheets/x'),
        _erro<LoginNecessario>('Sessão expirada. Faça login novamente.'),
      );
      expect(falso.pedidos, hasLength(7));
    },
  );

  test('req: renovação recusada → LoginNecessario', () async {
    final (s, _, _) = _montar([
      _about(),
      RespostaFalsa(401, texto: ''),
      RespostaFalsa(400, json: {'error': 'invalid_grant'}),
    ]);
    await s.iniciar(_token());
    await expectLater(
      s.req('GET', '$urlSheets/x'),
      _erro<LoginNecessario>('Sessão expirada. Faça login novamente.'),
    );
  });

  test('req renova antes quando o token está vencido', () async {
    final (s, falso, _) = _montar([_renovou(), _about()]);
    await s.iniciar(_token(expiry: DateTime.utc(2025, 10, 1)));
    expect(falso.pedidos[0].url.host, 'oauth2.googleapis.com');
    expect(falso.pedidos[1].cabecalhos['authorization'], 'Bearer ya29.novo');
    expect(s.email, 'ana@gmail.com');
  });

  test(
    'req: 400 com JSON usa error.message; 500 em texto usa 300 caracteres',
    () async {
      final (s, _, _) = _montar([
        _about(),
        RespostaFalsa(
          400,
          json: {
            'error': {'message': 'Pedido ruim'},
          },
        ),
        RespostaFalsa(500, texto: 'ç' * 400),
      ]);
      await s.iniciar(_token());
      await expectLater(
        s.req('GET', '$urlSheets/x'),
        _erro<ErroGoogle>('Pedido ruim', 400),
      );
      await expectLater(
        s.req('GET', '$urlSheets/x'),
        _erro<ErroGoogle>('ç' * 300, 500),
      );
    },
  );

  test('req: SocketException → Offline', () async {
    final (s, _, _) = _montar([
      _about(),
      RespostaFalsa(200, erro: const SocketException('sem rede')),
    ]);
    await s.iniciar(_token());
    await expectLater(s.req('GET', '$urlSheets/x'), throwsA(isA<Offline>()));
  });

  test('req: corpo vazio → {}', () async {
    final (s, _, _) = _montar([_about(), RespostaFalsa(200)]);
    await s.iniciar(_token());
    expect(await s.req('DELETE', '$urlSheets/x'), <String, Object?>{});
  });

  test('json com NaN → ErroGoogle sem nenhum pedido', () async {
    final (s, falso, _) = _montar([_about()]);
    await s.iniciar(_token());
    final antes = falso.pedidos.length;
    await expectLater(
      s.req(
        'PUT',
        '$urlSheets/x',
        json: {
          'values': [
            [1.0, double.nan],
          ],
        },
      ),
      _erro<ErroGoogle>(
        'Há um valor inválido (NaN ou infinito) nos dados; nada foi enviado ao Google.',
      ),
    );
    expect(falso.pedidos.length, antes);
  });

  test(
    'req: params com lista repetem a chave; json com content-type',
    () async {
      final (s, falso, _) = _montar([_about(), RespostaFalsa(200, json: {})]);
      await s.iniciar(_token());
      await s.req(
        'POST',
        '$urlSheets/x',
        params: {
          'ranges': ['a', 'b'],
          'n': 3,
          'valueRenderOption': 'UNFORMATTED_VALUE',
        },
        json: {'a': 1},
      );
      final p = falso.pedidos.last;
      expect(
        p.url.query,
        'ranges=a&ranges=b&n=3&valueRenderOption=UNFORMATTED_VALUE',
      );
      expect(p.cabecalhos['content-type'], contains('application/json'));
      expect(p.json, {'a': 1});
    },
  );

  test('sair apaga token.json e esquece o e-mail', () async {
    final (s, _, a) = _montar([_about()]);
    gravarToken(a, _token());
    await s.carregarToken();
    s.sair();
    expect(a.existe(arquivoToken), isFalse);
    expect(s.email, isNull);
    expect(s.temToken(), isFalse);
    await expectLater(
      s.req('GET', '$urlSheets/x'),
      _erro<LoginNecessario>('Faça login com o Google.'),
    );
  });

  test(
    'sair durante carregarToken não recria token.json nem repõe o e-mail',
    () async {
      final (s, _, a) = _montar([
        RespostaFalsa(
          200,
          json: {'access_token': 'ya29.novo', 'expires_in': 3599},
          atraso: const Duration(milliseconds: 50),
        ),
        _about(),
      ]);
      gravarToken(a, _token(expiry: DateTime.utc(2025, 10, 1)));
      final f = s.carregarToken();
      final esperado = expectLater(f, throwsA(isA<LoginNecessario>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      s.sair();
      await esperado;
      expect(a.existe(arquivoToken), isFalse);
      expect(s.email, isNull);
    },
  );

  test('sair durante o about de iniciar não repõe o e-mail', () async {
    final (s, _, _) = _montar([
      RespostaFalsa(
        200,
        json: {
          'user': {'emailAddress': 'a@b.com'},
        },
        atraso: const Duration(milliseconds: 50),
      ),
    ]);
    final f = s.iniciar(_token());
    final esperado = expectLater(f, throwsA(isA<LoginNecessario>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    s.sair();
    await esperado;
    expect(s.email, isNull);
  });

  test('sair durante a renovação em req não repõe o token', () async {
    final (s, _, _) = _montar([
      _about(),
      RespostaFalsa(401, texto: ''),
      RespostaFalsa(
        200,
        json: {'access_token': 'ya29.novo', 'expires_in': 3599},
        atraso: const Duration(milliseconds: 50),
      ),
    ]);
    await s.iniciar(_token());
    final f = s.req('GET', '$urlSheets/x');
    final esperado = expectLater(f, throwsA(isA<LoginNecessario>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    s.sair();
    await esperado;
    await expectLater(
      s.req('GET', '$urlSheets/x'),
      _erro<LoginNecessario>('Faça login com o Google.'),
    );
  });

  for (final corpo in ['<html>erro</html>', '[1, 2]']) {
    test(
      'req: corpo 200 que não é objeto JSON ($corpo) → ErroGoogle',
      () async {
        final (s, _, _) = _montar([_about(), RespostaFalsa(200, texto: corpo)]);
        await s.iniciar(_token());
        await expectLater(
          s.req('GET', '$urlSheets/x'),
          _erro<ErroGoogle>('Resposta inválida do Google.'),
        );
      },
    );
  }
}
