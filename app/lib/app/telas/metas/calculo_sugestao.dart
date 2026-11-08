// Cálculo, filtro e ordenação das sugestões por ativo. Funções puras sobre o
// que o serviço já trouxe (barras, cotação e posição): mudar quantidade,
// preço ou horizonte refaz tudo aqui, sem nova requisição, e nada é gravado.

import '../../../nucleo/nucleo.dart';
import '../../servicos/api.dart';

enum FiltroDados { todos, comDados, semDados }

enum OrdemSugestao { rr, distancia, liquidez, ticker }

/// O que o usuário digitou para um ativo; nulo = campo vazio ou inválido.
class EntradasAtivo {
  const EntradasAtivo({this.qtd, this.preco, this.lucro});

  final int? qtd;
  final double? preco;
  final double? lucro;
}

/// Tudo o que a tela mostra de um ativo para o horizonte escolhido.
class ResultadoAtivo {
  const ResultadoAtivo({
    required this.ativo,
    required this.horizonte,
    this.posicao,
    this.cenario,
    this.consolidado,
    this.pontoEquilibrio,
    this.meta,
    this.erroMeta,
  });

  final SugestaoAtivo ativo;
  final Horizonte horizonte;

  /// Posição considerada: a carteira toda no swing; só as compras de hoje no
  /// day trade. Nula para um ticker só do radar.
  final PosicaoAtivo? posicao;

  /// Nulo quando o ticker falhou ou não tem dados.
  final CenarioMercado? cenario;

  /// Nulo sem posição ou sem cenário.
  final ConsolidadoAtivo? consolidado;
  final double? pontoEquilibrio;

  /// Preço da meta financeira (simulação); nulo sem lucro desejado.
  final double? meta;
  final String? erroMeta;

  /// Os cinco números do cenário existem (há alvo e stop).
  bool get temCenario => cenario?.alvo != null && cenario?.stop != null;

  bool get comDados => ativo.estado == EstadoDados.ok;
}

/// Quantidade usada nos avisos de liquidez de um ticker só do radar.
const qtdPadraoRadar = 100;

/// Posição do day trade: só as compras de hoje, a custo gerencial.
PosicaoAtivo? _posicaoDeHoje(PosicaoAtivo? p, String hoje) {
  if (p == null) return null;
  final compras = [
    for (final c in p.compras)
      if (c.dataCompra == hoje) c,
  ];
  if (compras.isEmpty) return null;
  return PosicaoAtivo(
    ticker: p.ticker,
    tipo: p.tipo,
    qtd: compras.fold(0, (s, c) => s + c.restante),
    custoGerencial: compras.fold(0.0, (s, c) => s + c.restante * c.preco),
    compras: compras,
  );
}

/// Calcula o ativo; [hoje] é `AAAA-MM-DD` e [agoraBr] o relógio de Brasília.
ResultadoAtivo calcularAtivo(
  SugestaoAtivo a,
  Horizonte horizonte,
  EntradasAtivo e, {
  required String hoje,
  required DataHora agoraBr,
}) {
  final dayTrade = horizonte == Horizonte.dayTrade;
  final p = dayTrade ? _posicaoDeHoje(a.posicao, hoje) : a.posicao;
  final qtd = e.qtd ?? p?.qtd ?? qtdPadraoRadar;
  final custo = p == null ? null : (p.custoFiscal ?? p.custoGerencial);
  final pe = p == null || p.qtd == 0 || custo == null
      ? null
      : pontoEquilibrio(p.ticker, p.qtd, custo);
  double? meta;
  String? erroMeta;
  final lucro = e.lucro;
  if (lucro != null && p != null && p.qtd > 0 && custo != null) {
    try {
      // a meta vale para a posição inteira, não para a quantidade digitada
      meta = metaFinanceira(
        p.ticker,
        p.qtd,
        custo / p.qtd,
        lucro,
        dayTrade: dayTrade,
      );
    } on ErroValidacao catch (x) {
      erroMeta = x.mensagem;
    }
  }
  final temDados =
      a.estado == EstadoDados.ok || a.estado == EstadoDados.desatualizado;
  CenarioMercado? cenario;
  if (temDados) {
    cenario = dayTrade
        ? cenarioDayTrade(
            ticker: a.ticker,
            barras: a.barras,
            hoje: hoje,
            cotacao: a.cotacao,
            pregaoAberto: pregaoAbertoEm(agoraBr),
            pontoEquilibrio: pe,
            qtd: qtd,
            meta: meta,
          )
        : cenarioSwing(
            ticker: a.ticker,
            barras: a.barras,
            hoje: hoje,
            cotacao: a.cotacao,
            pontoEquilibrio: pe,
            qtd: qtd,
            meta: meta,
          );
  }
  return ResultadoAtivo(
    ativo: a,
    horizonte: horizonte,
    posicao: p,
    cenario: cenario,
    consolidado: p == null || cenario == null
        ? null
        : consolidar(
            p,
            cenario,
            meta: meta,
            precoDigitado: e.preco,
            qtdDigitada: e.qtd,
          ),
    pontoEquilibrio: pe,
    meta: meta,
    erroMeta: erroMeta,
  );
}

/// Aplica os filtros e a ordenação. [soPosicoes] esconde o radar sem
/// posição; no day trade só ficam os ativos com compra de hoje.
List<ResultadoAtivo> prepararLista(
  List<SugestaoAtivo> ativos, {
  required Horizonte horizonte,
  required bool soPosicoes,
  required FiltroDados dados,
  required OrdemSugestao ordem,
  required EntradasAtivo Function(String ticker) entradas,
  required String hoje,
  required DataHora agoraBr,
}) {
  final lista = <ResultadoAtivo>[];
  for (final a in ativos) {
    if (a.posicao == null && (soPosicoes || horizonte == Horizonte.dayTrade)) {
      continue;
    }
    final r = calcularAtivo(
      a,
      horizonte,
      entradas(a.ticker),
      hoje: hoje,
      agoraBr: agoraBr,
    );
    if (horizonte == Horizonte.dayTrade && r.posicao == null) continue;
    final passa = switch (dados) {
      FiltroDados.todos => true,
      FiltroDados.comDados => r.comDados,
      FiltroDados.semDados => !r.comDados,
    };
    if (passa) lista.add(r);
  }
  double? chave(ResultadoAtivo r) {
    final c = r.cenario;
    return switch (ordem) {
      OrdemSugestao.rr => c?.rr,
      OrdemSugestao.distancia =>
        c?.alvo == null || c?.ancora == null || c!.ancora! <= 0
            ? null
            : (c.alvo! - c.ancora!) / c.ancora!,
      OrdemSugestao.liquidez => c?.vfm,
      // sem cenário (falha, sem dados) vai para o fim também por ticker
      OrdemSugestao.ticker => c == null ? null : 0.0,
    };
  }

  // maior R/R e maior liquidez primeiro; menor distância até o alvo primeiro
  final sinal = ordem == OrdemSugestao.distancia ? 1.0 : -1.0;
  return ordenadoCom(lista, (x, y) {
    final kx = chave(x);
    final ky = chave(y);
    if ((kx == null) != (ky == null)) return kx == null ? 1 : -1;
    if (kx != null && ky != null && kx != ky) {
      return sinal * kx.compareTo(ky) < 0 ? -1 : 1;
    }
    return compararTexto(x.ativo.ticker, y.ativo.ticker);
  });
}
