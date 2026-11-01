import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _agora = 1761000000.0;

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

RespostaFalsa _tokenOk() => RespostaFalsa(
  200,
  json: {'access_token': 'ya29.a', 'refresh_token': '1//r', 'expires_in': 3599},
);

RespostaFalsa _about() => RespostaFalsa(
  200,
  json: {
    'user': {'emailAddress': 'Ana@Gmail.com'},
  },
);

RespostaFalsa _semRede() =>
    RespostaFalsa(0, erro: const SocketException('sem rede'));

class _Montagem {
  _Montagem(List<RespostaFalsa> respostas)
    : falso = ClienteFalso.fila(respostas),
      armazenamento = ArmazenamentoMemoria() {
    http = ClienteHttp(falso, tempoLimite: const Duration(seconds: 30));
    sessao = SessaoGoogle(
      http: http,
      armazenamento: armazenamento,
      executar: executarDireto,
    );
  }

  final ClienteFalso falso;
  final ArmazenamentoMemoria armazenamento;
  late final ClienteHttp http;
  late final SessaoGoogle sessao;
  final esperas = <Duration>[];
  Uri? urlAberta;

  Future<String> login(
    Future<void> Function(Uri) abrir, {
    Duration tempoLimite = const Duration(seconds: 600),
    Esperar? esperar,
  }) => loginNavegador(
    sessao,
    _cliente,
    http,
    (url) {
      urlAberta = url;
      return abrir(url);
    },
    tempoLimite: tempoLimite,
    esperar:
        esperar ??
        (d) async {
          esperas.add(d);
        },
  );
}

Uri _redirect(Uri auth) => Uri.parse(auth.queryParameters['redirect_uri']!);

/// GET no servidor loopback; devolve (status, corpo).
Future<(int, String)> _get(Uri url) async {
  final c = HttpClient();
  try {
    final r = await (await c.getUrl(url)).close();
    return (r.statusCode, await utf8.decodeStream(r));
  } finally {
    c.close(force: true);
  }
}

/// O "navegador" devolve o usuário ao redirect com [q].
Future<void> _retornarComo(Uri url, Map<String, String> q) async {
  unawaited(_get(_redirect(url).replace(queryParameters: q)));
}

Future<void> _retornarComCodigo(Uri url) =>
    _retornarComo(url, {'code': 'abc', 'state': url.queryParameters['state']!});

Matcher _erro<T extends ErroGoogle>(String msg) =>
    throwsA(isA<T>().having((e) => e.mensagem, 'mensagem', msg));

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  test(
    'desafio PKCE do RFC 7636',
    () => expect(
      desafioPkce('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    ),
  );

  test('gerarPkce: verificador de 86 caracteres base64url sem "="', () {
    final p = gerarPkce();
    expect(p.verificador, matches(RegExp(r'^[A-Za-z0-9_-]{86}$')));
    expect(p.desafio, desafioPkce(p.verificador));
    expect(p.desafio, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(gerarPkce().verificador, isNot(p.verificador));
  });

  test('URL de autorização com os parâmetros do Python', () {
    final url = urlAutorizacao(
      _cliente,
      redirect: 'http://127.0.0.1:5000/',
      desafio: 'DES',
      estado: 'EST',
    );
    expect(url.scheme, 'https');
    expect(url.host, 'accounts.google.com');
    expect(url.path, '/o/oauth2/auth');
    expect(url.queryParameters, {
      'client_id': 'c.apps.googleusercontent.com',
      'redirect_uri': 'http://127.0.0.1:5000/',
      'response_type': 'code',
      'scope': escoposGoogle.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': 'DES',
      'code_challenge_method': 'S256',
      'state': 'EST',
    });
    expect(url.queryParameters.keys.toList(), [
      'client_id',
      'redirect_uri',
      'response_type',
      'scope',
      'access_type',
      'prompt',
      'code_challenge',
      'code_challenge_method',
      'state',
    ]);
  });

  test(
    'fluxo completo: recebe o código em 127.0.0.1, troca e devolve o e-mail',
    () async {
      final m = _Montagem([_tokenOk(), _about()]);
      final resposta = Completer<(int, String)>();
      final email = await m.login((url) async {
        final r = _redirect(url);
        expect(r.host, '127.0.0.1');
        expect(r.path, '/');
        final estado = url.queryParameters['state']!;
        resposta.complete(
          _get(r.replace(queryParameters: {'code': 'abc', 'state': estado})),
        );
      });
      expect(email, 'ana@gmail.com');
      final (status, corpo) = await resposta.future;
      expect(status, 200);
      expect(corpo, contains('Login concluído'));

      final troca = m.falso.pedidos[0];
      expect(troca.metodo, 'POST');
      expect(troca.url.toString(), 'https://oauth2.googleapis.com/token');
      final f = troca.formulario;
      expect(
        desafioPkce(f['code_verifier']!),
        m.urlAberta!.queryParameters['code_challenge'],
      );
      expect(f, {
        'code': 'abc',
        'client_id': 'c.apps.googleusercontent.com',
        'client_secret': 'segredo',
        'redirect_uri': _redirect(m.urlAberta!).toString(),
        'grant_type': 'authorization_code',
        'code_verifier': f['code_verifier'],
      });
      expect(m.falso.pedidos[1].url.path, '/drive/v3/about');

      final salvo = jsonDecode(m.armazenamento.ler('token.json')!) as Map;
      expect(salvo['token'], 'ya29.a');
      expect(salvo['refresh_token'], '1//r');
      expect(salvo['scopes'], escoposGoogle);
      expect(salvo['client_id'], 'c.apps.googleusercontent.com');
      expect(salvo['token_uri'], 'https://oauth2.googleapis.com/token');
      // agora + 3599 - 60 = 1761003539
      expect(
        salvo['expiry'],
        DateTime.fromMillisecondsSinceEpoch(
          1761003539000,
          isUtc: true,
        ).toIso8601String().replaceFirst('.000Z', 'Z'),
      );
    },
  );

  test('favicon.ico recebe 404 e o login continua esperando', () async {
    final m = _Montagem([_tokenOk(), _about()]);
    final statusFavicon = Completer<int>();
    final email = await m.login((url) async {
      final r = _redirect(url);
      final estado = url.queryParameters['state']!;
      unawaited(() async {
        statusFavicon.complete(
          (await _get(r.replace(path: '/favicon.ico'))).$1,
        );
        await _get(
          r.replace(queryParameters: {'code': 'abc', 'state': estado}),
        );
      }());
    });
    expect(await statusFavicon.future, 404);
    expect(email, 'ana@gmail.com');
    expect(m.falso.pedidos, hasLength(2));
  });

  test('error=access_denied → "O login foi cancelado."', () async {
    final m = _Montagem([]);
    await expectLater(
      m.login((u) => _retornarComo(u, {'error': 'access_denied'})),
      _erro<ErroGoogle>('O login foi cancelado.'),
    );
    expect(m.falso.pedidos, isEmpty);
  });

  test(
    'error=invalid_scope → "O login não foi concluído: invalid_scope"',
    () async {
      final m = _Montagem([]);
      await expectLater(
        m.login((u) => _retornarComo(u, {'error': 'invalid_scope'})),
        _erro<ErroGoogle>('O login não foi concluído: invalid_scope'),
      );
    },
  );

  test('state errado → "O login não foi concluído."', () async {
    final m = _Montagem([]);
    await expectLater(
      m.login((u) => _retornarComo(u, {'code': 'abc', 'state': 'outro'})),
      _erro<ErroGoogle>('O login não foi concluído.'),
    );
    expect(m.falso.pedidos, isEmpty);
  });

  test('sem retorno no tempo limite → "O login não foi concluído." e porta liberada', () async {
    final m = _Montagem([]);
    late Uri redirect;
    await expectLater(
      m.login(
        (u) async => redirect = _redirect(u),
        tempoLimite: const Duration(milliseconds: 200),
      ),
      _erro<ErroGoogle>('O login não foi concluído.'),
    );
    await expectLater(_get(redirect), throwsA(isA<SocketException>()));
  });

  test('troca do código sem rede repete a cada 2 s', () async {
    final m = _Montagem([_semRede(), _semRede(), _tokenOk(), _about()]);
    final email = await m.login(_retornarComCodigo);
    expect(email, 'ana@gmail.com');
    expect(m.esperas, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    expect(m.falso.pedidos, hasLength(4));
  });

  test('troca sem rede até o prazo → Offline', () async {
    var agora = _agora;
    final m = _Montagem([for (var i = 0; i < 20; i++) _semRede()]);
    await expectLater(
      m.login(
        _retornarComCodigo,
        tempoLimite: const Duration(seconds: 10),
        esperar: (d) async {
          m.esperas.add(d);
          agora += 4;
          ambiente = Ambiente.fixo(agora: agora);
        },
      ),
      throwsA(
        isA<Offline>().having(
          (e) => e.mensagem,
          'mensagem',
          contains('sem rede'),
        ),
      ),
    );
    // prazo = agora + 10: esperas em +0, +4 e +8; em +12 passou do prazo
    expect(m.esperas, hasLength(3));
    expect(m.armazenamento.existe('token.json'), isFalse);
  });

  test(
    'token endpoint 400 → "O login não foi concluído: Bad Request"',
    () async {
      final m = _Montagem([
        RespostaFalsa(
          400,
          json: {'error': 'invalid_grant', 'error_description': 'Bad Request'},
        ),
      ]);
      await expectLater(
        m.login(_retornarComCodigo),
        _erro<ErroGoogle>('O login não foi concluído: Bad Request'),
      );
      expect(m.armazenamento.existe('token.json'), isFalse);
    },
  );
}
