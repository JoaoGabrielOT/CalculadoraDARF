// Cenário de mercado, meta financeira e consolidado por ativo (entrega 2.1,
// §9). Funções puras: não gravam nada nem simulam com o preço de compra.
//
// Âncora = cotação atual (se for atual) ou último fechamento; alvo e stop são
// arredondados para baixo no tick, ponto de equilíbrio e meta para cima. Sem
// VWAP (o app não tem barras intradiárias com volume confiáveis neste fluxo).
// `sugerir`/`avaliar` (sugestoes.dart) ficam para a paridade com o Python; o
// novo caminho não os usa.

import '../caixa.dart';
import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../constantes.dart';
import '../datas.dart';
import '../erros.dart';
import '../indicadores_ativo.dart';
import '../mercado/indicadores.dart';
import '../modelos/barras.dart';
import '../posicoes.dart';
import '../tick.dart';

/// Período do ATR de Wilder.
const int atrPeriodo = 14;

/// Pregões fechados da máxima usada como resistência e do volume médio.
const int janelaSr = 20;

/// Múltiplo do ATR do stop de referência (e da projeção sem resistência).
const int multStop = 2;

/// Relação risco/retorno mínima para haver oportunidade.
const double rrMinimo = 1.5;

/// Fração do volume financeiro médio acima da qual a saída pode mover o preço.
const double limiteLiquidez = 0.05;

/// Pregões fechados exigidos pelo swing.
const int minPregoesSwing = 21;

/// Idade máxima, em minutos, de uma cotação atual durante o pregão.
const int minutosCotacaoAtual = 20;

/// Pregão regular da B3 (horário de Brasília), em minutos desde 00:00.
const int _aberturaPregao = 10 * 60;
const int _fechamentoPregao = 18 * 60;

/// Pregões fechados do day trade: o ATR(14) precisa de 15 fechamentos.
const int _minPregoesDayTrade = atrPeriodo + 1;

const double _tolerancia = 1e-9;

enum Horizonte { swing, dayTrade }

const textoHorizonte = {
  Horizonte.swing: '5 a 20 pregões',
  Horizonte.dayTrade: 'o pregão de hoje',
};

const _rotuloResistencia = 'resistência de 20 pregões';
const _rotuloProjecao =
    'projeção pela volatilidade (sem resistência recente acima)';
const _rotuloR1 = 'resistência R1 do pregão anterior';
const _semOportunidade = 'Sem oportunidade identificada';
const _motivoRr = 'relação risco/retorno abaixo de 1,5';
const _motivoEquilibrio = 'alvo abaixo do ponto de equilíbrio';
const _motivoDados = 'dados insuficientes';
const _motivoDesatualizado = 'dados desatualizados';
const _motivoSemResistencia = 'sem resistência acima da cotação';
const _motivoIntradiario =
    'Análise intradiária indisponível: sem cotação atual';
const _avisoQuantidade =
    'Quantidade grande frente ao volume médio: a saída pode mover o preço';
const _avisoLiquidez = 'Liquidez indisponível';
const _avisoSpread =
    'Spread: indisponível (o Yahoo não fornece livro de ofertas)';
const _avisoMeta = 'Meta acima do cenário de mercado para o horizonte';
const _avisoCotacaoAntiga =
    'Cotação desatualizada: a análise usa o último fechamento';
const _avisoBarrasAntigas = 'Barras diárias desatualizadas';

/// Texto do resumo quando não há oportunidade.
const textoSemOportunidade = _semOportunidade;

/// Uma cotação com a hora e a fonte, e se ela é atual (não histórica).
class CotacaoInfo {
  CotacaoInfo({
    required this.preco,
    required this.hora,
    required this.fonte,
    required this.atual,
  });

  final double preco;
  final DataHora hora;
  final String fonte;
  final bool atual;
}

int _minutos(DataHora h) {
  final p = h.horaMinuto.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// Dia útil do último pregão já aberto em [agoraBr] (hoje, se o pregão de
/// hoje já abriu).
String _ultimoPregao(DataHora agoraBr) {
  final ag = agoraBr.noFuso(fusoBrasilia);
  var d = ag.data;
  if (diaUtil(d) && _minutos(ag) >= _aberturaPregao) return d;
  do {
    d = somarDias(d, -1);
  } while (!diaUtil(d));
  return d;
}

/// O pregão regular está aberto em [agoraBr] (dia útil, 10:00 a 18:00).
bool pregaoAbertoEm(DataHora agoraBr) {
  final ag = agoraBr.noFuso(fusoBrasilia);
  final m = _minutos(ag);
  return diaUtil(ag.data) && m >= _aberturaPregao && m < _fechamentoPregao;
}

/// Cotação atual: do último pregão e, durante o pregão, com menos de
/// [minutosCotacaoAtual] minutos.
CotacaoInfo cotacaoInfo(
  double preco,
  DataHora hora,
  String fonte,
  DataHora agoraBr,
) {
  final doUltimoPregao =
      hora.noFuso(fusoBrasilia).data == _ultimoPregao(agoraBr);
  final recente =
      !pregaoAbertoEm(agoraBr) ||
      agoraBr.utc.difference(hora.utc) <
          const Duration(minutes: minutosCotacaoAtual);
  return CotacaoInfo(
    preco: preco,
    hora: hora,
    fonte: fonte,
    atual: doUltimoPregao && recente,
  );
}

/// A última barra é anterior ao último pregão fechado esperado antes de [hoje]
/// (`AAAA-MM-DD`). Sem barras, está desatualizada.
bool barrasDesatualizadas(List<BarraDiaria> barras, String hoje) {
  if (barras.isEmpty) return true;
  var esperado = hoje;
  do {
    esperado = somarDias(esperado, -1);
  } while (!diaUtil(esperado));
  var ultima = barras.first.data;
  for (final b in barras) {
    if (b.data.compareTo(ultima) > 0) ultima = b.data;
  }
  return ultima.compareTo(esperado) < 0;
}

/// Resultado de um cenário de mercado. Preços em R$ por ação; [potencial],
/// [risco] e [rr] são por ação e brutos (sem taxas nem imposto): distância da
/// âncora até o alvo e até o stop. O líquido só existe em [consolidar].
class CenarioMercado {
  CenarioMercado({
    required this.horizonte,
    this.ancora,
    this.rotuloAncora,
    this.stop,
    this.alvo,
    this.faixaMin,
    this.faixaMax,
    this.rotuloAlvo,
    this.potencial,
    this.risco,
    this.rr,
    this.oportunidade = false,
    this.motivo,
    this.vfm,
    this.baseData,
    this.avisos = const [],
  });

  final Horizonte horizonte;
  final double? ancora;
  final String? rotuloAncora;
  final double? stop;
  final double? alvo;
  final double? faixaMin;
  final double? faixaMax;
  final String? rotuloAlvo;
  final double? potencial;
  final double? risco;
  final double? rr;
  final bool oportunidade;

  /// Por que não há oportunidade (nulo quando há).
  final String? motivo;

  /// Volume financeiro médio dos últimos [janelaSr] pregões.
  final double? vfm;

  /// Data (`AAAA-MM-DD`) do último pregão fechado usado.
  final String? baseData;
  final List<String> avisos;
}

/// Pregões fechados (anteriores a [hoje]) em ordem crescente.
List<BarraDiaria> _fechadas(List<BarraDiaria> barras, String hoje) {
  return ordenadoPor([
    for (final b in barras)
      if (b.data.compareTo(hoje) < 0) b,
  ], (b) => [b.data]);
}

/// Volume financeiro médio dos últimos [janelaSr] pregões; nulo com menos
/// pregões ou com qualquer barra sem volume.
double? _vfm(List<BarraDiaria> f) {
  if (f.length < janelaSr) return null;
  final ultimas = f.sublist(f.length - janelaSr);
  final partes = <double>[];
  for (final b in ultimas) {
    final v = b.volume;
    if (v == null) return null;
    partes.add(b.fech * v);
  }
  return somaPython(partes) / janelaSr;
}

List<String> _avisos(
  String hoje,
  double? vfm,
  double? ancora,
  int qtd,
  CotacaoInfo? cotacao,
  List<BarraDiaria> todas,
) => [
  if (cotacao != null && !cotacao.atual) _avisoCotacaoAntiga,
  if (barrasDesatualizadas(todas, hoje)) _avisoBarrasAntigas,
  if (vfm == null)
    _avisoLiquidez
  else if (ancora != null && qtd * ancora > limiteLiquidez * vfm)
    _avisoQuantidade,
  _avisoSpread,
];

double _atr(List<BarraDiaria> f) =>
    calcularAtr([for (final b in f) b.alta], [for (final b in f) b.baixa], [
      for (final b in f) b.fech,
    ], atrPeriodo) ??
    0.0;

CenarioMercado _decidir({
  required Horizonte horizonte,
  required double ancora,
  required String rotuloAncora,
  required double stop,
  required double alvo,
  double? faixaMin,
  double? faixaMax,
  required String rotuloAlvo,
  double? pontoEquilibrio,
  double? meta,
  double? vfm,
  required String baseData,
  required List<String> avisos,
}) {
  final potencial = alvo - ancora;
  final risco = ancora - stop;
  final rr = risco > 0 ? potencial / risco : null;
  String? motivo;
  if (rr == null || rr + _tolerancia < rrMinimo) {
    motivo = _motivoRr;
  } else if (pontoEquilibrio != null && alvo <= pontoEquilibrio) {
    motivo = _motivoEquilibrio;
  }
  return CenarioMercado(
    horizonte: horizonte,
    ancora: ancora,
    rotuloAncora: rotuloAncora,
    stop: stop,
    alvo: alvo,
    faixaMin: faixaMin,
    faixaMax: faixaMax,
    rotuloAlvo: rotuloAlvo,
    potencial: potencial,
    risco: risco,
    rr: rr,
    oportunidade: motivo == null,
    motivo: motivo,
    vfm: vfm,
    baseData: baseData,
    avisos: [if (meta != null && meta > alvo) _avisoMeta, ...avisos],
  );
}

/// Cenário de swing (horizonte de 5 a 20 pregões). Sem [cotacao] atual a
/// âncora é o último fechamento. [meta] só gera aviso; não muda a decisão.
CenarioMercado cenarioSwing({
  required String ticker,
  required List<BarraDiaria> barras,
  required String hoje,
  CotacaoInfo? cotacao,
  double? pontoEquilibrio,
  required int qtd,
  double? meta,
}) {
  final f = _fechadas(barras, hoje);
  final atual = cotacao != null && cotacao.atual;
  final double? ancora = atual
      ? cotacao.preco
      : (f.isEmpty ? null : f.last.fech);
  final rotuloAncora = atual ? 'cotação atual' : 'último fechamento';
  final vfm = _vfm(f);
  final avisos = _avisos(hoje, vfm, ancora, qtd, cotacao, barras);

  CenarioMercado semDados() => CenarioMercado(
    horizonte: Horizonte.swing,
    ancora: ancora,
    rotuloAncora: ancora == null ? null : rotuloAncora,
    motivo: _motivoDados,
    vfm: vfm,
    baseData: f.isEmpty ? null : f.last.data,
    avisos: avisos,
  );

  if (f.length < minPregoesSwing || ancora == null) return semDados();
  final atr = _atr(f);
  if (atr <= 0) return semDados();

  final tick = tickDe(ticker, ancora);
  var stopBruto = ancora - multStop * atr;
  final chandelier = calcularChandelier(f);
  // Chandelier na ou acima da âncora não protege nada: fica só P − 2·ATR.
  if (chandelier != null && chandelier < ancora) {
    stopBruto = maxPython(stopBruto, chandelier);
  }
  final stop = pisoTick(ticker, stopBruto);
  if (stop < tick || stop >= ancora) return semDados();

  final resistencia = maxDe(f.sublist(f.length - janelaSr).map((b) => b.alta));
  final double alvo;
  final double faixaMin;
  final String rotuloAlvo;
  if (resistencia >= ancora + tick - _tolerancia) {
    alvo = pisoTick(ticker, resistencia);
    faixaMin = pisoTick(
      ticker,
      maxPython(ancora + tick, resistencia - 0.5 * atr),
    );
    rotuloAlvo = _rotuloResistencia;
  } else {
    alvo = pisoTick(ticker, ancora + multStop * atr);
    faixaMin = alvo;
    rotuloAlvo = _rotuloProjecao;
  }
  return _decidir(
    horizonte: Horizonte.swing,
    ancora: ancora,
    rotuloAncora: rotuloAncora,
    stop: stop,
    alvo: alvo,
    faixaMin: faixaMin,
    faixaMax: alvo,
    rotuloAlvo: rotuloAlvo,
    pontoEquilibrio: pontoEquilibrio,
    meta: meta,
    vfm: vfm,
    baseData: f.last.data,
    avisos: avisos,
  );
}

/// Cenário de day trade (o pregão de hoje) pelos pivôs do pregão anterior.
/// Sem cotação atual (ou com o pregão fechado) não há análise: nunca simula
/// com o preço de compra.
CenarioMercado cenarioDayTrade({
  required String ticker,
  required List<BarraDiaria> barras,
  required String hoje,
  CotacaoInfo? cotacao,
  required bool pregaoAberto,
  double? pontoEquilibrio,
  required int qtd,
  double? meta,
}) {
  final f = _fechadas(barras, hoje);
  final vfm = _vfm(f);
  final baseData = f.isEmpty ? null : f.last.data;
  if (cotacao == null || !cotacao.atual || !pregaoAberto) {
    return CenarioMercado(
      horizonte: Horizonte.dayTrade,
      motivo: _motivoIntradiario,
      vfm: vfm,
      baseData: baseData,
      avisos: _avisos(hoje, vfm, null, qtd, cotacao, barras),
    );
  }
  final ancora = cotacao.preco;
  final avisos = _avisos(hoje, vfm, ancora, qtd, cotacao, barras);
  CenarioMercado semDados([String motivo = _motivoDados]) => CenarioMercado(
    horizonte: Horizonte.dayTrade,
    ancora: ancora,
    rotuloAncora: 'cotação atual',
    motivo: motivo,
    vfm: vfm,
    baseData: baseData,
    avisos: avisos,
  );

  if (f.length < _minPregoesDayTrade) return semDados();
  final atr = _atr(f);
  if (atr <= 0) return semDados();
  final ontem = f.last;
  // Os pivôs precisam do último pregão fechado esperado.
  if (barrasDesatualizadas(f, hoje)) return semDados(_motivoDesatualizado);
  final p = calcularPivos(ontem.alta, ontem.baixa, ontem.fech);
  final candidato = maxPython(p.s1, ancora - atr);
  final stop = pisoTick(ticker, candidato < ancora ? candidato : ancora - atr);
  if (stop < tickDe(ticker, ancora) || stop >= ancora) return semDados();
  final alvo = p.r1 > ancora ? pisoTick(ticker, p.r1) : null;
  if (alvo == null || alvo <= ancora) return semDados(_motivoSemResistencia);
  return _decidir(
    horizonte: Horizonte.dayTrade,
    ancora: ancora,
    rotuloAncora: 'cotação atual',
    stop: stop,
    alvo: alvo,
    rotuloAlvo: _rotuloR1,
    pontoEquilibrio: pontoEquilibrio,
    meta: meta,
    vfm: vfm,
    baseData: ontem.data,
    avisos: avisos,
  );
}

/// Meta financeira: preço de venda, no tick para cima, para sobrar
/// [lucroDesejado] líquido de IR (como a Calculadora de metas): ganho bruto
/// G = L/(1 − alíquota) (só com L > 0), custo `Q·PM·(1+t)` e corretagem de
/// compra e venda. É simulação: nunca vira recomendação.
double metaFinanceira(
  String ticker,
  int qtd,
  double precoMedio,
  double lucroDesejado, {
  bool dayTrade = false,
}) {
  if (qtd <= 0) throw ErroValidacao('Quantidade inválida.');
  if (!lucroDesejado.isFinite) throw ErroValidacao('Lucro desejado inválido.');
  final t = dayTrade ? taxaB3Daytrade : taxaB3Swing;
  final aliq = dayTrade ? aliqDaytrade : aliqSwing;
  final bruto = lucroDesejado > 0 ? lucroDesejado / (1 - aliq) : lucroDesejado;
  final corretagem = corretagemPorOrdem * (1 + qtd / qtd);
  final exato =
      (bruto + qtd * precoMedio * (1 + t) + corretagem) / (qtd * (1 - t));
  if (!exato.isFinite) {
    throw ErroValidacao('Valores grandes demais para calcular.');
  }
  if (exato <= 0) {
    throw ErroValidacao(
      'Com esse resultado o preço de venda seria zero ou negativo.',
    );
  }
  return maxPython(tetoTick(ticker, exato), tickDe(ticker, exato));
}

/// Saída simulada de [qtd] ações a [preco].
class CenarioSaida {
  const CenarioSaida({
    required this.rotulo,
    required this.qtd,
    required this.preco,
    required this.resultado,
    required this.resultadoPct,
  });

  final String rotulo;
  final int qtd;
  final double preco;

  /// Líquido de taxas B3 e do IR estimado, em R$.
  final double resultado;

  /// `resultado / compra × 100`, com `compra` o custo baixado das [qtd]
  /// ações; nulo sem custo.
  final double? resultadoPct;
}

class ConsolidadoAtivo {
  ConsolidadoAtivo({
    required this.ticker,
    required this.qtd,
    required this.custo,
    required this.precoMedio,
    required this.pontoEquilibrio,
    required this.cenarios,
  });

  final String ticker;
  final int qtd;
  final double custo;
  final double? precoMedio;
  final double? pontoEquilibrio;
  final List<CenarioSaida> cenarios;
}

CenarioSaida _saida(
  String rotulo,
  int q,
  double preco,
  PosicaoAtivo p,
  double custo,
  bool dayTrade,
) {
  final taxa = dayTrade ? taxaB3Daytrade : taxaB3Swing;
  final aliq = dayTrade ? aliqDaytrade : aliqSwing;
  final compra = arredondar(q * custo / p.qtd, 2);
  final venda = q * preco;
  final taxas = (compra + venda) * taxa;
  final corretagem = corretagemPorOrdem * (1 + q / p.qtd);
  final liquido = venda - compra - taxas - corretagem;
  final imposto = maxPython(liquido, 0.0) * aliq;
  final resultado = liquido - imposto;
  return CenarioSaida(
    rotulo: rotulo,
    qtd: q,
    preco: preco,
    resultado: resultado,
    resultadoPct: compra > 0 ? resultado / compra * 100 : null,
  );
}

/// Consolida a posição: saída de 25%, 50%, 100% e [qtdDigitada] nos preços
/// do alvo, do stop e da [meta]. O regime (taxas e IR) segue o horizonte do
/// cenário.
ConsolidadoAtivo consolidar(
  PosicaoAtivo p,
  CenarioMercado c, {
  double? meta,
  int? qtdDigitada,
}) {
  final custo = p.custoFiscal ?? p.custoGerencial;
  final dayTrade = c.horizonte == Horizonte.dayTrade;
  final quantidades = <(String, int)>[];
  if (p.qtd > 0) {
    final fracoes = [(25, 0.25), (50, 0.5), (100, 1.0)];
    for (final (i, (pct, f)) in fracoes.indexed) {
      final q = f == 1.0 ? p.qtd : maxPython(1, (p.qtd * f).floor()).toInt();
      final repetida = fracoes
          .skip(i + 1)
          .any((o) => (o.$2 == 1.0 ? p.qtd : (p.qtd * o.$2).floor()) == q);
      if (!repetida) quantidades.add(('$pct%', q));
    }
    if (qtdDigitada != null &&
        qtdDigitada > 0 &&
        qtdDigitada <= p.qtd &&
        !quantidades.any((e) => e.$2 == qtdDigitada)) {
      quantidades.add(('Qtd. digitada ($qtdDigitada)', qtdDigitada));
    }
  }
  final precos = <(String, double)>[
    if (c.alvo != null) ('no alvo', c.alvo!),
    if (c.stop != null) ('no stop', c.stop!),
    if (meta != null) ('na meta', meta),
  ];
  return ConsolidadoAtivo(
    ticker: p.ticker,
    qtd: p.qtd,
    custo: custo,
    precoMedio: p.precoMedio,
    pontoEquilibrio: p.qtd == 0
        ? null
        : pontoEquilibrio(p.ticker, p.qtd, custo),
    cenarios: [
      for (final (nome, preco) in precos)
        for (final (rotulo, q) in quantidades)
          _saida('$rotulo $nome', q, preco, p, custo, dayTrade),
    ],
  );
}
