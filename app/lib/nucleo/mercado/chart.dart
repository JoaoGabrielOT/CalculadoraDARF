// Interpretação do chart do Yahoo, sem rede (mercado.py:119-231, 336-375). A
// busca HTTP é injetada como [ObterChart].

import '../ambiente.dart';
import '../compat/numeros.dart';
import '../datas.dart';
import '../erros.dart';
import '../modelos/barras.dart';
import 'dados_ativo.dart';
import 'indicadores.dart';

/// `_get_chart`: devolve `chart.result[0]`. A implementação HTTP lança
/// [SemDados] no 404 ou resultado vazio e [LimiteConsultas] no 429.
typedef ObterChart = Future<Map<String, Object?>> Function(
  String ticker,
  Map<String, String> params,
);

/// `PERIODOS_ATR` (mercado.py:8).
const _periodosAtr = 14;

// Visão sem cópia (o `lerMapa` de modelos/com_mod.dart faz cópia profunda; aqui
// só se lê o JSON do Yahoo, que pode ser grande).
Map<String, Object?> _mapa(Object? o) =>
    o is Map ? o.cast<String, Object?>() : <String, Object?>{};

/// `lista or []`.
List<Object?> _lista(Object? o) => o is List ? o.cast<Object?>() : const [];

/// `meta.get(chave) or padrao` para números.
int _inteiroOu(Object? v, int padrao) =>
    v is num && v != 0 ? v.toInt() : padrao;

/// `((res.get("indicators") or {}).get("quote") or [{}])[0]`.
Map<String, Object?> _quote(Map<String, Object?> resultado) {
  final quotes = _lista(_mapa(resultado['indicators'])['quote']);
  return quotes.isEmpty ? <String, Object?>{} : _mapa(quotes.first);
}

/// `float(lista[i]) if i < len(lista) and _valido(lista[i]) else None`.
double? _campo(List<Object?> lista, int i) =>
    i < lista.length && valido(lista[i]) ? (lista[i]! as num).toDouble() : null;

/// Intervalos do Yahoo a tentar, do mais fino ao mais grosso, conforme a idade
/// do período pedido.
List<String> intervalosHistorico(double dias) {
  if (dias <= 7) return ['1m', '5m', '15m', '1h', '1d'];
  if (dias <= 60) return ['5m', '15m', '1h', '1d'];
  if (dias <= 700) return ['1h', '1d'];
  return ['1d'];
}

/// Máximas, mínimas e aberturas das barras do Yahoo desde [desde], no
/// intervalo mais fino disponível. Lança [SemDados] se não houver nenhuma
/// barra. [agora] vale `ambiente.agora()` quando omitido.
Future<HistoricoIntradiario> historicoDesde(
  String ticker,
  DataHora desde, {
  DataHora? agora,
  required ObterChart obterChart,
}) async {
  final fim = agora ?? DataHora.deTimestamp(ambiente.agora(), 0);
  final dias = fim.utc.difference(desde.utc).inMicroseconds / 1e6 / 86400;
  SemDados? ultimo;
  for (final intervalo in intervalosHistorico(dias > 0 ? dias : 0.0)) {
    final inicio =
        desde.timestamp.truncate() -
        (intervalo == '1h' || intervalo == '1d' ? 86400 : 0);
    final Map<String, Object?> res;
    try {
      res = await obterChart(ticker, {
        'period1': '$inicio',
        'period2': '${fim.timestamp.truncate() + 60}',
        'interval': intervalo,
        'includePrePost': 'false',
      });
    } on SemDados catch (e) {
      ultimo = e;
      continue;
    }
    final desvio = _inteiroOu(_mapa(res['meta'])['gmtoffset'], fusoBrasilia);
    final q = _quote(res);
    final baixas = _lista(q['low']);
    final aberturas = _lista(q['open']);
    final timestamps = _lista(res['timestamp']);
    final altas = _lista(q['high']);
    final n = timestamps.length < altas.length
        ? timestamps.length
        : altas.length;
    final barras = [
      for (var i = 0; i < n; i++)
        if (valido(altas[i]))
          Barra(
            ts: (timestamps[i]! as num).toInt(),
            dt: DataHora.deTimestamp(timestamps[i]! as num, desvio),
            alta: (altas[i]! as num).toDouble(),
            baixa: _campo(baixas, i),
            abre: _campo(aberturas, i),
          ),
    ];
    if (barras.isNotEmpty) {
      return HistoricoIntradiario(
        barras: barras,
        fonte: 'Yahoo Finance',
        intervalo: intervalo,
      );
    }
  }
  throw ultimo ??
      SemDados(
        'Sem histórico de $ticker desde ${fmtData(desde.data)} '
        '${desde.horaMinuto}.',
      );
}

/// Menor range do Yahoo que cobre [desde] (`AAAA-MM-DD`) com 60 dias de folga
/// (para o ATR e o Chandelier). [hoje] vale `ambiente.hoje()` quando omitido.
String rangeDiarias(String? desde, {String? hoje}) {
  if (desde == null) return '6mo';
  final dias = diasEntre(desde, hoje ?? ambiente.hoje()) + 60;
  for (final (limite, alcance) in const [
    (180, '6mo'),
    (365, '1y'),
    (730, '2y'),
  ]) {
    if (dias <= limite) return alcance;
  }
  return '5y';
}

/// Barras diárias do Yahoo com cache de 15 minutos por (ticker, range); o
/// relógio é `ambiente.agora()`.
class CacheDiarias {
  static const validadeSegundos = 900;

  final _cache = <(String, String), (double, Diarias)>{};

  /// Barras diárias (ordem crescente); [desde] (`AAAA-MM-DD`) amplia o período
  /// para cobrir a data. Lança [SemDados].
  Future<Diarias> barrasDiarias(
    String ticker, {
    String? desde,
    required ObterChart obterChart,
  }) async {
    final alcance = rangeDiarias(desde);
    final chave = (ticker, alcance);
    final agora = ambiente.agora();
    final c = _cache[chave];
    if (c != null && agora - c.$1 < validadeSegundos) return c.$2;
    final res = await obterChart(ticker, {
      'range': alcance,
      'interval': '1d',
      'includePrePost': 'false',
    });
    final meta = _mapa(res['meta']);
    final desvio = _inteiroOu(meta['gmtoffset'], 0);
    final q = _quote(res);
    final abertas = _lista(q['open']);
    final altas = _lista(q['high']);
    final baixas = _lista(q['low']);
    final fechadas = _lista(q['close']);
    final volumes = _lista(q['volume']);
    final barras = <BarraDiaria>[];
    for (final (i, ts) in _lista(res['timestamp']).indexed) {
      final alta = _campo(altas, i);
      final baixa = _campo(baixas, i);
      final fech = _campo(fechadas, i);
      if (alta == null || baixa == null || fech == null) continue;
      barras.add(
        BarraDiaria(
          data: DataHora.deTimestamp((ts! as num) + desvio, 0).data,
          abre: _campo(abertas, i),
          alta: alta,
          baixa: baixa,
          fech: fech,
          volume: _campo(volumes, i),
        ),
      );
    }
    if (barras.isEmpty) {
      throw SemDados('Sem dados para $ticker no Yahoo Finance.');
    }
    final tMercado = meta['regularMarketTime'];
    final hoje = tMercado is num && tMercado != 0
        ? DataHora.deTimestamp(tMercado + desvio, 0).data
        : barras.last.data;
    final preco = meta['regularMarketPrice'];
    final out = Diarias(
      barras: barras,
      hoje: hoje,
      preco: valido(preco) ? (preco! as num).toDouble() : barras.last.fech,
      fonte: 'Yahoo Finance',
    );
    _cache[chave] = (agora, out);
    return out;
  }

  void limpar() => _cache.clear();
}

/// Cotação e indicadores de um ativo a partir do `chart.result[0]` de 180 dias
/// (`Mercado._dados_api`, mercado.py:336-375). [hora] vale `ambiente.agora()`
/// quando omitida. Lança [SemDados] com menos de 15 linhas válidas.
DadosAtivo dadosAtivoDeChart(
  String ticker,
  Map<String, Object?> resultado, {
  String nomeConhecido = '',
  double? hora,
}) {
  final meta = _mapa(resultado['meta']);
  final desvio = _inteiroOu(meta['gmtoffset'], 0);
  final q = _quote(resultado);
  final timestamps = _lista(resultado['timestamp']);
  final altas = _lista(q['high']);
  final baixas = _lista(q['low']);
  final fechadas = _lista(q['close']);
  var n = timestamps.length;
  for (final l in [altas, baixas, fechadas]) {
    if (l.length < n) n = l.length;
  }
  final datas = <String>[];
  // Valores crus (`int` ou `double`): o `sum()` do Python soma `int` sem
  // compensação.
  final hi = <num>[];
  final lo = <num>[];
  final cl = <num>[];
  for (var i = 0; i < n; i++) {
    if (valido(altas[i]) && valido(baixas[i]) && valido(fechadas[i])) {
      datas.add(DataHora.deTimestamp((timestamps[i]! as num) + desvio, 0).data);
      hi.add(altas[i]! as num);
      lo.add(baixas[i]! as num);
      cl.add(fechadas[i]! as num);
    }
  }
  if (cl.length < _periodosAtr + 1) {
    throw SemDados('Histórico insuficiente para $ticker.');
  }
  final tMercado = meta['regularMarketTime'];
  final dia = tMercado is num && tMercado != 0
      ? DataHora.deTimestamp(tMercado + desvio, 0).data
      : datas.last;
  final media = somaPythonNum(cl) / cl.length;
  final atr = calcularAtr(hi, lo, cl);
  final precoMeta = meta['regularMarketPrice'];
  final preco = valido(precoMeta)
      ? (precoMeta! as num).toDouble()
      : cl.last.toDouble();
  final longo = meta['longName'];
  final curto = meta['shortName'];
  final nomeMeta = longo is String && longo.isNotEmpty
      ? longo
      : (curto is String && curto.isNotEmpty ? curto : '');
  final anterior = anteriorDe([
    for (var i = 0; i < cl.length; i++) (datas[i], cl[i].toDouble()),
  ], dia);
  final atrPct = atr != null && atr != 0 ? atr / preco * 100 : null;
  final delta = variacao(preco, anterior);

  double? extra(String chave) =>
      valido(meta[chave]) ? (meta[chave]! as num).toDouble() : null;

  return DadosAtivo(
    ticker: ticker,
    nome: nomeConhecido.isNotEmpty ? nomeConhecido : nomeMeta,
    preco: preco,
    media6m: media,
    atr: atr,
    atrPct: atrPct,
    risco: atrPct == null ? null : classificarRisco(atrPct),
    hora: hora ?? ambiente.agora(),
    anterior: anterior,
    variacao: delta.$1,
    variacaoPct: delta.$2,
    min6m: minDe(lo.map((v) => v.toDouble())),
    max6m: maxDe(hi.map((v) => v.toDouble())),
    variacao6mPct: valido(preco) && valido(cl[0])
        ? (preco / cl[0].toDouble() - 1) * 100
        : null,
    vsMediaPct: valido(preco) && valido(media)
        ? (preco / media - 1) * 100
        : null,
    maxDia: extra('regularMarketDayHigh'),
    minDia: extra('regularMarketDayLow'),
    max52: extra('fiftyTwoWeekHigh'),
    min52: extra('fiftyTwoWeekLow'),
    volume: extra('regularMarketVolume'),
  );
}
