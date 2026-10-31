// Porte de TestHistoricoMercado e TestHistoricoComBaixaEAbertura
// (tests/test_metas.py:442-477, 1184-1205) e de TestBarrasDiarias
// (tests/test_sugestoes.py:264-306).

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/mercado/chart.dart';
import 'package:flutter_test/flutter_test.dart';

/// `FUSO` (-03:00) do metas.py.
final _agora = DataHora.parse('2026-10-22T12:00:00-03:00');
final _desde = DataHora.parse('2026-10-20T11:00:00');

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  group('TestHistoricoMercado', () {
    test('TestHistoricoMercado.test_intervalos', () {
      expect(intervalosHistorico(3)[0], '1m');
      expect(intervalosHistorico(30)[0], '5m');
      expect(intervalosHistorico(200)[0], '1h');
      expect(intervalosHistorico(1000), ['1d']);
    });

    test(
      'TestHistoricoMercado.test_historico_desde_usa_chart_e_fuso',
      () async {
        final chamadas = <Map<String, String>>[];
        Future<Map<String, Object?>> falso(
          String ticker,
          Map<String, String> params,
        ) async {
          chamadas.add(params);
          if (params['interval'] == '1m') throw SemDados('sem 1m');
          return {
            'meta': {'gmtoffset': -10800},
            'timestamp': [1761051600, 1761055200],
            'indicators': {
              'quote': [
                {
                  'high': [21.5, null],
                },
              ],
            },
          };
        }

        final h = await historicoDesde(
          'PETR4',
          _desde,
          agora: _agora,
          obterChart: falso,
        );
        expect([for (final c in chamadas) c['interval']], ['1m', '5m']);
        expect(h.intervalo, '5m');
        expect(h.barras, hasLength(1));
        expect(h.barras[0].dt.desvio, -3 * 3600);
      },
    );

    test('TestHistoricoMercado.test_sem_barras_levanta', () {
      Future<Map<String, Object?>> vazio(
        String t,
        Map<String, String> p,
      ) async => {
        'meta': <String, Object?>{},
        'timestamp': [],
        'indicators': {
          'quote': [<String, Object?>{}],
        },
      };
      expect(
        historicoDesde('PETR4', _desde, agora: _agora, obterChart: vazio),
        throwsA(isA<SemDados>()),
      );
    });
  });

  group('TestHistoricoComBaixaEAbertura', () {
    test(
      'TestHistoricoComBaixaEAbertura.test_barras_trazem_baixa_e_abre',
      () async {
        Future<Map<String, Object?>> falso(
          String t,
          Map<String, String> p,
        ) async => {
          'meta': {'gmtoffset': -10800},
          'timestamp': [1761051600, 1761055200],
          'indicators': {
            'quote': [
              {
                'high': [21.5, null],
                'low': [20.9, 20.0],
                'open': [null, 21.0],
              },
            ],
          },
        };
        final h = await historicoDesde(
          'PETR4',
          _desde,
          agora: _agora,
          obterChart: falso,
        );
        expect(h.barras, hasLength(1));
        final b = h.barras[0];
        expect((b.alta, b.baixa, b.abre), (21.5, 20.9, null));
      },
    );

    test(
      'TestHistoricoComBaixaEAbertura.test_baixa_ausente_fica_none',
      () async {
        Future<Map<String, Object?>> falso(
          String t,
          Map<String, String> p,
        ) async => {
          'meta': <String, Object?>{},
          'timestamp': [1761051600],
          'indicators': {
            'quote': [
              {
                'high': [21.5],
              },
            ],
          },
        };
        final h = await historicoDesde(
          'PETR4',
          _desde,
          agora: _agora,
          obterChart: falso,
        );
        expect((h.barras[0].baixa, h.barras[0].abre), (null, null));
      },
    );
  });

  group('TestBarrasDiarias', () {
    late CacheDiarias cache;
    setUp(() => cache = CacheDiarias());

    test('TestBarrasDiarias.test_barras_data_e_cache', () async {
      final chamadas = <Map<String, String>>[];
      Future<Map<String, Object?>> falso(
        String ticker,
        Map<String, String> params,
      ) async {
        chamadas.add(params);
        return {
          'meta': {
            'gmtoffset': -10800,
            'regularMarketTime': 1761685200,
            'regularMarketPrice': 10.4,
          },
          'timestamp': [1761051600, 1761138000, 1761224400],
          'indicators': {
            'quote': [
              {
                'open': [10, null, 10.2],
                'high': [11, 11, 11],
                'low': [9, 9, null],
                'close': [10, 10, 10],
              },
            ],
          },
        };
      }

      final r = await cache.barrasDiarias('PETR4', obterChart: falso);
      expect(r.barras, hasLength(2)); // a barra sem mínima é descartada
      expect(r.barras[0].data, '2025-10-21');
      expect(r.barras[0].abre, 10.0);
      expect(r.preco, 10.4);
      expect(r.hoje, '2025-10-28');
      expect(chamadas[0]['range'], '6mo');
      await cache.barrasDiarias('PETR4', obterChart: falso);
      expect(chamadas, hasLength(1)); // segunda chamada vem do cache
      await cache.barrasDiarias(
        'PETR4',
        desde: somarDias(ambiente.hoje(), -300),
        obterChart: falso,
      );
      expect(['1y', '2y'], contains(chamadas.last['range']));
    });

    test('TestBarrasDiarias.test_sem_barras_levanta', () {
      Future<Map<String, Object?>> vazio(
        String t,
        Map<String, String> p,
      ) async => {
        'meta': <String, Object?>{},
        'timestamp': [],
        'indicators': {
          'quote': [<String, Object?>{}],
        },
      };
      expect(
        cache.barrasDiarias('PETR4', obterChart: vazio),
        throwsA(isA<SemDados>()),
      );
    });

    test('TestBarrasDiarias.test_range_pelo_alcance', () {
      final hoje = ambiente.hoje();
      expect(rangeDiarias(null), '6mo');
      expect(rangeDiarias(somarDias(hoje, -100)), '6mo');
      expect(rangeDiarias(somarDias(hoje, -200)), '1y');
      expect(rangeDiarias(somarDias(hoje, -500)), '2y');
      expect(rangeDiarias(somarDias(hoje, -900)), '5y');
    });
  });
}
