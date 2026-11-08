// Reconstrução das posições em aberto numa data de corte (entrega 2.1, §7.1).
// Função pura: não grava nada e não gera movimentação, resultado ou imposto.

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

/// Posições abertas em [dataCorte] (`AAAA-MM-DD`), ordenadas por ticker.
///
/// A cadeia de uma compra é `origem ?? id`; a quantidade comprada é a do lote
/// raiz (`id == chave`), e as cópias não somam compra. As vendas são todas as
/// da cadeia, em qualquer mês, até a data de corte.
List<PosicaoAtivo> posicoesEm(Map<String, Mes> meses, String dataCorte) {
  final cadeias = <String, List<(String, Lote)>>{};
  final nomes = ordenadoCom(meses.keys, compararTexto);
  for (final nome in nomes) {
    for (final l in meses[nome]!.lotes) {
      final chave = (l.origem != null && l.origem!.isNotEmpty)
          ? l.origem!
          : l.id;
      (cadeias[chave] ??= []).add((nome, l));
    }
  }
  final porTicker = <String, List<CompraNaPosicao>>{};
  final tipos = <String, String>{};
  cadeias.forEach((chave, lotes) {
    // raiz: o lote da compra original; sem ele (dados parciais), o mais antigo
    final raiz = lotes.firstWhere(
      (p) => p.$2.id == chave,
      orElse: () => lotes.first,
    );
    final l = raiz.$2;
    if (compararTexto(l.dataCompra, dataCorte) > 0) return;
    var vendidas = 0;
    for (final p in lotes) {
      for (final v in p.$2.vendas) {
        if (compararTexto(v.data, dataCorte) <= 0) vendidas += v.qtd;
      }
    }
    final resta = l.qtd - vendidas;
    if (resta <= 0) return;
    tipos[l.ticker] = l.tipo;
    (porTicker[l.ticker] ??= []).add(
      CompraNaPosicao(
        loteId: l.id,
        mes: raiz.$1,
        dataCompra: l.dataCompra,
        qtdOriginal: l.qtd,
        restante: resta,
        preco: l.preco,
      ),
    );
  });
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
      ),
  ];
}
