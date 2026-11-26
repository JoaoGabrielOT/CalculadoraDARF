import 'dart:async';
import 'dart:convert';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_reais.dart';
import 'package:calculadoradarf/app/servicos/servicos_web.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/armazenamento_chave_valor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../nucleo/apoio/fixture_relatorio.dart';

final _api = Uri.parse('https://calculadora-darf-web.vercel.app/api');
final _origem = Uri.parse('https://calculadora-darf-web.vercel.app/');
final _pacote = 'v1.${'p' * 30}';
const _nomeRelatorio = 'relatorio-abertura-2026-11-26.json';

/// Os escopos da 2.6.0, antes do `drive.readonly`.
const _escoposAntigos = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

void main() {
  late ChaveValorMemoria kv;
  late ArmazenamentoChaveValor a;
  late List<http.Request> pedidos;
  late List<Uri> idas;
  late List<EventoServico> eventos;
  late int statusToken;
  late ServicosApp s;

  /// Resposta da listagem da pasta; nula = 503.
  http.Response? listagem;

  http.Response responder(http.Request r) {
    if (r.url.path == '/api/auth/token') {
      return http.Response(
        jsonEncode({'access_token': 'at', 'expires_in': 3600}),
        statusToken,
      );
    }
    if (r.url.path == '/drive/v3/files' &&
        r.url.queryParameters['q'] == consultaRelatorios) {
      return listagem ?? http.Response('', 503);
    }
    if (r.url.path == '/drive/v3/files/r1' &&
        r.url.queryParameters['alt'] == 'media') {
      return http.Response.bytes(
        utf8.encode(jsonEncode(fixtureRelatorio())),
        200,
      );
    }
    if (r.url.path == '/drive/v3/about') {
      return http.Response(
        jsonEncode({
          'user': {'emailAddress': 'eu@x.com'},
        }),
        200,
      );
    }
    return http.Response('', 503);
  }

  setUp(() {
    kv = ChaveValorMemoria();
    a = ArmazenamentoChaveValor(kv);
    pedidos = [];
    listagem = null;
    idas = [];
    eventos = [];
    statusToken = 200;
    s = criarServicosWeb(
      api: _api,
      origem: _origem,
      armazenamento: a,
      irPara: (url) async => idas.add(url),
      abrirUrl: (_) async => true,
      cliente: MockClient((r) async {
        pedidos.add(r);
        return responder(r);
      }),
      timers: false,
    );
    s.eventos.listen(eventos.add);
  });

  tearDown(() => s.encerrar());

  // `cotacao()` do ServicosApp pede o histórico (period1/period2); a
  // cotação curta (`ServicoYahoo.cotacao`, range=5d) vem pelos preços.
  test('cotação passa pelo servidor, sem User-Agent', () async {
    await s.precosCarteira({'PETR4'});
    expect(pedidos, hasLength(1));
    expect(
      pedidos.single.url.toString(),
      'https://calculadora-darf-web.vercel.app/api/yahoo/chart/PETR4.SA'
      '?range=5d&interval=1d',
    );
    expect(
      pedidos.single.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('user-agent')),
    );
  });

  test('tickSync renova pelo servidor e consulta o Google direto', () async {
    gravarPacoteWeb(a, _pacote);
    await s.iniciar();
    await (s as ServicosReais).tickSync();

    final token = pedidos[0];
    expect(token.method, 'POST');
    expect(
      token.url.toString(),
      'https://calculadora-darf-web.vercel.app/api/auth/token',
    );
    expect(jsonDecode(token.body), {'pacote': _pacote});
    final about = pedidos[1];
    expect(about.method, 'GET');
    expect(about.url.host, 'www.googleapis.com');
    expect(about.url.path, '/drive/v3/about');
    expect(about.headers['Authorization'], 'Bearer at');
    expect((await s.conta()).email, 'eu@x.com');
  });

  Future<void> recusarPacote() async {
    statusToken = 401;
    gravarPacoteWeb(a, _pacote);
    await s.iniciar();
    await (s as ServicosReais).tickSync();
    await pumpEventQueue();
  }

  test('401 na renovação apaga o token e desliga a sincronização', () async {
    await recusarPacote();

    expect(a.existe('token.json'), isFalse);
    final c = await s.conta();
    expect(c.temToken, isFalse);
    expect(c.status, StatusSync.off);
  });

  // O aviso "Sessão expirada" da Web vem do EstadoApp quando a sessão cai
  // sem a pessoa sair (test/app/telas/login_web_test.dart).

  test('conectar sai da página rumo ao login do servidor', () async {
    await s.iniciar();
    unawaited(s.conectar());
    await pumpEventQueue();

    expect(idas, hasLength(1));
    final ida = idas.single;
    expect(
      ida.replace(queryParameters: {'volta': ida.queryParameters['volta']}),
      Uri.parse(
        'https://calculadora-darf-web.vercel.app/api/auth/inicio'
        '?volta=https%3A%2F%2Fcalculadora-darf-web.vercel.app',
      ),
    );
    expect(ida.queryParameters['n'], hasLength(43));
    expect((await s.conta()).status, StatusSync.login);
    await s.cancelarLogin();
  });

  test('sair revoga o pacote no servidor', () async {
    gravarPacoteWeb(a, _pacote);
    await s.iniciar();
    await s.sair();
    await pumpEventQueue();

    final sair = pedidos.where((r) => r.url.path == '/api/auth/sair');
    expect(sair, hasLength(1));
    expect(sair.single.method, 'POST');
    expect(jsonDecode(sair.single.body), {'pacote': _pacote});
  });

  group('relatórios', () {
    /// Token de acesso ainda válido: a sessão abre sem passar pelo servidor.
    Future<void> abrirSessao(List<String> escopos) async {
      gravarToken(
        a,
        TokenGoogle(
          token: 'at-drive',
          refreshToken: _pacote,
          clientId: marcadorServidor,
          clientSecret: marcadorServidor,
          scopes: escopos,
          expiry: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await s.iniciar();
      await (s as ServicosReais).tickSync();
      expect((await s.conta()).email, 'eu@x.com');
    }

    test('lista e baixa direto do Drive com Bearer, sem o servidor', () async {
      listagem = http.Response(
        jsonEncode({
          'files': [
            {
              'id': 'r1',
              'name': _nomeRelatorio,
              'modifiedTime': '2026-11-26T12:00:00.000Z',
            },
          ],
        }),
        200,
      );
      await abrirSessao(escoposGoogle);
      pedidos.clear();

      final v = await s.atualizarRelatorios();

      expect(v.situacao, SituacaoRelatorios.ok);
      expect(v.itens.single.nome, _nomeRelatorio);
      final lista = pedidos.first;
      expect(lista.method, 'GET');
      expect(lista.url.host, 'www.googleapis.com');
      expect(lista.url.path, '/drive/v3/files');
      expect(lista.url.queryParameters['q'], consultaRelatorios);
      expect(lista.headers['Authorization'], 'Bearer at-drive');
      final baixa = pedidos[1];
      expect(
        baixa.url.toString(),
        'https://www.googleapis.com/drive/v3/files/r1?alt=media',
      );
      expect(baixa.headers['Authorization'], 'Bearer at-drive');
      expect(pedidos, hasLength(2));
      expect(kv.obter('darf:relatorios/$_nomeRelatorio'), isNotNull);
      expect(
        jsonDecode(kv.obter('darf:relatorios/$_nomeRelatorio')!),
        fixtureRelatorio(),
      );
    });

    test('nenhum pedido ao servidor na sessão e nos relatórios', () async {
      listagem = http.Response(jsonEncode({'files': <Object>[]}), 200);
      await abrirSessao(escoposGoogle);
      await s.atualizarRelatorios();
      expect(pedidos.where((r) => r.url.host == _api.host), isEmpty);
    });

    test('token sem drive.readonly pede novo login sem ir ao Drive', () async {
      await abrirSessao(_escoposAntigos);
      pedidos.clear();

      final v = await s.atualizarRelatorios();

      expect(v.situacao, SituacaoRelatorios.novoLogin);
      expect(pedidos, isEmpty);
      // a conta continua conectada
      expect((await s.conta()).email, 'eu@x.com');
    });

    test('403 de escopo do Drive vira novo login', () async {
      listagem = http.Response(
        jsonEncode({
          'error': {
            'code': 403,
            'message': 'Request had insufficient authentication scopes.',
            'errors': [
              {'reason': 'insufficientPermissions'},
            ],
          },
        }),
        403,
      );
      await abrirSessao(escoposGoogle);

      final v = await s.atualizarRelatorios();

      expect(v.situacao, SituacaoRelatorios.novoLogin);
      expect((await s.conta()).email, 'eu@x.com');
    });

    test('só 5 relatórios guardam o conteúdo', () async {
      listagem = http.Response(
        jsonEncode({
          'files': [
            for (var d = 10; d < 17; d++)
              {
                'id': 'r1',
                'name': 'relatorio-abertura-2026-10-$d.json',
                'modifiedTime': '2026-11-26T12:00:00.000Z',
              },
          ],
        }),
        200,
      );
      await abrirSessao(escoposGoogle);

      final v = await s.atualizarRelatorios();

      expect(v.itens, hasLength(7));
      expect(
        kv.chaves().where(
          (c) => c.startsWith('darf:relatorios/relatorio-abertura-'),
        ),
        hasLength(5),
      );
    });
  });

  test('sem atualizador', () {
    expect(s.verificarAtualizacao, throwsStateError);
  });
}
