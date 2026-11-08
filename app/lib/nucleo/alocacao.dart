// Alocação gerencial de uma venda entre as compras do ativo. Só rastreia qual
// compra foi consumida; o resultado fiscal vem sempre de `apurar`. Compras do
// mesmo dia são day trade e entram primeiro, travadas (regra da Receita).

import 'ambiente.dart';
import 'apuracao.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'datas.dart';
import 'erros.dart';
import 'modelos/lote.dart';
import 'metas/cadeia.dart';
import 'modelos/config.dart';
import 'modelos/mes.dart';
import 'repositorio.dart';

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
  if (qtd <= 0) throw ErroValidacao('Quantidade inválida.');
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
    if (!porId.containsKey(i.lote.id)) {
      return 'Compra fora das disponíveis nessa data.';
    }
    if (i.qtd <= 0) return 'Quantidade inválida em uma das compras escolhidas.';
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

/// Prévia da venda: [gerencial] depende da alocação; usa a taxa da B3 de swing
/// no custo efetivo e ignora a corretagem da venda (serve para comparar
/// alocações, não para o imposto); [fiscal] é a variação do
/// lucro líquido da apuração do mês e não depende de qual compra se escolheu
/// além do regime (day trade ou comum).
class PreviaVenda {
  const PreviaVenda({
    required this.linhas,
    required this.gerencial,
    required this.fiscal,
    required this.qtdDt,
    required this.qtdComum,
    this.aviso,
  });

  final List<LinhaPrevia> linhas;
  final double gerencial;
  final double fiscal;
  final int qtdDt;
  final int qtdComum;

  /// Aviso (sem bloquear) quando a venda usa quantidade reservada por metas
  /// ativas; preenchido pelo serviço, nulo se não há.
  final String? aviso;
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

/// Pedido de venda por quantidade. [grupo] é o id criado quando o formulário
/// abre (chave de idempotência); [selecao] nulo = alocação automática.
class NovaVendaQtd {
  const NovaVendaQtd({
    required this.ticker,
    required this.data,
    required this.qtd,
    required this.preco,
    required this.grupo,
    this.selecao,
  });

  final String ticker;
  final String data;
  final int qtd;
  final double preco;
  final String grupo;
  final List<(String loteId, int qtd)>? selecao;
}

/// Vendas do grupo [grupo] em [d], com a compra de cada uma.
List<(Lote, Venda)> _vendasDoGrupo(Mes d, String grupo) => [
  for (final l in d.lotes)
    for (final v in l.vendas)
      if (grupoDe(v.id) == grupo) (l, v),
];

/// Valida o pedido contra [d] (data, quantidade, preço, seleção) e devolve a
/// alocação. Não altera [d].
List<ItemAlocacao> alocarPedido(Mes d, String mes, NovaVendaQtd v) {
  if (v.grupo.trim().isEmpty) throw ErroValidacao('Venda sem identificador.');
  if (d.fechado) throw ErroValidacao('O mês está fechado.');
  final data = v.data;
  var valida = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data);
  if (valida) {
    try {
      somarDias(data, 0);
    } on FormatException {
      valida = false;
    }
  }
  if (!valida) throw ErroValidacao('Selecione a data da venda.');
  if (data.substring(0, 7) != mes) {
    throw ErroValidacao(
      'A venda em várias compras vale só para o mês aberto; para mês '
      'anterior, venda uma compra de cada vez.',
    );
  }
  if (data.compareTo(ambiente.hoje()) > 0) {
    throw ErroValidacao('Data da venda inválida para essa compra.');
  }
  if (v.qtd <= 0) throw ErroValidacao('Quantidade inválida.');
  if (!(v.preco > 0) || v.preco.isInfinite) {
    throw ErroValidacao('Preço inválido.');
  }
  final el = comprasElegiveis(d, v.ticker.trim().toUpperCase(), data);
  final sel = v.selecao;
  if (sel == null) return alocarAutomatico(el, v.qtd, data);
  final porId = {for (final l in el) l.id: l};
  final itens = <ItemAlocacao>[];
  for (final (id, q) in sel) {
    final l = porId[id];
    if (l == null) {
      throw ErroValidacao('Compra fora das disponíveis nessa data.');
    }
    itens.add(ItemAlocacao(l, q, travado: _doDia(l, data)));
  }
  final erro = validarManual(el, itens, v.qtd, data);
  if (erro != null) throw ErroValidacao(erro);
  return itens;
}

/// Acrescenta as linhas em [d]. Uma compra: id [NovaVendaQtd.grupo] (se não
/// estiver em [usados]); várias: `grupo.k` com k fora de [usados]. Nascem com
/// `mod` 0; `salvar` carimba todas com a mesma hora.
void _acrescentar(
  Mes d,
  List<ItemAlocacao> itens,
  NovaVendaQtd v,
  Set<String> usados,
) {
  final vendas = montarVendas(itens, v.grupo, v.data, v.preco, 0);
  final simples = itens.length == 1 && !usados.contains(v.grupo);
  var k = 0;
  for (final (i, item) in itens.indexed) {
    if (!simples) {
      do {
        k++;
      } while (usados.contains('${v.grupo}.$k'));
      vendas[i].id = '${v.grupo}.$k';
    } else {
      vendas[i].id = v.grupo;
    }
    d.lotes.firstWhere((l) => l.id == item.lote.id).vendas.add(vendas[i]);
  }
}

/// Confirma a venda: relê o mês do disco, devolve `duplicada` sem gravar se o
/// grupo já existe (confirmação repetida) e senão valida contra o disco,
/// acrescenta todas as linhas e grava uma única vez.
({Mes mes, bool duplicada}) confirmarVenda(
  Repositorio repo,
  String mes,
  NovaVendaQtd v,
) {
  final d = repo.carregar(mes);
  if (v.grupo.trim().isEmpty) throw ErroValidacao('Venda sem identificador.');
  // grupo excluído depois (reenvio tardio) também conta: não ressuscita
  if (_vendasDoGrupo(d, v.grupo).isNotEmpty ||
      d.excluidos.keys.any((i) => grupoDe(i) == v.grupo)) {
    return (mes: d, duplicada: true);
  }
  final itens = alocarPedido(d, mes, v);
  _acrescentar(d, itens, v, {...d.excluidos.keys});
  repo.salvar(d);
  return (mes: d, duplicada: false);
}

/// Refaz o grupo [grupo]: libera a quantidade dele, aloca de novo e grava uma
/// vez. As linhas que somem vão para `excluidos` (carimbo de `salvar`) e as
/// novas usam sufixos que o grupo nunca usou.
Mes editarGrupo(Repositorio repo, String mes, String grupo, NovaVendaQtd v) {
  final d = repo.carregar(mes);
  if (grupo.trim().isEmpty) throw ErroValidacao('Venda sem identificador.');
  final antigas = _vendasDoGrupo(d, grupo);
  if (antigas.isEmpty) throw ErroValidacao('Venda não encontrada.');
  final idsAntigos = {for (final (_, x) in antigas) x.id};
  for (final (l, _) in antigas) {
    l.vendas = [
      for (final x in l.vendas)
        if (!idsAntigos.contains(x.id)) x,
    ];
  }
  final novo = NovaVendaQtd(
    ticker: v.ticker,
    data: v.data,
    qtd: v.qtd,
    preco: v.preco,
    grupo: grupo,
    selecao: v.selecao,
  );
  final itens = alocarPedido(d, mes, novo);
  // o id simples do grupo pode voltar (é a mesma venda) se não foi excluído
  final usados = {...d.excluidos.keys, ...idsAntigos}
    ..remove(grupo)
    ..addAll(d.excluidos.keys.where((i) => i == grupo));
  _acrescentar(d, itens, novo, usados);
  repo.salvar(d);
  return d;
}

/// Aviso se a alocação [itens] consome quantidade reservada por metas ativas
/// (stop, alvo, OCO), ou nulo. Não bloqueia a venda.
String? avisoMetasReservadas(
  Repositorio repo,
  Config cfg,
  Mes d,
  List<ItemAlocacao> itens, {
  Map<String, Mes>? meses,
}) {
  final todos = meses ?? repo.carregarMeses();
  final r = raizes(todos);
  final partes = <String>[];
  for (final i in itens) {
    final res = reservado(repo, cfg, i.lote.id, meses: todos);
    if (res <= 0 || i.qtd <= restante(i.lote) - res) continue;
    final raiz = r[i.lote.id] ?? i.lote.id;
    final metas = [
      for (final m in metasAtivas(cfg))
        if ((r[m.loteId] ?? m.loteId) == raiz)
          'meta ${m.tipo.isEmpty ? 'de venda' : m.tipo} de ${m.qtd}',
    ];
    partes.add(
      '${i.lote.ticker}, compra de ${fmtData(i.lote.dataCompra)} '
      '(${metas.join(', ')})',
    );
  }
  if (partes.isEmpty) return null;
  return 'Esta venda usa quantidade reservada por metas ativas em '
      '${partes.join('; ')}; a meta ficará inválida se o saldo não bastar.';
}
