// Fechamento de mês, venda retroativa e tickers frequentes (nucleo.py:378-441,
// 488-517, 742-743).

import 'ambiente.dart';
import 'apuracao.dart';
import 'apuracao_medio.dart';
import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'datas.dart';
import 'erros.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';
import 'repositorio.dart';

/// Fecha o mês, leva os ativos não vendidos para o mês seguinte e devolve
/// (apuração, próximo mês). O id da cópia é `'<id>~<prox>'`: dois aparelhos
/// que fecham o mesmo mês geram o mesmo id. No custo médio, o mês seguinte
/// (se aberto) herda o método, a posição fiscal e o prejuízo a compensar; com
/// saldo inconsistente, nada é gravado.
(Apuracao, String) fecharMes(Repositorio repo, Mes d) {
  final r = apurar(d);
  if (r.inconsistentes.isNotEmpty) {
    throw ErroValidacao(bloqueioSaldoInconsistente(r.inconsistentes));
  }
  d.fechado = true;
  d.resumo = r.resumo;
  repo.salvar(d);
  final prox = proximoMes(d.mes);
  final nd = repo.carregar(prox);
  if (!nd.fechado) {
    final ja = {for (final l in nd.lotes) l.origem};
    for (final l in d.lotes) {
      if (restante(l) > 0 && !ja.contains(l.id)) {
        nd.lotes.add(
          Lote(
            id: '${l.id}~$prox',
            origem: l.id,
            ticker: l.ticker,
            tipo: l.tipo,
            dataCompra: l.dataCompra,
            qtd: restante(l),
            preco: l.preco,
          ),
        );
      }
    }
    nd.darfAnterior = r.darf < darfMinimo ? r.darf : 0.0;
    if (r.metodo == metodoCustoMedio) {
      nd.metodo = metodoCustoMedio;
      nd.posicaoInicial = r.posicaoFinal;
      nd.prejuizoAnterior = PrejuizoAcumulado(
        comum: r.prejuizoComumFinal!,
        dayTrade: r.prejuizoDtFinal!,
      );
    }
    repo.salvar(nd);
  }
  return (r, prox);
}

const textoRetroativaCustoMedio =
    'Meses apurados por custo médio não aceitam venda retroativa.';

/// [mes] está no corte ou depois dele: tem o marcador ou, sem arquivo, algum
/// mês anterior tem (o marcador passa de um mês para o seguinte).
bool mesPorCustoMedio(Repositorio repo, String mes) {
  if (repo.existeMes(mes)) return repo.carregar(mes).metodo == metodoCustoMedio;
  for (final m in repo.listarMeses()) {
    if (compararTexto(m, mes) >= 0) break;
    if (repo.carregar(m).metodo == metodoCustoMedio) return true;
  }
  return false;
}

/// Venda de um mês anterior ao aberto: só em mês sem arquivo ou fechado sem
/// nenhuma compra em aberto (caso dos meses criados por venda retroativa; a
/// marcação "retroativo" não vai para a planilha), e nunca a partir do corte
/// do custo médio.
bool mesAceitaVendaRetroativa(Repositorio repo, String mes, String mesAtual) {
  if (compararTexto(mes, mesAtual) >= 0) return false;
  if (mesPorCustoMedio(repo, mes)) return false;
  if (!repo.existeMes(mes)) return true;
  final d = repo.carregar(mes);
  return d.retroativo || (d.fechado && d.lotes.every((l) => restante(l) == 0));
}

/// Grava a venda no mês em que ela ocorreu (fechado, com a apuração própria)
/// e tira a quantidade vendida da compra do mês atual [d]. DARF abaixo do
/// mínimo do mês da venda passa para o `darfAnterior` de [d]. Com [d] pelo
/// custo médio, a venda sai também da posição inicial dele (quantidade e
/// custo proporcional). Devolve o mês da venda.
String registrarVendaRetroativa(
  Repositorio repo,
  Mes d,
  String loteId,
  ({String data, int qtd, double preco}) venda,
) {
  final mes = venda.data.substring(0, 7);
  final lote = d.lotes.firstWhere((l) => l.id == loteId);
  if (lote.vendas.isNotEmpty) {
    // a corretagem das vendas é rateada por lote.qtd; reduzir a quantidade
    // mudaria a DARF delas
    throw ErroValidacao(
      'Essa compra já tem venda neste mês. '
      'Registre a venda antiga antes das vendas do mês.',
    );
  }
  final custoMedio = d.metodo == metodoCustoMedio;
  final pos = custoMedio ? (d.posicaoInicial?[lote.ticker]) : null;
  if (custoMedio && (pos == null || pos.qtd < venda.qtd)) {
    throw ErroValidacao(
      'Não há posição de ${lote.ticker} no início de ${fmtMes(d.mes)} '
      'para essa venda.',
    );
  }
  final dm = repo.carregar(mes);
  final darfAnt = dm.resumo?.darf ?? 0.0;
  final levadaAnt = darfAnt < darfMinimo ? darfAnt : 0.0;
  dm.retroativo = true;
  dm.fechado = true;
  dm.mod = ambiente.agora();
  final idLote = ambiente.novoId();
  final novo = Lote(
    id: idLote,
    // compra já debitada no mês de origem: não gera novo débito no caixa
    origem: lote.origem != null && lote.origem!.isNotEmpty ? lote.origem : null,
    ticker: lote.ticker,
    tipo: lote.tipo,
    dataCompra: lote.dataCompra,
    qtd: venda.qtd,
    preco: lote.preco,
    vendas: [
      Venda(
        id: ambiente.novoId(),
        data: venda.data,
        qtd: venda.qtd,
        preco: venda.preco,
      ),
    ],
  );
  dm.lotes.add(novo);
  final r = apurar(dm);
  dm.resumo = r.resumo;
  repo.salvar(dm);
  final levada = r.darf < darfMinimo ? r.darf : 0.0;
  d.darfAnterior = maxPython(d.darfAnterior - levadaAnt + levada, 0.0);
  if (pos != null) {
    final baixado = venda.qtd == pos.qtd
        ? pos.custo
        : arredondar(venda.qtd * pos.custo / pos.qtd, 2);
    pos
      ..custo = arredondar(pos.custo - baixado, 2)
      ..qtd -= venda.qtd;
    if (pos.qtd == 0) d.posicaoInicial!.remove(lote.ticker);
  }
  lote.qtd -= venda.qtd;
  if (lote.qtd <= 0) {
    d.lotes = [
      for (final l in d.lotes)
        if (l.id != loteId) l,
    ];
  }
  repo.salvar(d);
  return mes;
}

/// Corrige os registros já gravados; as compras alteradas recebem nova hora e
/// vencem na sincronização.
bool corrigirTipos(Repositorio repo) {
  var mudou = false;
  for (final mes in repo.listarMeses()) {
    final d = repo.carregar(mes);
    if (corrigirTiposMes(d)) {
      repo.salvar(d);
      mudou = true;
    }
  }
  return mudou;
}

/// Frequência de operações por ticker nos últimos meses e o tipo conhecido de
/// cada um.
(Map<String, int>, Map<String, String>) historicoTickers(
  Repositorio repo, {
  int mesesRecentes = 6,
}) {
  final freq = <String, int>{};
  final tipos = <String, String>{};
  final todos = repo.listarMeses();
  // `[-n:]` do Python: n = 0 devolve a lista inteira
  final inicio = mesesRecentes <= 0 || mesesRecentes >= todos.length
      ? 0
      : todos.length - mesesRecentes;
  for (final mes in todos.sublist(inicio)) {
    for (final l in repo.carregar(mes).lotes) {
      freq[l.ticker] =
          (freq[l.ticker] ?? 0) +
          ((l.origem != null && l.origem!.isNotEmpty) ? 0 : 1) +
          l.vendas.length;
      tipos[l.ticker] = l.tipo;
    }
  }
  return (freq, tipos);
}

/// Até 6 tickers sugeridos para o mês [d] (`sugestoes` do Python; renomeada
/// para não colidir com o módulo de sugestões).
(List<String>, Map<String, String>) sugestoesTickers(
  Repositorio repo,
  Mes d, {
  bool soCustodia = false,
}) {
  final (freq, tipos) = historicoTickers(repo);
  final custodia = {
    for (final l in d.lotes)
      if (restante(l) > 0) l.ticker,
  };
  final List<String> lista;
  if (soCustodia) {
    lista = ordenadoPor<String>(custodia, (t) => [-(freq[t] ?? 0), t]);
  } else {
    lista = ordenadoPor<String>({
      ...freq.keys,
      ...custodia,
    }, (t) => [-((freq[t] ?? 0) + (custodia.contains(t) ? 2 : 0)), t]);
  }
  return (lista.take(6).toList(), tipos);
}

/// Tickers com compra em aberto no mês inicial.
Set<String> custodiaAtual(Repositorio repo) => {
  for (final l in repo.carregar(repo.mesInicial()).lotes)
    if (restante(l) > 0) l.ticker,
};
