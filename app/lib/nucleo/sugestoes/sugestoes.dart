// Sugestão de alvo e stop por volatilidade (ATR), para as metas de venda
// automática (sugestoes.py:20-166).
//
// Barras: só de pregões fechados e em ordem (`sugerir` descarta a barra de
// hoje, que ainda está parcial).
//
// Swing:     stop inicial = compra − 2·ATR(14); stop móvel (Chandelier) =
//            máxima de 22 pregões − 3·ATR(22); stop sugerido = o maior dos
//            dois (arredondado para baixo no centavo); alvo = compra +
//            2·(compra − stop inicial) (risco/retorno 1:2, para cima).
// Day trade: stop = o maior entre o suporte S1 do pregão anterior e compra −
//            ATR(14), desde que abaixo da compra; alvo = resistência R1 se
//            ela der pelo menos o mesmo ganho que o risco, senão compra +
//            2·risco.

import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../erros.dart';
import '../metas/preco_alvo.dart';
import '../mercado/indicadores.dart';
import '../modelos/barras.dart';
import '../modelos/lote.dart';

const minBarras = 15; // ATR(14) precisa de 15 fechamentos
const multStopSwing = 2;
const multChandelier = 3;
const periodoChandelier = 22;
const rr = 2;
const multStopDt = 1;
const limiteRisco = 0.02; // perda máxima de uma operação: 2% do patrimônio
const limiteMes = 0.06; // perda máxima no mês: 6% do patrimônio
const avisoSugestao =
    'Sugestão baseada na volatilidade (ATR); não é recomendação de '
    'investimento e não há garantia de resultado.';
const avisoProventos =
    'Os preços do Yahoo não são ajustados por proventos: na data-ex de um '
    'dividendo o preço cai e pode disparar o stop.';
const avisoGap =
    'Em gap de baixa o app registra a abertura como pior preço plausível; na '
    'corretora um stop limitado pode nem executar.';

/// Sugestão de stop e alvo; os campos de pivô só existem no day trade e os
/// de stop inicial e Chandelier só no swing.
class Sugestao {
  Sugestao({
    required this.modo,
    required this.atr14,
    this.atr22,
    this.stopInicial,
    this.chandelier,
    this.pp,
    this.r1,
    this.s1,
    required this.stop,
    required this.alvo,
    required this.movelDisponivel,
    required this.baseData,
  });

  /// `"swing"` ou `"day_trade"`.
  final String modo;
  final double atr14;
  final double? atr22;
  final double? stopInicial;
  final double? chandelier;
  final double? pp;
  final double? r1;
  final double? s1;
  final double stop;
  final double alvo;
  final bool movelDisponivel;

  /// Data (`AAAA-MM-DD`) do último pregão usado.
  final String baseData;

  /// Preenchidos por [sugerir].
  double? precoAtual;
  bool stopValido = true;
  bool alvoImediato = false;
  List<String> avisos = [];
}

/// `math.floor` do Python lança com NaN e infinito; o `pisoCentavo` do Dart
/// devolveria o valor em silêncio.
double _finito(double v) {
  if (v.isNaN) {
    throw ErroValidacao('cannot convert float NaN to integer');
  }
  if (v.isInfinite) {
    throw ErroValidacao('cannot convert float infinity to integer');
  }
  return v;
}

double _piso(double v) => pisoCentavo(_finito(v));

double _teto(double v) => tetoCentavo(_finito(v));

/// Stop e alvo de swing trade a partir de pregões fechados. Lança
/// [SemSugestao] sem dados ou sem volatilidade.
Sugestao sugestaoSwing(double compra, List<BarraDiaria> barras) {
  final altas = [for (final b in barras) b.alta];
  final baixas = [for (final b in barras) b.baixa];
  final fechs = [for (final b in barras) b.fech];
  final atr14 = calcularAtr(altas, baixas, fechs, 14);
  if (atr14 == null) {
    throw SemSugestao(
      'Histórico insuficiente: faltam pregões para calcular o ATR.',
    );
  }
  final stopInicial = compra - multStopSwing * atr14;
  if (atr14 <= 0 || compra - stopInicial <= 0) {
    throw SemSugestao('Volatilidade zero, sem sugestão.');
  }
  final atr22 = calcularAtr(altas, baixas, fechs, periodoChandelier);
  final chandelier = calcularChandelier(
    barras,
    n: periodoChandelier,
    mult: multChandelier,
  );
  final stop = _piso(
    chandelier != null ? maxPython(stopInicial, chandelier) : stopInicial,
  );
  if (stop < 0.01) {
    throw SemSugestao(
      'Volatilidade alta demais para o preço da compra: o stop ficaria '
      'abaixo de R\$ 0,01.',
    );
  }
  final alvo = _teto(compra + rr * (compra - stopInicial));
  return Sugestao(
    modo: 'swing',
    atr14: atr14,
    atr22: atr22,
    stopInicial: stopInicial,
    chandelier: chandelier,
    stop: stop,
    alvo: alvo,
    movelDisponivel: chandelier != null,
    baseData: barras.last.data,
  );
}

/// Stop e alvo de day trade com os pivôs do pregão anterior e o ATR(14).
Sugestao sugestaoDayTrade(
  double compra,
  BarraDiaria diaAnterior,
  double? atr14,
) {
  if (atr14 == null || atr14 == 0 || atr14 <= 0) {
    throw SemSugestao('Volatilidade zero, sem sugestão.');
  }
  final p = calcularPivos(
    diaAnterior.alta,
    diaAnterior.baixa,
    diaAnterior.fech,
  );
  final candidato = maxPython(p.s1, compra - multStopDt * atr14);
  var stop = candidato < compra ? candidato : compra - multStopDt * atr14;
  final risco = compra - stop;
  if (risco <= 0) {
    throw SemSugestao('Volatilidade zero, sem sugestão.');
  }
  stop = _piso(stop);
  if (stop < 0.01) {
    throw SemSugestao(
      'Volatilidade alta demais para o preço da compra: o stop ficaria '
      'abaixo de R\$ 0,01.',
    );
  }
  final alvo = p.r1 > compra && (p.r1 - compra) >= risco
      ? p.r1
      : compra + rr * risco;
  return Sugestao(
    modo: 'day_trade',
    atr14: atr14,
    pp: p.pp,
    r1: p.r1,
    s1: p.s1,
    stop: stop,
    alvo: _teto(alvo),
    movelDisponivel: false,
    baseData: diaAnterior.data,
  );
}

/// `bool(x)` de um número do Python (nulo e zero são falsos).
bool _verdadeiro(double? v) => v != null && v != 0;

/// Sugestão para uma compra aberta. Usa só os pregões anteriores a [hoje]
/// (`AAAA-MM-DD`). É day trade quando a compra foi feita hoje. Lança
/// [SemSugestao] (a mensagem explica o motivo). Devolve a sugestão com
/// `precoAtual`, `stopValido` (o stop está abaixo da cotação), `alvoImediato`
/// (o alvo já está na cotação ou abaixo) e `avisos` (textos).
Sugestao sugerir(
  Lote lote,
  List<BarraDiaria> barras,
  String hoje,
  double? precoAtual,
) {
  final fechadas = ordenadoPor(
    barras.where((b) => b.data.compareTo(hoje) < 0),
    (b) {
      return [b.data];
    },
  );
  if (fechadas.length < minBarras) {
    throw SemSugestao(
      'Histórico insuficiente: ${fechadas.length} pregões fechados '
      '(mínimo $minBarras).',
    );
  }
  final compra = lote.preco;
  if (_verdadeiro(precoAtual) &&
      (compra > 3 * precoAtual! || compra < precoAtual / 3)) {
    throw SemSugestao(
      'O preço da compra está muito longe da cotação (possível desdobramento '
      'ou grupamento): sem sugestão.',
    );
  }
  final Sugestao sug;
  if (lote.dataCompra == hoje) {
    final altas = [for (final b in fechadas) b.alta];
    final baixas = [for (final b in fechadas) b.baixa];
    final fechs = [for (final b in fechadas) b.fech];
    sug = sugestaoDayTrade(
      compra,
      fechadas.last,
      calcularAtr(altas, baixas, fechs, 14),
    );
  } else {
    sug = sugestaoSwing(compra, fechadas);
  }
  sug.precoAtual = precoAtual;
  sug.stopValido = !_verdadeiro(precoAtual) || sug.stop < precoAtual!;
  sug.alvoImediato = _verdadeiro(precoAtual) && sug.alvo <= precoAtual!;
  final avisos = <String>[];
  if (sug.modo == 'day_trade') {
    avisos.add(
      'Day trade: se a venda não ocorrer hoje, a operação passa a ser swing '
      'e esta sugestão deixa de valer.',
    );
  } else if (!sug.movelDisponivel) {
    avisos.add(
      'Stop móvel indisponível: o histórico tem menos de 23 pregões '
      'fechados.',
    );
  }
  if (!sug.stopValido) {
    avisos.add(
      'Preço já abaixo do stop sugerido: os botões de stop ficam '
      'desativados.',
    );
  }
  if (sug.alvoImediato) {
    avisos.add(
      'O alvo sugerido não está acima da cotação: a meta executaria na '
      'próxima barra ao preço do alvo.',
    );
  }
  sug.avisos = avisos;
  return sug;
}

/// Projeções, distâncias até a cotação e relações risco/retorno.
class Avaliacao {
  Avaliacao({
    required this.projAlvo,
    required this.projStop,
    required this.lucroAlvo,
    required this.perdaStop,
    this.distAlvoPct,
    this.distStopPct,
    this.rrPreco,
    this.rrLiquido,
  });

  final Projecao projAlvo;
  final Projecao projStop;
  final double lucroAlvo;
  final double perdaStop;
  final double? distAlvoPct;
  final double? distStopPct;
  final double? rrPreco;
  final double? rrLiquido;
}

/// Projeção líquida (taxas e imposto) de alvo e stop para [qtd] da compra,
/// distâncias até a cotação e relação risco/retorno. `perdaStop` é o
/// resultado após imposto no stop: negativo (perda, sem imposto) quando o
/// stop fica abaixo da compra e positivo (lucro protegido) quando fica acima.
Avaliacao avaliar(
  Lote lote,
  num qtd,
  Sugestao sug,
  double? precoAtual,
  bool dayTrade,
) {
  final pa = projetar(lote, qtd, sug.alvo, dayTrade: dayTrade);
  final ps = projetar(lote, qtd, sug.stop, dayTrade: dayTrade);
  final compra = lote.preco;
  final risco = compra - sug.stop;
  final lucro = pa.lucroAposImposto;
  final perda = ps.lucroAposImposto;
  final cotado = _verdadeiro(precoAtual);
  return Avaliacao(
    projAlvo: pa,
    projStop: ps,
    lucroAlvo: lucro,
    perdaStop: perda,
    distAlvoPct: cotado ? (sug.alvo / precoAtual! - 1) * 100 : null,
    distStopPct: cotado ? (sug.stop / precoAtual! - 1) * 100 : null,
    rrPreco: risco > 0 ? (sug.alvo - compra) / risco : null,
    rrLiquido: perda < 0 ? lucro / perda.abs() : null,
  );
}
