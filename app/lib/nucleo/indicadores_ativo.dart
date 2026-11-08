// Indicadores por ativo (entrega 2.1, §8). Função pura: lê os meses e a
// posição, não grava nada. "null" significa dado indisponível ou divisão por
// zero, nunca zero. A rentabilidade é a razão de dois totais em R$, nunca a
// média de percentuais de operações.

import 'apuracao.dart';
import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'modelos/mes.dart';
import 'posicoes.dart';
import 'tick.dart';

/// Preço de venda que zera o custo do saldo: custo médio mais a corretagem
/// rateada, dividido pelo que sobra depois da taxa B3 da venda, no tick.
double? pontoEquilibrio(String ticker, int qtd, double custoTotal) {
  if (qtd == 0) return null;
  return tetoTick(
    ticker,
    (custoTotal / qtd + corretagemPorOrdem / qtd) / (1 - taxaB3Swing),
  );
}

class IndicadoresAtivo {
  IndicadoresAtivo({
    required this.ticker,
    required this.qtdAberta,
    required this.custoRemanescente,
    required this.custoPorCompra,
    required this.metodoResultado,
    required this.precoMedioCompras,
    required this.precoMedioVendasMes,
    required this.resultadoMes,
    required this.resultadoAcumulado,
    required this.desde,
    required this.ganhoPorUnidade,
    required this.rentabilidadeRealizada,
    this.naoRealizado,
    this.valorMercado,
    this.exposicao,
    required this.taxasMes,
    required this.pontoEquilibrio,
  });

  final String ticker;

  /// Σ restante na data de corte.
  final int qtdAberta;

  /// Custo do saldo; `null` sem saldo.
  final double? custoRemanescente;

  /// O custo é gerencial (Σ restante × preço), não o da posição fiscal.
  final bool custoPorCompra;

  /// Método da apuração do mês consultado (`metodoCustoMedio` ou nulo = por
  /// compra): vale para o resultado e a rentabilidade, mesmo sem saldo.
  final String? metodoResultado;

  /// Custo remanescente / quantidade em aberto.
  final double? precoMedioCompras;

  /// Σ(q·p das vendas do mês) / Σq; `null` sem vendas no mês.
  final double? precoMedioVendasMes;

  /// Resultado realizado no mês, depois das taxas e antes do imposto.
  final double resultadoMes;

  /// Σ do resultado realizado dos meses até o consultado.
  final double resultadoAcumulado;

  /// `MM/AAAA` do primeiro mês com dados.
  final String desde;

  /// Resultado do mês / Σq vendida no mês.
  final double? ganhoPorUnidade;

  /// Resultado do mês / custo das unidades vendidas no mês.
  final double? rentabilidadeRealizada;

  /// Q × cotação − custo remanescente; só com cotação atual.
  final double? naoRealizado;

  /// Q × cotação; só com cotação atual.
  final double? valorMercado;

  /// Valor do ativo / Σ valor da carteira; `null` se faltar cotação de algum.
  final double? exposicao;

  /// Σ(taxas B3 + corretagem) das vendas do mês.
  final double taxasMes;

  final double? pontoEquilibrio;

  /// Há venda do ativo no mês.
  bool get vendeuNoMes => precoMedioVendasMes != null;

  IndicadoresAtivo _com({
    double? naoRealizado,
    double? valorMercado,
    double? exposicao,
  }) => IndicadoresAtivo(
    ticker: ticker,
    qtdAberta: qtdAberta,
    custoRemanescente: custoRemanescente,
    custoPorCompra: custoPorCompra,
    metodoResultado: metodoResultado,
    precoMedioCompras: precoMedioCompras,
    precoMedioVendasMes: precoMedioVendasMes,
    resultadoMes: resultadoMes,
    resultadoAcumulado: resultadoAcumulado,
    desde: desde,
    ganhoPorUnidade: ganhoPorUnidade,
    rentabilidadeRealizada: rentabilidadeRealizada,
    naoRealizado: naoRealizado,
    valorMercado: valorMercado,
    exposicao: exposicao,
    taxasMes: taxasMes,
    pontoEquilibrio: pontoEquilibrio,
  );
}

/// Preenche não realizado, valor de mercado e exposição com as cotações
/// atuais ([cotacoes]: ticker → preço, `null` = falhou). Sem cotação de algum
/// ativo em aberto a exposição de todos fica indisponível.
List<IndicadoresAtivo> comCotacoes(
  List<IndicadoresAtivo> lista,
  Map<String, double?> cotacoes,
) {
  double? valor(IndicadoresAtivo i) {
    final p = cotacoes[i.ticker];
    if (i.qtdAberta == 0 || p == null) return null;
    return arredondar(i.qtdAberta * p, 2);
  }

  final abertos = [
    for (final i in lista)
      if (i.qtdAberta > 0) i,
  ];
  final completo = abertos.isNotEmpty && abertos.every((i) => valor(i) != null);
  final total = completo
      ? somaPython([for (final i in abertos) valor(i)!])
      : 0.0;
  return [
    for (final i in lista)
      i._com(
        valorMercado: valor(i),
        naoRealizado: valor(i) == null || i.custoRemanescente == null
            ? null
            : arredondar(valor(i)! - i.custoRemanescente!, 2),
        exposicao: completo && valor(i) != null && total > 0
            ? valor(i)! / total
            : null,
      ),
  ];
}

/// Indicadores de cada ativo com saldo em [posicao] ou vendido em [mes].
List<IndicadoresAtivo> indicadoresPorAtivo({
  required Map<String, Mes> meses,
  required String mes,
  required List<PosicaoAtivo> posicao,
  Map<String, double?> cotacoes = const {},
}) {
  final nomes = ordenadoCom(meses.keys, compararTexto);
  final ate = [
    for (final n in nomes)
      if (compararTexto(n, mes) <= 0) n,
  ];
  final desde = ate.isEmpty ? mes : ate.first;
  final textoDesde = '${desde.substring(5, 7)}/${desde.substring(0, 4)}';

  final ops = <String, List<Operacao>>{};
  final acumulado = <String, double>{};
  String? metodo;
  for (final n in ate) {
    final r = apurar(meses[n]!);
    if (n == mes) metodo = r.metodo;
    for (final o in r.ops) {
      acumulado[o.ticker] =
          (acumulado[o.ticker] ?? 0.0) + (o.resultadoFiscal ?? o.liquido);
      if (n == mes) (ops[o.ticker] ??= []).add(o);
    }
  }
  final porTicker = {for (final p in posicao) p.ticker: p};
  final tickers = ordenadoCom({...porTicker.keys, ...ops.keys}, compararTexto);

  final saida = <IndicadoresAtivo>[];
  for (final t in tickers) {
    final p = porTicker[t];
    final linhas = ops[t] ?? const <Operacao>[];
    final qtdVendida = linhas.fold(0, (s, o) => s + o.qtd);
    final resultado = somaPython(
      linhas.map((o) => o.resultadoFiscal ?? o.liquido),
    );
    final custoVendido = somaPython(
      linhas.map((o) => o.custoFiscal ?? o.compra),
    );
    final qtd = p?.qtd ?? 0;
    final custo = p == null || qtd == 0
        ? null
        : (p.custoFiscal ?? p.custoGerencial);
    saida.add(
      IndicadoresAtivo(
        ticker: t,
        qtdAberta: qtd,
        custoRemanescente: custo,
        custoPorCompra: p?.custoPorCompra ?? true,
        metodoResultado: metodo,
        precoMedioCompras: custo == null ? null : custo / qtd,
        precoMedioVendasMes: qtdVendida == 0
            ? null
            : somaPython(linhas.map((o) => o.qtd * o.preco)) / qtdVendida,
        resultadoMes: resultado,
        resultadoAcumulado: acumulado[t] ?? 0.0,
        desde: textoDesde,
        ganhoPorUnidade: qtdVendida == 0 ? null : resultado / qtdVendida,
        rentabilidadeRealizada: custoVendido == 0
            ? null
            : resultado / custoVendido,
        taxasMes: somaPython(linhas.map((o) => o.taxas + o.corretagem)),
        pontoEquilibrio: custo == null ? null : pontoEquilibrio(t, qtd, custo),
      ),
    );
  }
  return cotacoes.isEmpty ? saida : comCotacoes(saida, cotacoes);
}
