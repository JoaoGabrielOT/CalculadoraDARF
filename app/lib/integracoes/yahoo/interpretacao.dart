// Parte sem rede de `Mercado.cotacao`, `fechamento` e `grafico` e os params
// dos pedidos ao chart do Yahoo (mercado.py:265-325, 339-345, 441-466).

import '../../nucleo/compat/ordenacao.dart';
import '../../nucleo/datas.dart';
import '../../nucleo/erros.dart';
import '../../nucleo/mercado/indicadores.dart';

/// `URL_CHART` (mercado.py:63).
const urlChart = 'https://query1.finance.yahoo.com/v8/finance/chart/{t}.SA';

/// `DIAS_HISTORICO` (mercado.py:7).
const diasHistorico = 180;

/// Endereço do chart de [ticker] com os [params] na query.
Uri uriChart(String ticker, Map<String, String> params) {
  final base = Uri.parse(urlChart.replaceAll('{t}', ticker));
  return params.isEmpty ? base : base.replace(queryParameters: params);
}

/// Params dos [diasHistorico] dias até [agora] (`_dados_api`).
Map<String, String> paramsDados(double agora) {
  final fim = agora.truncate();
  return {
    'period1': '${fim - diasHistorico * 86400}',
    'period2': '$fim',
    'interval': '1d',
  };
}

/// Params de `cotacao`.
Map<String, String> paramsCotacao() => {'range': '5d', 'interval': '1d'};

int _meiaNoiteUtc(String iso) =>
    DateTime.parse('${iso}T00:00:00Z').millisecondsSinceEpoch ~/ 1000;

/// Params de `fechamento` para [dia] (`AAAA-MM-DD`).
Map<String, String> paramsFechamento(String dia) => {
  'period1': '${_meiaNoiteUtc(somarDias(dia, -10))}',
  'period2': '${_meiaNoiteUtc(somarDias(dia, 1)) + 86400}',
  'interval': '1d',
};

/// Params de `grafico` para [periodo] (chave de [periodosGrafico]).
Map<String, String> paramsGrafico(String periodo) {
  final (alcance, intervalo, _) = periodosGrafico[periodo]!;
  return {'range': alcance, 'interval': intervalo, 'includePrePost': 'false'};
}

// Visão sem cópia do JSON do Yahoo.
Map<String, Object?> _mapa(Object? o) =>
    o is Map ? o.cast<String, Object?>() : <String, Object?>{};

/// `lista or []`.
List<Object?> _lista(Object? o) => o is List ? o.cast<Object?>() : const [];

/// `((res.get("indicators") or {}).get("quote") or [{}])[0]`.
Map<String, Object?> _quote(Map<String, Object?> resultado) {
  final quotes = _lista(_mapa(resultado['indicators'])['quote']);
  return quotes.isEmpty ? <String, Object?>{} : _mapa(quotes.first);
}

/// `meta.get("gmtoffset") or 0`.
int _desvio(Map<String, Object?> meta) {
  final v = meta['gmtoffset'];
  return v is num && v != 0 ? v.toInt() : 0;
}

/// Preço de `chart.result[0]`: o `regularMarketPrice` da meta quando válido;
/// senão o último fechamento válido. Lança [SemDados].
double cotacaoDeChart(String ticker, Map<String, Object?> resultado) {
  final preco = _mapa(resultado['meta'])['regularMarketPrice'];
  if (valido(preco)) return (preco! as num).toDouble();
  final fechamentos = [
    for (final c in _lista(_quote(resultado)['close']))
      if (valido(c)) (c! as num).toDouble(),
  ];
  if (fechamentos.isEmpty) throw SemDados('Sem cotação para $ticker.');
  return fechamentos.last;
}

/// (fechamento, data real) do último pregão até [dia] (`AAAA-MM-DD`).
/// Lança [SemDados].
(double, String) fechamentoDeChart(
  String ticker,
  Map<String, Object?> resultado,
  String dia,
) {
  final desvio = _desvio(_mapa(resultado['meta']));
  final fechadas = _lista(_quote(resultado)['close']);
  final timestamps = _lista(resultado['timestamp']);
  final n = timestamps.length < fechadas.length
      ? timestamps.length
      : fechadas.length;
  final pares = <(String, double)>[
    for (var i = 0; i < n; i++)
      if (valido(fechadas[i]))
        (
          DataHora.deTimestamp((timestamps[i]! as num) + desvio, 0).data,
          (fechadas[i]! as num).toDouble(),
        ),
  ];
  final validos = [
    for (final p in ordenadoPor(pares, (p) => [p.$1, p.$2]))
      if (compararTexto(p.$1, dia) <= 0) p,
  ];
  if (validos.isEmpty) {
    throw SemDados('Sem fechamento de $ticker até ${fmtData(dia)}.');
  }
  return (validos.last.$2, validos.last.$1);
}

/// Pontos do gráfico de um período (`Mercado.grafico`).
class Grafico {
  Grafico({
    required this.ticker,
    required this.periodo,
    required this.pontos,
    required this.referencia,
    required this.desvio,
    required this.intradiario,
  });

  final String ticker;
  final String periodo;

  /// (timestamp, fechamento).
  final List<(int, double)> pontos;

  /// Fechamento anterior no 1D; primeiro ponto nos demais.
  final double referencia;
  final int desvio;
  final bool intradiario;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'periodo': periodo,
    'pontos': [
      for (final (ts, v) in pontos) [ts, v],
    ],
    'referencia': referencia,
    'desvio': desvio,
    'intradiario': intradiario,
  };
}

/// `x or None` para números: zero conta como falso, como no `or` do Python.
double? _verdadeiro(Object? v) => v is num && v != 0 ? v.toDouble() : null;

/// Gráfico de [periodo] a partir de `chart.result[0]`. Lança [SemDados] com
/// menos de 2 pontos válidos.
Grafico graficoDeChart(
  String ticker,
  String periodo,
  Map<String, Object?> resultado,
) {
  final (_, intervalo, _) = periodosGrafico[periodo]!;
  final meta = _mapa(resultado['meta']);
  final fechadas = _lista(_quote(resultado)['close']);
  final timestamps = _lista(resultado['timestamp']);
  final n = timestamps.length < fechadas.length
      ? timestamps.length
      : fechadas.length;
  final pontos = <(int, double)>[
    for (var i = 0; i < n; i++)
      if (valido(fechadas[i]))
        ((timestamps[i]! as num).toInt(), (fechadas[i]! as num).toDouble()),
  ];
  if (pontos.length < 2) {
    throw SemDados('Sem dados de $periodo para $ticker.');
  }
  final double referencia;
  if (periodo == '1D') {
    referencia =
        _verdadeiro(meta['previousClose']) ??
        _verdadeiro(meta['chartPreviousClose']) ??
        pontos.first.$2;
    final preco = meta['regularMarketPrice'];
    // O último ponto intradiário pode estar alguns minutos atrás da cotação.
    if (valido(preco)) {
      pontos[pontos.length - 1] = (pontos.last.$1, (preco! as num).toDouble());
    }
  } else {
    referencia = pontos.first.$2;
  }
  return Grafico(
    ticker: ticker,
    periodo: periodo,
    pontos: pontos,
    referencia: referencia,
    desvio: _desvio(meta),
    intradiario: intervalo.endsWith('m'),
  );
}
