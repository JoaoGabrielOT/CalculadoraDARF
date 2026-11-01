import 'dart:async';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';
import '../apoio/cliente_falso.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

Future<Object?> _capturar(Future<Object?> Function() f) async {
  try {
    await f();
  } catch (e) {
    return e;
  }
  return null;
}

/// Mesma configuração de `ServicoYahoo.clientePadrao`, sem dormir de verdade.
ClienteHttp _cliente(ClienteFalso falso, {int repeticoes429 = 0}) =>
    ClienteHttp(
      falso,
      userAgent: 'Mozilla/5.0',
      maxSimultaneas: 3,
      repeticoes429: repeticoes429,
      esperar: (_) async {},
    );

ServicoYahoo _servico(ClienteFalso falso, {int repeticoes429 = 0}) =>
    ServicoYahoo(
      _cliente(falso, repeticoes429: repeticoes429),
      executar: executarDireto,
    );

/// Corpo do chart com [n] pregões diários (preço da meta em [preco], texto
/// cru para preservar `int`).
String _corpoDados({int n = 20, String preco = '10.5'}) {
  final ts = [for (var i = 0; i < n; i++) 1760000000 + i * 86400];
  final altas = [for (var i = 0; i < n; i++) 11.0 + i * 0.1];
  final baixas = [for (var i = 0; i < n; i++) 9.0 + i * 0.1];
  final fech = [for (var i = 0; i < n; i++) 10.0 + i * 0.1];
  return '{"chart": {"result": [{"meta": {"regularMarketPrice": $preco, '
      '"gmtoffset": -10800, "longName": "Petrobras"}, '
      '"timestamp": $ts, "indicators": {"quote": [{"high": $altas, '
      '"low": $baixas, "close": $fech}]}}]}}';
}

String _corpoGrafico() =>
    '{"chart": {"result": [{"meta": {"gmtoffset": -10800}, '
    '"timestamp": [1760990000, 1760990300, 1760990600], '
    '"indicators": {"quote": [{"close": [10.0, 10.5, 11.0]}]}}]}}';

void _fixarRelogio(double agora) {
  ambiente = Ambiente.fixo(agora: agora);
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  group('repetição do Python', () {
    for (final caso in carregarCasos('yahoo_rede')) {
      test('${caso.funcao} ${caso.nome}', () async {
        ambiente = Ambiente.fixo();
        final e = _mapa(caso.entrada);
        final saida = _mapa(caso.saida);
        final respostas = _lista(e['respostas']);
        final falso = ClienteFalso.fila([
          for (final bruto in respostas)
            RespostaFalsa(
              _mapa(bruto)['status']! as int,
              json: _mapa(bruto)['json'],
              motivo: (_mapa(bruto)['status']! as int) >= 500
                  ? 'Internal Server Error'
                  : null,
            ),
        ]);
        final yahoo = _servico(falso);
        final ticker = e['ticker']! as String;
        final Future<Object?> Function() chamada = switch (caso.funcao) {
          'cotacao' => () => yahoo.cotacao(ticker),
          'fechamento' => () async {
            final (p, d) = await yahoo.fechamento(ticker, e['dia']! as String);
            return [p, d];
          },
          'preco_venda' => () async {
            final (p, r) = await yahoo.precoVenda(ticker, e['dia']! as String);
            return [p, r];
          },
          'grafico' => () async => (await yahoo.grafico(
            ticker,
            e['periodo']! as String,
          )).toJson(),
          _ => throw StateError('função desconhecida: ${caso.funcao}'),
        };

        Object? resultado;
        Object? erro;
        try {
          resultado = await chamada();
        } catch (ex) {
          erro = ex;
        }

        // Mesmos pedidos: URL sem query, params e User-Agent.
        final esperados = _lista(saida['pedidos']);
        expect(falso.pedidos, hasLength(esperados.length));
        for (final (i, bruto) in esperados.indexed) {
          final esperado = _mapa(bruto);
          final pedido = falso.pedidos[i];
          final u = pedido.url;
          expect(
            Uri(scheme: u.scheme, host: u.host, path: u.path).toString(),
            esperado['url'],
          );
          conferir(u.queryParametersAll, esperado['params']);
          expect(pedido.cabecalhos['user-agent'], 'Mozilla/5.0');
        }

        if (saida.containsKey('erro')) {
          expect(erro, isNotNull, reason: 'devia lançar ${saida['erro']}');
          final tipo = switch (saida['erro']) {
            'SemDados' => erro is SemDados,
            'LimiteConsultas' => erro is LimiteConsultas,
            'ErroHttp' => erro is ErroHttp,
            _ => false,
          };
          expect(tipo, isTrue, reason: '${erro.runtimeType}: $erro');
          expect(erro.toString(), saida['mensagem']);
        } else {
          expect(erro, isNull);
          conferir(resultado, saida['resultado']);
        }
      });
    }
  });

  group('dados', () {
    test('cache de 60 s por ticker', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoDados()),
      );
      final yahoo = _servico(falso);
      const t = 1761000000.0;
      _fixarRelogio(t);
      final primeiro = await yahoo.dados('PETR4');
      expect(falso.pedidos, hasLength(1));
      expect(primeiro.hora, t);
      _fixarRelogio(t + 60);
      final segundo = await yahoo.dados('PETR4');
      expect(falso.pedidos, hasLength(1));
      expect(segundo.hora, t + 60);
      _fixarRelogio(t + 61);
      await yahoo.dados('PETR4');
      expect(falso.pedidos, hasLength(2));
      await yahoo.dados('VALE3');
      expect(falso.pedidos, hasLength(3));
    });

    test('period1 = fim − 180·86400 e interval 1d', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoDados()),
      );
      _fixarRelogio(1761000000.9);
      await _servico(falso).dados('PETR4');
      expect(falso.pedidos.single.url.queryParameters, {
        'period1': '${1761000000 - 180 * 86400}',
        'period2': '1761000000',
        'interval': '1d',
      });
    });

    test('nome conhecido tem prioridade e o do Yahoo é o padrão', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoDados()),
      );
      final yahoo = _servico(falso);
      expect((await yahoo.dados('PETR4')).nome, 'Petrobras');
      expect(
        (await yahoo.dados('PETR4', nomeConhecido: 'Minha')).nome,
        'Minha',
      );
    });

    test('histórico insuficiente não entra no cache', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoDados(n: 5)),
      );
      final yahoo = _servico(falso);
      expect(await _capturar(() => yahoo.dados('PETR4')), isA<SemDados>());
      expect(await _capturar(() => yahoo.dados('PETR4')), isA<SemDados>());
      expect(falso.pedidos, hasLength(2));
    });

    test('limpar esvazia o cache de dados', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoDados()),
      );
      final yahoo = _servico(falso);
      await yahoo.dados('PETR4');
      yahoo.limpar();
      await yahoo.dados('PETR4');
      expect(falso.pedidos, hasLength(2));
    });

    test(
      'preço inteiro do chart chega como int ao dadosAtivoDeChart',
      () async {
        final falso = ClienteFalso(
          (_) => RespostaFalsa(200, texto: _corpoDados(preco: '35')),
        );
        final d = await _servico(falso).dados('PETR4');
        expect(d.preco, 35);
        expect(d.preco, isA<double>());
      },
    );

    test('8 dados ao mesmo tempo: no máximo 3 pedidos abertos', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(
          200,
          texto: _corpoDados(),
          atraso: const Duration(milliseconds: 20),
        ),
      );
      final yahoo = _servico(falso);
      await Future.wait([for (var i = 0; i < 8; i++) yahoo.dados('TICK$i')]);
      expect(falso.pedidos, hasLength(8));
      expect(falso.maxSimultaneos, 3);
    });
  });

  group('erros', () {
    test('404 → SemDados("Sem dados para PETR4 no Yahoo Finance.")', () async {
      final yahoo = _servico(ClienteFalso.fila([RespostaFalsa(404)]));
      final e = await _capturar(() => yahoo.obterChart('PETR4', {}));
      expect(e, isA<SemDados>());
      expect(e.toString(), 'Sem dados para PETR4 no Yahoo Finance.');
    });

    for (final corpo in ['<html>erro</html>', '[1, 2]']) {
      test(
        '200 com corpo que não é o JSON esperado ($corpo) → SemDados',
        () async {
          final yahoo = _servico(
            ClienteFalso.fila([RespostaFalsa(200, texto: corpo)]),
          );
          final e = await _capturar(() => yahoo.obterChart('PETR4', {}));
          expect(e, isA<SemDados>());
          expect(e.toString(), 'Sem dados para PETR4 no Yahoo Finance.');
        },
      );
    }

    test('429 três vezes: LimiteConsultas e mensagemErro do Yahoo', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(429),
        RespostaFalsa(429),
        RespostaFalsa(429),
      ]);
      final yahoo = _servico(falso, repeticoes429: 2);
      final e = await _capturar(() => yahoo.cotacao('PETR4'));
      expect(e, isA<LimiteConsultas>());
      expect(
        mensagemErro(e!),
        mensagemErro(LimiteConsultas('Too Many Requests')),
      );
      expect(falso.pedidos, hasLength(3));
    });

    test('rede caindo vira ErroConexao', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, erro: TimeoutException('x')),
      ]);
      final e = await _capturar(() => _servico(falso).cotacao('PETR4'));
      expect(e, isA<ErroConexao>());
    });
  });

  group('grafico', () {
    test('cache de 60 s no 1D e 3600 s no 5A', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(200, texto: _corpoGrafico()),
      );
      final yahoo = _servico(falso);
      const t = 1761000000.0;
      _fixarRelogio(t);
      await yahoo.grafico('PETR4', '1D');
      await yahoo.grafico('PETR4', '5A');
      expect(falso.pedidos, hasLength(2));
      _fixarRelogio(t + 59);
      await yahoo.grafico('PETR4', '1D');
      await yahoo.grafico('PETR4', '5A');
      expect(falso.pedidos, hasLength(2));
      _fixarRelogio(t + 60);
      await yahoo.grafico('PETR4', '1D');
      await yahoo.grafico('PETR4', '5A');
      expect(falso.pedidos, hasLength(3));
      _fixarRelogio(t + 3600);
      await yahoo.grafico('PETR4', '5A');
      expect(falso.pedidos, hasLength(4));
    });
  });

  group('histórico das metas', () {
    test('historico chega ao HTTP com os params de historicoDesde', () async {
      final falso = ClienteFalso(
        (_) => RespostaFalsa(
          200,
          texto:
              '{"chart": {"result": [{"meta": {"gmtoffset": -10800}, '
              '"timestamp": [1760990000], "indicators": {"quote": [{'
              '"high": [11.0], "low": [9.0], "open": [10.0]}]}}]}}',
        ),
      );
      _fixarRelogio(1761000000);
      final desde = DataHora.deTimestamp(1760900000, 0);
      final h = await _servico(falso).historico('PETR4', desde);
      expect(h.intervalo, '1m');
      expect(falso.pedidos.single.url.queryParameters, {
        'period1': '1760900000',
        'period2': '1761000060',
        'interval': '1m',
        'includePrePost': 'false',
      });
    });

    test(
      'diarias e barrasDiarias chegam ao HTTP com os params de rangeDiarias',
      () async {
        final corpo =
            '{"chart": {"result": [{"meta": {"gmtoffset": 0}, '
            '"timestamp": [1760990000], "indicators": {"quote": [{'
            '"high": [11.0], "low": [9.0], "close": [10.0]}]}}]}}';
        final falso = ClienteFalso((_) => RespostaFalsa(200, texto: corpo));
        final yahoo = _servico(falso);
        ambiente = Ambiente.fixo();
        await yahoo.diarias('PETR4', '2026-10-01');
        expect(falso.pedidos.single.url.queryParameters, {
          'range': '6mo',
          'interval': '1d',
          'includePrePost': 'false',
        });
        await yahoo.barrasDiarias('VALE3');
        expect(falso.pedidos.last.url.queryParameters['range'], '6mo');
        expect(falso.pedidos, hasLength(2));
        // Mesmo (ticker, range): o cache de 15 minutos do núcleo atende.
        await yahoo.diarias('PETR4', '2026-10-01');
        expect(falso.pedidos, hasLength(2));
      },
    );
  });
}
