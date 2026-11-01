import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/compat/ordenacao.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/mercado/indicadores.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

/// `chart.result[0]` da resposta 200 gravada; a interpretação sem rede só vê
/// esse resultado (vazio, 404, 429 e 500 são da Tarefa 5).
Map<String, Object?>? _resultado(Caso c) {
  final r = _mapa(_lista(_mapa(c.entrada)['respostas']).first);
  if (r['status'] != 200) return null;
  final chart = _mapa(r['json'])['chart'];
  final lista = chart == null ? null : _mapa(chart)['result'];
  return lista is List && lista.isNotEmpty ? _mapa(lista.first) : null;
}

bool _status200ComResultado(Caso c) => _resultado(c) != null;

/// O pedido gravado pelo Python tem a url, o User-Agent e os params dados.
void _conferirPedido(Caso c, Map<String, String> params) {
  final pedido = _mapa(_lista(_mapa(c.saida)['pedidos']).single);
  final ticker = _mapa(c.entrada)['ticker']! as String;
  conferir(pedido['url'], uriChart(ticker, {}).toString());
  conferir(pedido['cabecalhos'], {'User-Agent': 'Mozilla/5.0'});
  conferir(pedido['params'], {
    for (final e in params.entries) e.key: [e.value],
  });
}

Matcher _semDados(String mensagem) =>
    throwsA(isA<SemDados>().having((e) => e.toString(), 'mensagem', mensagem));

void main() {
  test('constantes e uriChart', () {
    expect(
      urlChart,
      'https://query1.finance.yahoo.com/v8/finance/chart/{t}.SA',
    );
    expect(diasHistorico, 180);
    expect(
      uriChart('PETR4', {'range': '5d', 'interval': '1d'}).toString(),
      'https://query1.finance.yahoo.com/v8/finance/chart/PETR4.SA'
      '?range=5d&interval=1d',
    );
  });

  test('paramsDados: period1 = fim − 180·86400', () {
    expect(paramsDados(1761000000.9), {
      'period1': '1745448000',
      'period2': '1761000000',
      'interval': '1d',
    });
  });

  test('paramsCotacao', () {
    expect(paramsCotacao(), {'range': '5d', 'interval': '1d'});
  });

  test('paramsGrafico: um por período', () {
    for (final e in periodosGrafico.entries) {
      expect(paramsGrafico(e.key), {
        'range': e.value.$1,
        'interval': e.value.$2,
        'includePrePost': 'false',
      });
    }
  });

  group('cotacao', () {
    test('há casos', () {
      expect(
        carregarCasos('yahoo_rede')
            .where((c) => c.funcao == 'cotacao')
            .where(_status200ComResultado),
        isNotEmpty,
      );
    });
    for (final caso in carregarCasos(
      'yahoo_rede',
    ).where((c) => c.funcao == 'cotacao').where(_status200ComResultado)) {
      test(caso.nome, () {
        _conferirPedido(caso, paramsCotacao());
        final ticker = _mapa(caso.entrada)['ticker']! as String;
        final saida = _mapa(caso.saida);
        final res = _resultado(caso)!;
        if (saida.containsKey('erro')) {
          expect(
            () => cotacaoDeChart(ticker, res),
            _semDados(saida['mensagem']! as String),
          );
        } else {
          conferir(cotacaoDeChart(ticker, res), saida['resultado']);
        }
      });
    }
  });

  group('fechamento', () {
    test('há casos', () {
      expect(
        carregarCasos('yahoo_rede')
            .where((c) => c.funcao == 'fechamento' || c.funcao == 'preco_venda')
            .where(_status200ComResultado),
        isNotEmpty,
      );
    });
    for (final caso
        in carregarCasos('yahoo_rede')
            .where((c) => c.funcao == 'fechamento' || c.funcao == 'preco_venda')
            .where(_status200ComResultado)) {
      final e = _mapa(caso.entrada);
      final dia = e['dia']! as String;
      // preco_venda de hoje ou do futuro é a cotação (Tarefa 5).
      if (caso.funcao == 'preco_venda' &&
          compararTexto(dia, '2026-10-28') >= 0) {
        continue;
      }
      test('${caso.funcao}: ${caso.nome}', () {
        _conferirPedido(caso, paramsFechamento(dia));
        final ticker = e['ticker']! as String;
        final saida = _mapa(caso.saida);
        final res = _resultado(caso)!;
        if (saida.containsKey('erro')) {
          expect(
            () => fechamentoDeChart(ticker, res, dia),
            _semDados(saida['mensagem']! as String),
          );
          return;
        }
        final (preco, data) = fechamentoDeChart(ticker, res, dia);
        conferir([
          preco,
          if (caso.funcao == 'fechamento')
            data
          else
            'Fechamento de ${fmtData(data)}',
        ], saida['resultado']);
      });
    }
  });

  group('grafico', () {
    test('há casos', () {
      expect(
        carregarCasos('yahoo_rede')
            .where((c) => c.funcao == 'grafico')
            .where(_status200ComResultado),
        isNotEmpty,
      );
    });
    for (final caso in carregarCasos(
      'yahoo_rede',
    ).where((c) => c.funcao == 'grafico').where(_status200ComResultado)) {
      test(caso.nome, () {
        final e = _mapa(caso.entrada);
        final ticker = e['ticker']! as String;
        final periodo = e['periodo']! as String;
        _conferirPedido(caso, paramsGrafico(periodo));
        final saida = _mapa(caso.saida);
        final res = _resultado(caso)!;
        if (saida.containsKey('erro')) {
          expect(
            () => graficoDeChart(ticker, periodo, res),
            _semDados(saida['mensagem']! as String),
          );
        } else {
          conferir(
            graficoDeChart(ticker, periodo, res).toJson(),
            saida['resultado'],
          );
        }
      });
    }
  });
}
