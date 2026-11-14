import 'dart:async';
import 'dart:convert';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_reais.dart';
import 'package:calculadoradarf/app/servicos/servicos_web.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _api = Uri.parse('https://calculadora-darf-web.vercel.app/api');
final _origem = Uri.parse('https://calculadora-darf-web.vercel.app/');
final _pacote = 'v1.${'p' * 30}';

void main() {
  late ArmazenamentoMemoria a;
  late List<http.Request> pedidos;
  late List<Uri> idas;
  late List<EventoServico> eventos;
  late int statusToken;
  late ServicosApp s;

  http.Response responder(http.Request r) {
    if (r.url.path == '/api/auth/token') {
      return http.Response(
        jsonEncode({'access_token': 'at', 'expires_in': 3600}),
        statusToken,
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
    a = ArmazenamentoMemoria();
    pedidos = [];
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

  test('sem atualizador', () {
    expect(s.verificarAtualizacao, throwsStateError);
  });
}
