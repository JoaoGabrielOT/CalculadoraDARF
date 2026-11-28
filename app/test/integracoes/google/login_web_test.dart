import 'dart:async';
import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _agora = 1761000000.0;
final api = Uri.parse('https://calculadora-darf-web.vercel.app/api');
final _pacote = 'v1.${'aB3_-' * 8}';
const _nonce = 'nonce-do-cliente-0123456789';

TokenGoogle _tokenPacote([String pacote = 'v1.p']) => TokenGoogle(
  refreshToken: pacote,
  clientId: marcadorServidor,
  clientSecret: marcadorServidor,
);

Matcher _erro<T extends ErroGoogle>(String msg) =>
    throwsA(isA<T>().having((e) => e.mensagem, 'mensagem', msg));

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  test('pacote gravado vira token vencido para renovar', () {
    final a = ArmazenamentoMemoria();
    gravarPacoteWeb(a, 'v1.p');
    final t = lerToken(a)!;
    expect(
      (t.refreshToken, t.clientId, t.clientSecret),
      ('v1.p', marcadorServidor, marcadorServidor),
    );
    expect(t.valido(ambiente.agora()), isFalse);
  });

  test('URL de início leva a origem de volta e o nonce', () {
    expect(
      urlInicioLogin(
        api,
        Uri.parse('https://calculadora-darf.onrender.com/#/'),
        _nonce,
      ).toString(),
      'https://calculadora-darf-web.vercel.app/api/auth/inicio'
      '?volta=https%3A%2F%2Fcalculadora-darf.onrender.com&n=$_nonce',
    );
  });

  test('URL de início com a conta atual leva o hint', () {
    final url = urlInicioLogin(
      api,
      Uri.parse('https://calculadora-darf.onrender.com/#/'),
      _nonce,
      dica: 'ana@gmail.com',
    );
    expect(url.queryParameters, {
      'volta': 'https://calculadora-darf.onrender.com',
      'n': _nonce,
      'hint': 'ana@gmail.com',
    });
  });

  test('URL de início com o extra drive ("Permitir")', () {
    final url = urlInicioLogin(
      api,
      Uri.parse('https://calculadora-darf.onrender.com/#/'),
      _nonce,
      dica: 'ana@gmail.com',
      extra: 'drive',
    );
    expect(url.queryParameters, {
      'volta': 'https://calculadora-darf.onrender.com',
      'n': _nonce,
      'hint': 'ana@gmail.com',
      'extra': 'drive',
    });
  });

  group('criarLoginWeb', () {
    final origem = Uri.parse('https://calculadora-darf.onrender.com/#/');

    test(
      'escopo drive extra vai como extra=drive, com a mesma conta',
      () async {
        final a = ArmazenamentoMemoria();
        final idas = <Uri>[];
        final login = criarLoginWeb(
          api: api,
          origem: origem,
          nonces: GuardaNonceMemoria(),
          armazenamento: a,
          irPara: (url) async => idas.add(url),
        );
        unawaited(
          login(
            (_) async {},
            mesmaConta: 'ana@gmail.com',
            escoposExtras: const [escopoDrive],
          ),
        );
        await pumpEventQueue();
        expect(idas.single.queryParameters['extra'], 'drive');
        expect(idas.single.queryParameters['hint'], 'ana@gmail.com');
        expect(consumirMesmaContaWeb(a), 'ana@gmail.com');

        // sem extras (ou com outro escopo) não vai extra
        unawaited(login((_) async {}));
        unawaited(
          login((_) async {}, escoposExtras: const ['https://exemplo/outro']),
        );
        await pumpEventQueue();
        expect(idas[1].queryParameters.containsKey('extra'), isFalse);
        expect(idas[2].queryParameters.containsKey('extra'), isFalse);
      },
    );

    test('mesmaConta: hint na ida e a conta guardada para a volta', () async {
      final a = ArmazenamentoMemoria();
      final idas = <Uri>[];
      final login = criarLoginWeb(
        api: api,
        origem: origem,
        nonces: GuardaNonceMemoria(),
        armazenamento: a,
        irPara: (url) async => idas.add(url),
      );
      unawaited(login((_) async {}, mesmaConta: 'ana@gmail.com'));
      await pumpEventQueue();
      expect(idas.single.queryParameters['hint'], 'ana@gmail.com');
      expect(a.existe(arquivoMesmaConta), isTrue);

      // login sem a conta atual apaga a marca
      unawaited(login((_) async {}));
      await pumpEventQueue();
      expect(idas.last.queryParameters.containsKey('hint'), isFalse);
      expect(consumirMesmaContaWeb(a), isNull);
    });

    test('consumirMesmaContaWeb devolve a conta e apaga', () {
      final a = ArmazenamentoMemoria();
      guardarMesmaContaWeb(a, 'ana@gmail.com');
      expect(consumirMesmaContaWeb(a), 'ana@gmail.com');
      expect(consumirMesmaContaWeb(a), isNull);
      a.gravar(arquivoMesmaConta, '{quebrado');
      expect(consumirMesmaContaWeb(a), isNull);
      expect(a.existe(arquivoMesmaConta), isFalse);
    });

    test('guarda o nonce, vai à URL uma vez e não termina', () async {
      final nonces = GuardaNonceMemoria();
      final idas = <Uri>[];
      String? guardadoAntes;
      final login = criarLoginWeb(
        api: api,
        origem: origem,
        nonces: nonces,
        irPara: (url) async {
          guardadoAntes = nonces.consumir();
          nonces.guardar(guardadoAntes!);
          idas.add(url);
        },
      );
      var terminou = false;
      unawaited(login((_) async {}).whenComplete(() => terminou = true));
      await pumpEventQueue();
      expect(terminou, isFalse);
      expect(idas, hasLength(1));
      final n = guardadoAntes!;
      expect(n, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(idas.single, urlInicioLogin(api, origem, n));
      expect(nonces.consumir(), n);
    });

    test('nonces diferentes a cada login', () async {
      final nonces = GuardaNonceMemoria();
      final vistos = <String>{};
      final login = criarLoginWeb(
        api: api,
        origem: origem,
        nonces: nonces,
        irPara: (url) async => vistos.add(url.queryParameters['n']!),
      );
      unawaited(login((_) async {}));
      unawaited(login((_) async {}));
      await pumpEventQueue();
      expect(vistos, hasLength(2));
    });

    test('cancelar → ErroGoogle("O login foi cancelado.")', () async {
      final cancelar = Completer<void>();
      final login = criarLoginWeb(
        api: api,
        origem: origem,
        nonces: GuardaNonceMemoria(),
        irPara: (_) async {},
      );
      final f = login((_) async {}, cancelar: cancelar.future);
      cancelar.complete();
      await expectLater(f, _erro<ErroGoogle>('O login foi cancelado.'));
    });

    test(
      'irPara que lança → ErroGoogle("O login não foi concluído.")',
      () async {
        final login = criarLoginWeb(
          api: api,
          origem: origem,
          nonces: GuardaNonceMemoria(),
          irPara: (_) async => throw StateError('bloqueado'),
        );
        await expectLater(
          login((_) async {}),
          _erro<ErroGoogle>('O login não foi concluído.'),
        );
      },
    );
  });

  group('gravarPacoteDaMesmaConta', () {
    late List<http.Request> pedidos;
    late ArmazenamentoMemoria a;
    late String antes;

    Future<String?> gravar(
      String email, {
      int statusToken = 200,
      int statusAbout = 200,
      bool pendurar = false,
    }) {
      pedidos = [];
      a = ArmazenamentoMemoria();
      gravarPacoteWeb(a, 'v1.antigo');
      antes = a.ler('token.json')!;
      final cliente = MockClient((r) async {
        pedidos.add(r);
        if (r.url.path == '/api/auth/token') {
          if (pendurar) await Completer<void>().future;
          return http.Response(
            jsonEncode({
              'access_token': 'at-novo',
              'expires_in': 3599,
              'pacote': 'v1.girado',
            }),
            statusToken,
          );
        }
        if (r.url.path == '/drive/v3/about') {
          return http.Response(
            jsonEncode({
              'user': {'emailAddress': email},
            }),
            statusAbout,
          );
        }
        return http.Response('{}', 200);
      });
      return gravarPacoteDaMesmaConta(
        a,
        _pacote,
        mesmaConta: 'ana@gmail.com',
        http: ClienteHttp(cliente),
        api: api,
        limite: const Duration(milliseconds: 50),
      );
    }

    test('outra conta: revoga o pacote novo e o token antigo fica', () async {
      expect(
        await gravar('bia@gmail.com'),
        'Entre com a mesma conta (ana@gmail.com). Para trocar de conta, '
        'use Sair na aba Conta.',
      );
      expect(a.ler('token.json'), antes);
      expect(jsonDecode(pedidos[0].body), {'pacote': _pacote});
      expect(pedidos[1].url.host, 'www.googleapis.com');
      expect(pedidos[1].headers['Authorization'], 'Bearer at-novo');
      final sair = pedidos.last;
      expect(sair.url.toString(), '$api/auth/sair');
      expect(jsonDecode(sair.body), {'pacote': 'v1.girado'});
    });

    test('a mesma conta: grava o token novo já renovado', () async {
      expect(await gravar('Ana@Gmail.com'), isNull);
      final t = lerToken(a)!;
      expect((t.token, t.refreshToken), ('at-novo', 'v1.girado'));
      expect(pedidos.where((r) => r.url.path == '/api/auth/sair'), isEmpty);
    });

    void semRevogar(String? aviso) {
      expect(aviso, 'O login não foi concluído.');
      expect(a.ler('token.json'), antes);
      expect(pedidos.where((r) => r.url.path == '/api/auth/sair'), isEmpty);
    }

    test('sem confirmar a conta (503): descarta o novo sem revogar', () async {
      semRevogar(await gravar('ana@gmail.com', statusToken: 503));
    });

    test('about que falha: descarta o novo sem revogar', () async {
      semRevogar(await gravar('ana@gmail.com', statusAbout: 500));
    });

    test('conferência além do limite: descarta o novo sem revogar', () async {
      semRevogar(await gravar('ana@gmail.com', pendurar: true));
    });
  });

  test('GuardaNonceMemoria: consumir devolve e apaga', () {
    final g = GuardaNonceMemoria();
    expect(g.consumir(), isNull);
    g.guardar('abc');
    expect(g.consumir(), 'abc');
    expect(g.consumir(), isNull);
  });

  group('criarRenovadorWeb', () {
    late List<http.Request> pedidos;

    RenovarToken renovador(Future<http.Response> Function() resposta) {
      pedidos = [];
      final cliente = MockClient((r) {
        pedidos.add(r);
        return resposta();
      });
      return criarRenovadorWeb(ClienteHttp(cliente), api);
    }

    http.Response json(int status, Object corpo) =>
        http.Response(jsonEncode(corpo), status);

    test('200 → token novo com o mesmo pacote', () async {
      final renovar = renovador(
        () async => json(200, {'access_token': 'a', 'expires_in': 3599}),
      );
      final t = await renovar(_tokenPacote());
      expect(pedidos, hasLength(1));
      final p = pedidos.single;
      expect(p.method, 'POST');
      expect(p.url.toString(), '$api/auth/token');
      expect(p.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(p.body), {'pacote': 'v1.p'});
      expect(t.token, 'a');
      expect(t.refreshToken, 'v1.p');
      expect(
        (t.clientId, t.clientSecret),
        (marcadorServidor, marcadorServidor),
      );
      expect(t.valido(ambiente.agora()), isTrue);
    });

    test('200 com scope → escopos devolvidos no token', () async {
      final renovar = renovador(
        () async => json(200, {
          'access_token': 'a',
          'expires_in': 3599,
          'scope': 'x y',
        }),
      );
      expect((await renovar(_tokenPacote())).scopes, ['x', 'y']);
    });

    test('200 sem scope → mantém os escopos do token atual', () async {
      final renovar = renovador(
        () async => json(200, {'access_token': 'a', 'expires_in': 3599}),
      );
      final atual = _tokenPacote()..scopes = ['antigo'];
      expect((await renovar(atual)).scopes, ['antigo']);
    });

    test('200 com pacote novo → refreshToken trocado', () async {
      final renovar = renovador(
        () async => json(200, {
          'access_token': 'a',
          'expires_in': 3599,
          'pacote': 'v1.q',
        }),
      );
      expect((await renovar(_tokenPacote())).refreshToken, 'v1.q');
    });

    test('401 → LoginNecessario', () async {
      final renovar = renovador(() async => json(401, {'erro': 'pacote'}));
      await expectLater(
        renovar(_tokenPacote()),
        _erro<LoginNecessario>('Sessão expirada. Faça login novamente.'),
      );
    });

    for (final (nome, resposta) in [
      ('404', () => http.Response('', 404)),
      ('403', () => http.Response('', 403)),
      ('200 com HTML', () => http.Response('<html>erro</html>', 200)),
      ('200 sem access_token', () => json(200, {'expires_in': 3599})),
      ('200 com lista', () => json(200, [1, 2])),
    ]) {
      test('$nome → Offline', () async {
        final renovar = renovador(() async => resposta());
        await expectLater(renovar(_tokenPacote()), throwsA(isA<Offline>()));
      });
    }

    test('503 → Offline', () async {
      final renovar = renovador(() async => http.Response('', 503));
      await expectLater(renovar(_tokenPacote()), throwsA(isA<Offline>()));
    });

    test('ClientException → Offline', () async {
      final renovar = renovador(
        () async => throw http.ClientException('sem rede'),
      );
      await expectLater(renovar(_tokenPacote()), throwsA(isA<Offline>()));
    });
  });

  group('revogarWeb', () {
    for (final (nome, resposta) in [
      ('500', () async => http.Response('', 500)),
      ('erro de rede', () async => throw http.ClientException('sem rede')),
    ]) {
      test('$nome → completa sem lançar', () async {
        final pedidos = <http.Request>[];
        final cliente = MockClient((r) {
          pedidos.add(r);
          return resposta();
        });
        await revogarWeb(ClienteHttp(cliente), api, 'v1.p');
        expect(pedidos.single.method, 'POST');
        expect(pedidos.single.url.toString(), '$api/auth/sair');
        expect(jsonDecode(pedidos.single.body), {'pacote': 'v1.p'});
      });
    }
  });

  group('lerRetornoLogin', () {
    RetornoLogin? ler(String fragmento, [String? esperado = _nonce]) =>
        lerRetornoLogin(
          Uri.parse('https://x/$fragmento'),
          nonceEsperado: esperado,
        );

    test('pacote válido com o nonce certo → RetornoPacote', () {
      final r = ler('#auth=$_pacote&n=$_nonce');
      expect(
        r,
        isA<RetornoPacote>().having((r) => r.pacote, 'pacote', _pacote),
      );
    });

    test('pacote válido com n errado ou sem n → RetornoErro("estado")', () {
      for (final r in [
        ler('#auth=$_pacote&n=outro-nonce-0123456789xx'),
        ler('#auth=$_pacote'),
        ler('#auth=$_pacote&n=$_nonce', null),
      ]) {
        expect(
          r,
          isA<RetornoErro>().having((e) => e.codigo, 'codigo', 'estado'),
        );
      }
    });

    test('auth_erro com n errado → RetornoErro("estado")', () {
      final r = ler('#auth_erro=acesso_negado&n=errado');
      expect(r, isA<RetornoErro>().having((e) => e.codigo, 'codigo', 'estado'));
    });

    test('acesso_negado → aviso de cancelado', () {
      final r = ler('#auth_erro=acesso_negado&n=$_nonce');
      expect(
        r,
        isA<RetornoErro>().having((e) => e.codigo, 'codigo', 'acesso_negado'),
      );
      expect(avisoRetorno(r! as RetornoErro), (
        'Login não concluído',
        'O login foi cancelado.',
      ));
    });

    test('pacote fora do formato → RetornoErro("falhou")', () {
      for (final p in ['lixo', 'v1.p', 'v1.${'a' * 19}', 'v1.${'a' * 4097}']) {
        final r = ler('#auth=$p&n=$_nonce');
        expect(
          r,
          isA<RetornoErro>().having((e) => e.codigo, 'codigo', 'falhou'),
        );
        expect(avisoRetorno(r! as RetornoErro), (
          'Login não concluído',
          'O login não foi concluído.',
        ));
      }
    });

    test('estado tem o mesmo aviso de falhou', () {
      expect(avisoRetorno(RetornoErro('estado')), (
        'Login não concluído',
        'O login não foi concluído.',
      ));
      final r = ler('#auth_erro=estado&n=$_nonce');
      expect(avisoRetorno(r! as RetornoErro), (
        'Login não concluído',
        'O login não foi concluído.',
      ));
    });

    test('rota ou sem fragmento → null', () {
      expect(ler('#/'), isNull);
      expect(ler(''), isNull);
      expect(ler('#/', null), isNull);
    });
  });
}
