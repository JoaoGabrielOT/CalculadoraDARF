// Serviço do Yahoo: HTTP real do chart, caches e as buscas do núcleo
// (`_get_chart` e `Mercado`, só o caminho da API; mercado.py:105-116, 233-466).

import 'package:http/http.dart' as http;

import '../../nucleo/ambiente.dart';
import '../../nucleo/datas.dart';
import '../../nucleo/erros.dart';
import '../../nucleo/mercado/chart.dart';
import '../../nucleo/mercado/dados_ativo.dart';
import '../../nucleo/mercado/indicadores.dart';
import '../../nucleo/modelos/barras.dart';
import '../executor.dart';
import '../http/cliente.dart';
import '../http/erros.dart';
import '../http/json.dart';
import 'interpretacao.dart';

/// Validade do cache de `dados`, em segundos (`agora - hora > 60` refaz).
const _validadeDados = 60;

class ServicoYahoo {
  ServicoYahoo(
    this._http, {
    CacheDiarias? cacheDiarias,
    Executar executar = executarEmIsolate,
  }) : _cacheDiarias = cacheDiarias ?? CacheDiarias(),
       // ignore: prefer_initializing_formals -- parâmetro nomeado não pode ser privado
       _executar = executar;

  /// Cliente do Python: UA `Mozilla/5.0`, 20 s, no máximo 3 pedidos abertos e
  /// 2 repetições após 429.
  static ClienteHttp clientePadrao(http.Client c) => ClienteHttp(
    c,
    userAgent: 'Mozilla/5.0',
    tempoLimite: const Duration(seconds: 20),
    maxSimultaneas: 3,
    repeticoes429: 2,
  );

  final ClienteHttp _http;
  final CacheDiarias _cacheDiarias;
  final Executar _executar;
  final _dados = <String, (double, Map<String, Object?>)>{};
  final _graficos = <(String, String), (double, Grafico)>{};

  /// `chart.result[0]` do pedido; 404 ou resultado vazio lançam [SemDados]
  /// com [semDados]; 429 e demais erros HTTP vêm de [conferirStatus].
  Future<Map<String, Object?>> _chart(
    String ticker,
    Map<String, String> params,
    String semDados,
  ) async {
    final url = uriChart(ticker, params);
    final r = await _http.enviar('GET', url);
    if (r.statusCode == 404) throw SemDados(semDados);
    conferirStatus(r.statusCode, url, motivo: r.reasonPhrase);
    final Object? corpo;
    try {
      corpo = await decodificarJson(r.bodyBytes, _executar);
    } on FormatException {
      throw SemDados(semDados);
    }
    final chart = corpo is Map ? corpo['chart'] : null;
    final lista = chart is Map ? chart['result'] : null;
    if (lista is! List || lista.isEmpty || lista.first is! Map) {
      throw SemDados(semDados);
    }
    return (lista.first as Map).cast<String, Object?>();
  }

  /// `_get_chart`; compatível com [ObterChart].
  Future<Map<String, Object?>> obterChart(
    String ticker,
    Map<String, String> params,
  ) => _chart(ticker, params, 'Sem dados para $ticker no Yahoo Finance.');

  /// Cotação e indicadores (`_dados_api`); o chart de 180 dias fica 60 s por
  /// ticker.
  Future<DadosAtivo> dados(String ticker, {String nomeConhecido = ''}) async {
    final agora = ambiente.agora();
    final guardado = _dados[ticker];
    if (guardado != null && !(agora - guardado.$1 > _validadeDados)) {
      return dadosAtivoDeChart(
        ticker,
        guardado.$2,
        nomeConhecido: nomeConhecido,
        hora: ambiente.agora(),
      );
    }
    final res = await obterChart(ticker, paramsDados(agora));
    final d = dadosAtivoDeChart(
      ticker,
      res,
      nomeConhecido: nomeConhecido,
      hora: ambiente.agora(),
    );
    _dados[ticker] = (agora, res);
    return d;
  }

  void limpar() => _dados.clear();

  Future<double> cotacao(String ticker) async => cotacaoDeChart(
    ticker,
    await _chart(ticker, paramsCotacao(), 'Sem cotação para $ticker.'),
  );

  /// (fechamento, data real) do último pregão até [dia] (`AAAA-MM-DD`).
  Future<(double, String)> fechamento(String ticker, String dia) async =>
      fechamentoDeChart(
        ticker,
        await _chart(
          ticker,
          paramsFechamento(dia),
          'Sem cotação para $ticker.',
        ),
        dia,
      );

  /// Cotação atual quando [dia] é hoje ou futuro; senão o fechamento do dia.
  Future<(double, String)> precoVenda(String ticker, String dia) async {
    if (dia.compareTo(ambiente.hoje()) >= 0) {
      return (await cotacao(ticker), 'Cotação atual');
    }
    final (preco, dataReal) = await fechamento(ticker, dia);
    return (preco, 'Fechamento de ${fmtData(dataReal)}');
  }

  /// Gráfico do [periodo], com cache pela validade de [periodosGrafico].
  Future<Grafico> grafico(String ticker, String periodo) async {
    final validade = periodosGrafico[periodo]!.$3;
    final chave = (ticker, periodo);
    final agora = ambiente.agora();
    final c = _graficos[chave];
    if (c != null && agora - c.$1 < validade) return c.$2;
    final res = await obterChart(ticker, paramsGrafico(periodo));
    final g = graficoDeChart(ticker, periodo, res);
    _graficos[chave] = (agora, g);
    return g;
  }

  /// É um `BuscarHistorico`.
  Future<HistoricoIntradiario> historico(String ticker, DataHora desde) =>
      historicoDesde(ticker, desde, obterChart: obterChart);

  /// É um `BuscarDiarias`.
  Future<Diarias> diarias(String ticker, String desde) =>
      barrasDiarias(ticker, desde: desde);

  /// Barras diárias; sem [desde], as dos 6 meses (sugestões).
  Future<Diarias> barrasDiarias(String ticker, {String? desde}) =>
      _cacheDiarias.barrasDiarias(ticker, desde: desde, obterChart: obterChart);
}
