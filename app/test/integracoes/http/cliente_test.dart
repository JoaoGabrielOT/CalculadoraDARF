import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../apoio/cliente_falso.dart';

final url = Uri.parse('https://x.com/a?b=1');

Future<Object?> capturar(Future<Object?> Function() f) async {
  try {
    await f();
  } catch (e) {
    return e;
  }
  return null;
}

Object? capturarSinc(void Function() f) {
  try {
    f();
  } catch (e) {
    return e;
  }
  return null;
}

ClienteHttp cliente(
  RespostaFalsa r, {
  Duration tempoLimite = const Duration(seconds: 20),
}) => ClienteHttp(ClienteFalso.fila([r]), tempoLimite: tempoLimite);

void main() {
  test('envia User-Agent e cabeçalhos extras', () async {
    final falso = ClienteFalso.fila([RespostaFalsa(200, texto: 'ok')]);
    final c = ClienteHttp(
      falso,
      userAgent: 'Mozilla/5.0',
      cabecalhos: {'Accept-Language': 'pt-BR'},
    );
    final r = await c.enviar('GET', url, cabecalhos: {'X-Teste': '1'});
    expect(r.body, 'ok');
    final p = falso.pedidos[0];
    expect(p.metodo, 'GET');
    expect(p.url, url);
    expect(p.cabecalhos['user-agent'], 'Mozilla/5.0');
    expect(p.cabecalhos['accept-language'], 'pt-BR');
    expect(p.cabecalhos['x-teste'], '1');
  });

  test('corpo: texto, formulário e bytes', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(200),
      RespostaFalsa(200),
      RespostaFalsa(200),
    ]);
    final c = ClienteHttp(falso);
    await c.enviar(
      'POST',
      url,
      cabecalhos: {'Content-Type': 'application/json'},
      corpo: jsonEncode({'a': 'é'}),
    );
    await c.enviar('POST', url, corpo: {'code': 'x y', 'k': 'é'});
    await c.enviar('PUT', url, corpo: [1, 2, 3]);
    expect(falso.pedidos[0].json, {'a': 'é'});
    expect(falso.pedidos[1].formulario, {'code': 'x y', 'k': 'é'});
    expect(
      falso.pedidos[1].cabecalhos['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(falso.pedidos[2].corpo, [1, 2, 3]);
  });

  test('não lança por status', () async {
    final r = await cliente(RespostaFalsa(404, motivo: 'Not Found'))
        .enviar('GET', url);
    expect(r.statusCode, 404);
    expect(r.reasonPhrase, 'Not Found');
  });

  test('falhas de transporte viram ErroConexao', () async {
    final erros = <Object>[
      const SocketException('Failed host lookup'),
      http.ClientException('Connection closed'),
      const HandshakeException('Handshake error'),
      TimeoutException('demorou'),
      const HttpException('Connection reset'),
    ];
    for (final erro in erros) {
      final e = await capturar(
        () => cliente(RespostaFalsa(0, erro: erro)).enviar('GET', url),
      );
      expect(e, isA<ErroConexao>(), reason: '$erro');
      expect(mensagemErro(e!), 'Sem conexão com a internet.');
    }
  });

  test('resposta mais lenta que o tempo limite vira ErroConexao', () async {
    final c = cliente(
      RespostaFalsa(200, atraso: const Duration(milliseconds: 200)),
      tempoLimite: const Duration(milliseconds: 50),
    );
    final e = await capturar(() => c.enviar('GET', url));
    expect(e, isA<ErroConexao>());
    expect(mensagemErro(e!), 'Sem conexão com a internet.');
  });

  test('tempo limite por chamada vale mais que o padrão', () async {
    final c = cliente(
      RespostaFalsa(200, atraso: const Duration(milliseconds: 100)),
      tempoLimite: const Duration(milliseconds: 20),
    );
    final r = await c.enviar(
      'GET',
      url,
      tempoLimite: const Duration(seconds: 5),
    );
    expect(r.statusCode, 200);
  });

  test('429 repete com as esperas e devolve a última resposta', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(429),
      RespostaFalsa(429),
      RespostaFalsa(200, texto: 'ok'),
    ]);
    final esperas = <Duration>[];
    final c = ClienteHttp(
      falso,
      repeticoes429: 2,
      esperar: (d) async => esperas.add(d),
    );
    final r = await c.enviar('GET', url);
    expect(r.statusCode, 200);
    expect(falso.pedidos.length, 3);
    expect(esperas, [const Duration(seconds: 2), const Duration(seconds: 5)]);
  });

  test('429 persistente devolve o 429 após as repetições', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(429),
      RespostaFalsa(429),
      RespostaFalsa(429),
      RespostaFalsa(429),
    ]);
    final esperas = <Duration>[];
    final c = ClienteHttp(
      falso,
      repeticoes429: 3,
      esperar: (d) async => esperas.add(d),
    );
    final r = await c.enviar('GET', url);
    expect(r.statusCode, 429);
    expect(falso.pedidos.length, 4);
    expect(esperas, [
      const Duration(seconds: 2),
      const Duration(seconds: 5),
      const Duration(seconds: 5),
    ]);
  });

  test('sem repeticoes429 o 429 volta direto', () async {
    final falso = ClienteFalso.fila([RespostaFalsa(429)]);
    final r = await ClienteHttp(falso).enviar('GET', url);
    expect(r.statusCode, 429);
    expect(falso.pedidos.length, 1);
  });

  test(
    '429 com Retry-After: 3 espera 3 s; Retry-After: 120 espera 30 s',
    () async {
      final esperas = <Duration>[];
      for (final valor in ['3', '120']) {
        final falso = ClienteFalso.fila([
          RespostaFalsa(429, cabecalhos: {'Retry-After': valor}),
          RespostaFalsa(200),
        ]);
        final c = ClienteHttp(
          falso,
          repeticoes429: 1,
          esperar: (d) async => esperas.add(d),
        );
        await c.enviar('GET', url);
      }
      expect(esperas, [
        const Duration(seconds: 3),
        const Duration(seconds: 30),
      ]);
    },
  );

  test('Retry-After que não é número usa a espera padrão', () async {
    final esperas = <Duration>[];
    final falso = ClienteFalso.fila([
      RespostaFalsa(429, cabecalhos: {'Retry-After': 'amanhã'}),
      RespostaFalsa(200),
    ]);
    await ClienteHttp(
      falso,
      repeticoes429: 1,
      esperar: (d) async => esperas.add(d),
    ).enviar('GET', url);
    expect(esperas, [const Duration(seconds: 2)]);
  });

  test('maxSimultaneas limita os pedidos em andamento', () async {
    final falso = ClienteFalso(
      (_) => RespostaFalsa(200, atraso: const Duration(milliseconds: 10)),
    );
    final c = ClienteHttp(falso, maxSimultaneas: 2);
    await Future.wait([for (var i = 0; i < 8; i++) c.enviar('GET', url)]);
    expect(falso.pedidos.length, 8);
    expect(falso.maxSimultaneos, 2);
  });

  test('o semáforo segura a vaga durante a espera do 429', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(429),
      RespostaFalsa(200),
      RespostaFalsa(200),
    ]);
    final liberar = Completer<void>();
    final c = ClienteHttp(
      falso,
      maxSimultaneas: 1,
      repeticoes429: 1,
      esperar: (_) => liberar.future,
    );
    final a = c.enviar('GET', url);
    final b = c.enviar('GET', Uri.parse('https://x.com/b'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(falso.pedidos.length, 1);
    liberar.complete();
    await Future.wait([a, b]);
    expect(falso.pedidos.map((p) => p.url.path), ['/a', '/a', '/b']);
  });

  test('conferirStatus: sucesso não faz nada', () {
    expect(capturarSinc(() => conferirStatus(200, url)), isNull);
    expect(capturarSinc(() => conferirStatus(304, url)), isNull);
  });

  test('conferirStatus: 429 persistente vira LimiteConsultas', () {
    final e = capturarSinc(() => conferirStatus(429, url));
    expect(e, isA<LimiteConsultas>());
    expect(e.toString(), 'Too Many Requests');
    expect(
      mensagemErro(e!),
      'Limite de consultas do Yahoo atingido. Tente em alguns minutos.',
    );
  });

  test('conferirStatus: 404 e 500 com o texto do requests', () {
    final e404 = capturarSinc(
      () => conferirStatus(404, url, motivo: 'Not Found'),
    );
    expect(e404, isA<ErroHttp>());
    expect((e404 as ErroHttp).status, 404);
    expect(
      e404.toString(),
      '404 Client Error: Not Found for url: https://x.com/a?b=1',
    );
    final e500 = capturarSinc(
      () => conferirStatus(500, url, motivo: 'Internal Server Error'),
    );
    expect(
      e500.toString(),
      '500 Server Error: Internal Server Error for url: https://x.com/a?b=1',
    );
    expect(e500, isA<ErroNucleo>());
  });

  test('conferirStatus sem motivo deixa o texto vazio como o requests', () {
    final e = capturarSinc(() => conferirStatus(503, url));
    expect(e.toString(), '503 Server Error:  for url: https://x.com/a?b=1');
  });

  test('abrir: blocos em fluxo, cabeçalhos e urlFinal', () async {
    final destino = Uri.parse('https://y.com/final');
    final falso = ClienteFalso.fila([
      RespostaFalsa(
        200,
        blocos: [
          [1, 2],
          [3],
        ],
        cabecalhos: {'content-length': '3', 'x-a': 'b'},
        urlFinal: destino,
        motivo: 'OK',
      ),
    ]);
    final c = ClienteHttp(falso, userAgent: 'UA');
    final r = await c.abrir('GET', url);
    expect(r.status, 200);
    expect(r.motivo, 'OK');
    expect(r.cabecalhos['x-a'], 'b');
    expect(r.urlFinal, destino);
    expect(await r.blocos.toList(), [
      [1, 2],
      [3],
    ]);
    expect(falso.pedidos[0].cabecalhos['user-agent'], 'UA');
  });

  test('abrir: sem urlFinal da resposta devolve a URL pedida', () async {
    final r = await cliente(RespostaFalsa(200, texto: 'x')).abrir('GET', url);
    expect(r.urlFinal, url);
    await r.blocos.drain<void>();
  });

  test('abrir: bloco mais lento que o tempo limite vira ErroConexao', () async {
    final c = cliente(
      RespostaFalsa(
        200,
        blocos: [
          [1],
          [2],
        ],
        atrasoBlocos: const Duration(milliseconds: 200),
      ),
      tempoLimite: const Duration(milliseconds: 50),
    );
    final r = await c.abrir('GET', url);
    final e = await capturar(() => r.blocos.toList());
    expect(e, isA<ErroConexao>());
  });

  test('abrir: falha de transporte vira ErroConexao', () async {
    final e = await capturar(
      () => cliente(
        RespostaFalsa(0, erro: const SocketException('Failed host lookup')),
      ).abrir('GET', url),
    );
    expect(e, isA<ErroConexao>());
  });

  test('decodificarJson preserva int e double', () async {
    final j = await decodificarJson(
      utf8.encode('{"a": 35, "b": 35.0}'),
      executarDireto,
    ) as Map;
    expect(j['a'], isA<int>());
    expect(j['b'], isA<double>());
  });

  test('decodificarJson decodifica UTF-8', () async {
    final j = await decodificarJson(
      utf8.encode('{"n": "ação"}'),
      executarDireto,
    );
    expect(j, {'n': 'ação'});
  });

  test('decodificarJson acima de 64 KiB passa pelo executar', () async {
    var chamadas = 0;
    Future<R> contar<R>(FutureOr<R> Function() t) async {
      chamadas++;
      return t();
    }

    await decodificarJson(utf8.encode('{"a": 1}'), contar);
    expect(chamadas, 0);
    final grande = utf8.encode('{"a": "${'x' * (limiteJsonDireto + 1)}"}');
    final j = await decodificarJson(grande, contar) as Map;
    expect(chamadas, 1);
    expect((j['a'] as String).length, limiteJsonDireto + 1);
  });
}
