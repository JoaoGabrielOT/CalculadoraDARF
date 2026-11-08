// Alocação gerencial de uma venda entre as compras do ativo. Só rastreia qual
// compra foi consumida; o resultado fiscal vem sempre de `apurar`. Compras do
// mesmo dia são day trade e entram primeiro, travadas (regra da Receita).

import 'apuracao.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'datas.dart';
import 'erros.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

/// Parte de uma venda tirada de uma compra. [travado]: compra do mesmo dia,
/// parte obrigatória de day trade.
class ItemAlocacao {
  const ItemAlocacao(this.lote, this.qtd, {this.travado = false});

  final Lote lote;
  final int qtd;
  final bool travado;
}

/// Compras do [ticker] que existiam em [dataVenda] e ainda têm saldo.
List<Lote> comprasElegiveis(Mes d, String ticker, String dataVenda) => [
  for (final l in d.lotes)
    if (l.ticker == ticker &&
        compararTexto(l.dataCompra, dataVenda) <= 0 &&
        restante(l) > 0)
      l,
];

/// Custo por ação com a taxa da B3 e a corretagem rateada pela compra.
double custoUnitarioEfetivo(Lote l) =>
    l.preco * (1 + taxaB3Swing) + corretagemPorOrdem / l.qtd;

bool _doDia(Lote l, String dataVenda) => l.dataCompra == dataVenda;

/// Compras do dia primeiro (travadas), depois menor custo efetivo; empate pela
/// compra mais antiga e depois pelo id.
List<ItemAlocacao> alocarAutomatico(
  List<Lote> elegiveis,
  int qtd,
  String dataVenda,
) {
  final disp = elegiveis.fold(0, (s, l) => s + restante(l));
  if (qtd > disp) {
    final ticker = elegiveis.isEmpty ? '' : elegiveis.first.ticker;
    throw ErroValidacao(
      'Quantidade indisponível: só há $disp ações de $ticker nessa data.',
    );
  }
  final ordem = ordenadoPor(
    elegiveis,
    (l) => [
      _doDia(l, dataVenda) ? 0 : 1,
      custoUnitarioEfetivo(l),
      l.dataCompra,
      l.id,
    ],
  );
  final saida = <ItemAlocacao>[];
  var falta = qtd;
  for (final l in ordem) {
    if (falta <= 0) break;
    final q = restante(l) < falta ? restante(l) : falta;
    if (q <= 0) continue;
    saida.add(ItemAlocacao(l, q, travado: _doDia(l, dataVenda)));
    falta -= q;
  }
  return saida;
}

/// Mensagem de erro da seleção manual ou nulo quando ela vale.
String? validarManual(
  List<Lote> elegiveis,
  List<ItemAlocacao> selecao,
  int qtd,
  String dataVenda,
) {
  final porId = {for (final l in elegiveis) l.id: l};
  final usado = <String, int>{};
  for (final i in selecao) {
    if (!porId.containsKey(i.lote.id) || i.qtd < 0) {
      return 'Compra fora das disponíveis nessa data.';
    }
    usado[i.lote.id] = (usado[i.lote.id] ?? 0) + i.qtd;
  }
  for (final e in usado.entries) {
    final l = porId[e.key]!;
    if (e.value > restante(l)) {
      return 'A compra de ${fmtData(l.dataCompra)} tem só ${restante(l)} '
          'ações disponíveis.';
    }
  }
  final soma = usado.values.fold(0, (s, q) => s + q);
  if (soma != qtd) {
    return 'A soma das compras escolhidas ($soma) é diferente da quantidade '
        'da venda ($qtd).';
  }
  final doDia = elegiveis.where((l) => _doDia(l, dataVenda));
  final disponivelDia = doDia.fold(0, (s, l) => s + restante(l));
  final obrigatorio = disponivelDia < qtd ? disponivelDia : qtd;
  final escolhidoDia = doDia.fold(0, (s, l) => s + (usado[l.id] ?? 0));
  if (escolhidoDia < obrigatorio) {
    return 'As compras de hoje entram primeiro (day trade, regra da Receita).';
  }
  return null;
}

/// Uma linha da prévia: o item, o custo por ação e o resultado gerencial.
class LinhaPrevia {
  const LinhaPrevia(this.item, this.custoEfetivo, this.resultadoGerencial);

  final ItemAlocacao item;
  final double custoEfetivo;
  final double resultadoGerencial;
}

/// Prévia da venda: [gerencial] depende da alocação; [fiscal] é a variação do
/// lucro líquido da apuração do mês e não depende de qual compra se escolheu
/// além do regime (day trade ou comum).
class PreviaVenda {
  const PreviaVenda({
    required this.linhas,
    required this.gerencial,
    required this.fiscal,
    required this.qtdDt,
    required this.qtdComum,
  });

  final List<LinhaPrevia> linhas;
  final double gerencial;
  final double fiscal;
  final int qtdDt;
  final int qtdComum;
}

PreviaVenda previa(
  Mes d,
  List<ItemAlocacao> selecao,
  double preco,
  String dataVenda,
) {
  final linhas = <LinhaPrevia>[];
  var gerencial = 0.0;
  var qtdDt = 0;
  var qtdComum = 0;
  for (final i in selecao) {
    final dt = _doDia(i.lote, dataVenda);
    final taxa = dt ? taxaB3Daytrade : taxaB3Swing;
    final ce = custoUnitarioEfetivo(i.lote);
    final r = i.qtd * preco - i.qtd * ce - i.qtd * preco * taxa;
    linhas.add(LinhaPrevia(i, ce, r));
    gerencial += r;
    if (dt) {
      qtdDt += i.qtd;
    } else {
      qtdComum += i.qtd;
    }
  }
  final copia = Mes.fromJson(d.toJson());
  final vendas = montarVendas(selecao, '__previa', dataVenda, preco, 0);
  for (final (k, i) in selecao.indexed) {
    copia.lotes.firstWhere((l) => l.id == i.lote.id).vendas.add(vendas[k]);
  }
  final fiscal = apurar(copia).lucroLiquido - apurar(d).lucroLiquido;
  return PreviaVenda(
    linhas: linhas,
    gerencial: gerencial,
    fiscal: fiscal,
    qtdDt: qtdDt,
    qtdComum: qtdComum,
  );
}

/// Uma venda por item; id [grupo] com um item, `grupo.k` (k de 1) com vários.
List<Venda> montarVendas(
  List<ItemAlocacao> selecao,
  String grupo,
  String data,
  double preco,
  double mod,
) => [
  for (final (k, i) in selecao.indexed)
    Venda(
      id: selecao.length == 1 ? grupo : '$grupo.${k + 1}',
      data: data,
      qtd: i.qtd,
      preco: preco,
      mod: mod,
    ),
];

final _reGrupo = RegExp(r'^(.+)\.(\d+)$');

/// Id do grupo de uma venda: o prefixo antes de `.k`, senão o próprio id.
String grupoDe(String vendaId) =>
    _reGrupo.firstMatch(vendaId)?.group(1) ?? vendaId;
