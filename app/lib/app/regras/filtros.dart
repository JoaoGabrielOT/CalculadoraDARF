// Filtros e ordenação das listas de compras, vendas e lançamentos do caixa
// (sem Flutter nem IO). Ordenação estável com `ordenadoPor`, como o `sort` do
// Python.

import '../../nucleo/nucleo.dart';

const double _semValor = double.negativeInfinity;

/// Estado do filtro da lista de compras (android/main.py:53).
class FiltroLotes {
  FiltroLotes({
    this.situacao = 'Todos',
    this.tipo = 'Todos',
    this.busca = '',
    this.ordem = 'cadastro',
    this.desc = false,
  });

  final String situacao;
  final String tipo;
  final String busca;
  final String ordem;
  final bool desc;

  /// Algum filtro fora do padrão (a ordem não conta), como o `filtrado` do
  /// Android (android/main.py:884).
  bool get filtrado =>
      situacao != 'Todos' || tipo != 'Todos' || busca.trim().isNotEmpty;

  FiltroLotes copiarCom({
    String? situacao,
    String? tipo,
    String? busca,
    String? ordem,
    bool? desc,
  }) => FiltroLotes(
    situacao: situacao ?? this.situacao,
    tipo: tipo ?? this.tipo,
    busca: busca ?? this.busca,
    ordem: ordem ?? this.ordem,
    desc: desc ?? this.desc,
  );
}

/// Estado do filtro da lista de vendas (android/main.py:55).
class FiltroVendas {
  FiltroVendas({
    this.operacao = 'Todas',
    this.tipo = 'Todos',
    this.busca = '',
    this.ordem = 'data',
    this.desc = true,
  });

  final String operacao;
  final String tipo;
  final String busca;
  final String ordem;
  final bool desc;

  bool get filtrado =>
      operacao != 'Todas' || tipo != 'Todos' || busca.trim().isNotEmpty;

  FiltroVendas copiarCom({
    String? operacao,
    String? tipo,
    String? busca,
    String? ordem,
    bool? desc,
  }) => FiltroVendas(
    operacao: operacao ?? this.operacao,
    tipo: tipo ?? this.tipo,
    busca: busca ?? this.busca,
    ordem: ordem ?? this.ordem,
    desc: desc ?? this.desc,
  );
}

/// Ordens que começam decrescentes ao serem escolhidas (android/main.py:873).
bool descPadrao(String ordem) => const {
  'data',
  'total',
  'resultado',
  'atual',
  'bruto',
  'liquido',
  'imposto',
  'taxas',
}.contains(ordem);

const _ordensLotes = {
  'data',
  'ticker',
  'qtd',
  'preco',
  'total',
  'atual',
  'resultado',
  'restante',
};

String _termo(String busca) => busca.trim().toUpperCase();

/// Compras filtradas e ordenadas (android/main.py:915-940). [preco] devolve a
/// cotação atual do ticker (ou nulo). A lista recebida não é alterada.
List<Lote> filtrarLotes(
  List<Lote> lotes,
  FiltroLotes f,
  double? Function(String ticker) preco,
) {
  var itens = lotes.toList();
  if (f.situacao == 'Em aberto') {
    itens = [
      for (final l in itens)
        if (restante(l) > 0) l,
    ];
  } else if (f.situacao == 'Vendidos') {
    itens = [
      for (final l in itens)
        if (restante(l) == 0) l,
    ];
  }
  if (f.tipo != 'Todos') {
    itens = [
      for (final l in itens)
        if (l.tipo == f.tipo) l,
    ];
  }
  final termo = _termo(f.busca);
  if (termo.isNotEmpty) {
    itens = [
      for (final l in itens)
        if (l.ticker.contains(termo)) l,
    ];
  }

  // Sem chave (cadastro ou ordem desconhecida): a ordem original, invertida
  // por inteiro no sentido decrescente.
  if (!_ordensLotes.contains(f.ordem)) {
    return f.desc ? itens.reversed.toList() : itens;
  }

  Object chave(Lote l) => switch (f.ordem) {
    'data' => l.dataCompra,
    'ticker' => l.ticker,
    'qtd' => l.qtd,
    'preco' => l.preco,
    'total' => l.qtd * l.preco,
    'atual' => _atual(l, preco),
    'resultado' => resultadoAberto(l, preco(l.ticker))?.$1 ?? _semValor,
    _ => restante(l),
  };

  return ordenadoPor(itens, (l) => [chave(l)], reverso: f.desc);
}

/// Preço atual só de compra ainda aberta; sem cotação (ou zero) vale -inf.
double _atual(Lote l, double? Function(String) preco) {
  final p = restante(l) > 0 ? preco(l.ticker) : null;
  return p == null || p == 0 ? _semValor : p;
}

/// Vendas filtradas e ordenadas (android/main.py:942-955). Ordem desconhecida
/// usa a data. A lista recebida não é alterada.
List<Operacao> filtrarVendas(List<Operacao> ops, FiltroVendas f) {
  var itens = ops.toList();
  if (f.operacao != 'Todas') {
    itens = [
      for (final o in itens)
        if (o.regime.startsWith(f.operacao)) o,
    ];
  }
  if (f.tipo != 'Todos') {
    itens = [
      for (final o in itens)
        if (o.tipo == f.tipo) o,
    ];
  }
  final termo = _termo(f.busca);
  if (termo.isNotEmpty) {
    itens = [
      for (final o in itens)
        if (o.ticker.contains(termo)) o,
    ];
  }
  Object chave(Operacao o) => switch (f.ordem) {
    'ticker' => o.ticker,
    'qtd' => o.qtd,
    'preco' => o.preco,
    'bruto' => o.bruto,
    'liquido' => o.liquido,
    'imposto' => o.imposto,
    'taxas' => o.taxas + o.corretagem,
    _ => o.data,
  };
  return ordenadoPor(itens, (o) => [chave(o)], reverso: f.desc);
}

/// Lançamentos do caixa pelo filtro da agenda (calculadora_darf.py:1873):
/// "A liquidar" = Pendente, "Liquidados" = Liquidado, o resto mostra tudo.
List<LancamentoCaixa> filtrarAgenda(
  List<LancamentoCaixa> itens,
  String filtro,
) {
  final status = switch (filtro) {
    'A liquidar' => 'Pendente',
    'Liquidados' => 'Liquidado',
    _ => null,
  };
  return [
    for (final i in itens)
      if (status == null || i.status == status) i,
  ];
}
