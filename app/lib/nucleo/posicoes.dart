// Reconstrução das posições em aberto numa data de corte (entrega 2.1, §7.1).
// Função pura: não grava nada e não gera movimentação, resultado ou imposto.

import 'apuracao_medio.dart';
import 'compat/ordenacao.dart';
import 'datas.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

/// Uma compra (cadeia de cópias) com saldo na data de corte.
class CompraNaPosicao {
  const CompraNaPosicao({
    required this.loteId,
    required this.mes,
    required this.dataCompra,
    required this.qtdOriginal,
    required this.restante,
    required this.preco,
  });

  final String loteId;

  /// Mês do lote raiz da cadeia (ou do mês aberto), não o mês da compra.
  final String mes;
  final String dataCompra;
  final int qtdOriginal;
  final int restante;
  final double preco;
}

/// Posição de um ticker na data de corte.
class PosicaoAtivo {
  PosicaoAtivo({
    required this.ticker,
    required this.tipo,
    required this.qtd,
    required this.custoGerencial,
    this.custoFiscal,
    required this.compras,
  });

  final String ticker;
  final String tipo;
  final int qtd;
  final double custoGerencial;

  /// `null` até o custo fiscal ser calculado; então o custo é "por compra".
  double? custoFiscal;
  final List<CompraNaPosicao> compras;

  bool get custoPorCompra => custoFiscal == null;

  double? get precoMedio =>
      qtd == 0 ? null : (custoFiscal ?? custoGerencial) / qtd;
}

/// Último dia de [mes] (`AAAA-MM`), ou [hoje] (`AAAA-MM-DD`) no mês de hoje.
String dataCorteDoMes(String mes, String hoje) {
  if (mes == hoje.substring(0, 7)) return hoje;
  return somarDias('${proximoMes(mes)}-01', -1);
}

String _chave(Lote l) =>
    (l.origem != null && l.origem!.isNotEmpty) ? l.origem! : l.id;

int _vendidoAte(Lote l, String dataCorte) => l.vendas.fold(
  0,
  (soma, v) => compararTexto(v.data, dataCorte) <= 0 ? soma + v.qtd : soma,
);

/// Posições abertas em [dataCorte] (`AAAA-MM-DD`), ordenadas por ticker.
///
/// Meses fechados são histórico imutável. Para cortes dentro deles, a cadeia
/// de uma compra é `origem ?? id`; a quantidade comprada é a do lote raiz
/// (`id == chave`), e as cópias não somam compra. As vendas são todas as da
/// cadeia, em qualquer mês, até a data de corte.
///
/// Para cortes a partir do primeiro mês aberto, vale o estado desse mês: a
/// cadeia só existe se tiver lote nele (compra excluída conta 0 dali em
/// diante), com a `qtd` e o `preco` como estão (editados) menos as vendas do
/// próprio mês até o corte. Vendas retroativas já reduziram a `qtd` desse
/// lote, por isso as de outros meses não são subtraídas de novo.
List<PosicaoAtivo> posicoesEm(Map<String, Mes> meses, String dataCorte) {
  final nomes = ordenadoCom(meses.keys, compararTexto);
  final abertos = [
    for (final n in nomes)
      if (!meses[n]!.fechado) n,
  ];
  final porTicker = <String, List<CompraNaPosicao>>{};
  final tipos = <String, String>{};
  void somar(Lote l, String mes, int qtdOriginal, int resta) {
    if (resta <= 0) return;
    tipos[l.ticker] = l.tipo;
    (porTicker[l.ticker] ??= []).add(
      CompraNaPosicao(
        loteId: l.id,
        mes: mes,
        dataCompra: l.dataCompra,
        qtdOriginal: qtdOriginal,
        restante: resta,
        preco: l.preco,
      ),
    );
  }

  if (abertos.isNotEmpty &&
      compararTexto(dataCorte.substring(0, 7), abertos.first) >= 0) {
    final aberto = abertos.first;
    final cadeias = <String, List<Lote>>{};
    for (final l in meses[aberto]!.lotes) {
      (cadeias[_chave(l)] ??= []).add(l);
    }
    for (final lotes in cadeias.values) {
      final l = lotes.first;
      if (compararTexto(l.dataCompra, dataCorte) > 0) continue;
      var qtd = 0;
      var resta = 0;
      for (final x in lotes) {
        qtd += x.qtd;
        resta += x.qtd - _vendidoAte(x, dataCorte);
      }
      somar(l, aberto, qtd, resta);
    }
  } else {
    final cadeias = <String, List<(String, Lote)>>{};
    for (final nome in nomes) {
      for (final l in meses[nome]!.lotes) {
        (cadeias[_chave(l)] ??= []).add((nome, l));
      }
    }
    cadeias.forEach((chave, lotes) {
      final raiz = lotes.firstWhere(
        (p) => p.$2.id == chave,
        orElse: () => _maisAntigo(lotes, meses),
      );
      final l = raiz.$2;
      if (compararTexto(l.dataCompra, dataCorte) > 0) return;
      var vendidas = 0;
      for (final p in lotes) {
        vendidas += _vendidoAte(p.$2, dataCorte);
      }
      somar(l, raiz.$1, l.qtd, l.qtd - vendidas);
    });
  }
  final mesFiscal =
      abertos.isNotEmpty &&
          compararTexto(dataCorte.substring(0, 7), abertos.first) >= 0
      ? abertos.first
      : dataCorte.substring(0, 7);
  final fiscal = _fiscalEm(
    meses[mesFiscal],
    meses[somarDias('$mesFiscal-01', -1).substring(0, 7)],
    mesDeCorte(meses.values),
    dataCorte,
  );
  final tickers = ordenadoCom(porTicker.keys, compararTexto);
  return [
    for (final t in tickers)
      PosicaoAtivo(
        ticker: t,
        tipo: tipos[t]!,
        qtd: porTicker[t]!.fold(0, (s, c) => s + c.restante),
        custoGerencial: porTicker[t]!.fold(
          0.0,
          (s, c) => s + c.restante * c.preco,
        ),
        compras: ordenadoCom(porTicker[t]!, (a, b) {
          final c = compararTexto(a.dataCompra, b.dataCompra);
          return c != 0 ? c : compararTexto(a.loteId, b.loteId);
        }),
      )..custoFiscal = _custoSeBate(fiscal?[t], porTicker[t]!),
  ];
}

/// Custo fiscal só quando a quantidade fiscal bate com a dos lotes; senão o
/// saldo está inconsistente e o custo fica "por compra".
double? _custoSeBate(PosicaoFiscal? f, List<CompraNaPosicao> compras) =>
    f != null && f.qtd == compras.fold(0, (s, c) => s + c.restante)
    ? f.custo
    : null;

/// Posição fiscal em [dataCorte] pelo mês [m] quando ele usa o custo médio: a
/// posição inicial do mês (se ainda sem marcador, a que [marcarAoCarregar]
/// daria com o mês [anterior], numa cópia) mais as compras e vendas até a
/// data, pela mesma apuração do mês.
Map<String, PosicaoFiscal>? _fiscalEm(
  Mes? m,
  Mes? anterior,
  String? corte,
  String dataCorte,
) {
  if (m == null || !usaCustoMedio(m, corte)) return null;
  var inicial = m.posicaoInicial;
  if (m.metodo != metodoCustoMedio) {
    final copia = Mes(mes: m.mes, lotes: m.lotes);
    marcarAoCarregar(copia, anterior);
    inicial = copia.posicaoInicial;
  }
  final ate = Mes(
    mes: m.mes,
    metodo: metodoCustoMedio,
    posicaoInicial: inicial ?? posicaoInicialDerivada(m),
    prejuizoAnterior: m.prejuizoAnterior,
    lotes: [
      for (final l in m.lotes)
        if (compararTexto(l.dataCompra, dataCorte) <= 0)
          Lote.fromJson({
            ...l.toJson(),
            'vendas': [
              for (final v in l.vendas)
                if (compararTexto(v.data, dataCorte) <= 0) v.toJson(),
            ],
          }),
    ],
  );
  return apurarCustoMedio(ate).posicaoFinal;
}

/// Cadeia sem lote raiz (dados parciais): a compra mais antiga que não vem de
/// mês de venda retroativa, com a maior `qtd` entre as de mesma data.
(String, Lote) _maisAntigo(List<(String, Lote)> lotes, Map<String, Mes> meses) {
  final normais = [
    for (final p in lotes)
      if (!meses[p.$1]!.retroativo) p,
  ];
  return ordenadoCom(normais.isEmpty ? lotes : normais, (a, b) {
    final c = compararTexto(a.$2.dataCompra, b.$2.dataCompra);
    if (c != 0) return c;
    if (a.$2.qtd != b.$2.qtd) return b.$2.qtd - a.$2.qtd;
    return compararTexto(a.$1, b.$1);
  }).first;
}
