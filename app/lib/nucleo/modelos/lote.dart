import 'com_mod.dart';

/// Venda de parte de uma compra (`lote["vendas"]`).
class Venda implements ComMod {
  Venda({
    required this.id,
    required this.data,
    required this.qtd,
    required this.preco,
    this.mod = 0,
  });

  factory Venda.fromJson(Map<String, Object?> json) => Venda(
    id: lerTexto(json['id']),
    data: lerTexto(json['data']),
    qtd: lerInt(json['qtd']),
    preco: lerDouble(json['preco']),
    mod: lerDouble(json['mod']),
  );

  String id;
  String data;
  int qtd;
  double preco;
  @override
  double mod;

  Map<String, Object?> toJson() => {
    'id': id,
    'data': data,
    'qtd': qtd,
    'preco': preco,
    'mod': mod,
  };
}

/// Compra de um ativo no mês, com as vendas feitas a partir dela.
class Lote implements ComMod {
  Lote({
    required this.id,
    this.origem,
    required this.ticker,
    required this.tipo,
    required this.dataCompra,
    required this.qtd,
    required this.preco,
    List<Venda>? vendas,
    this.mod = 0,
  }) : vendas = vendas ?? [];

  factory Lote.fromJson(Map<String, Object?> json) => Lote(
    id: lerTexto(json['id']),
    origem: lerTextoOuNulo(json['origem']),
    ticker: lerTexto(json['ticker']),
    tipo: lerTexto(json['tipo']),
    dataCompra: lerTexto(json['data_compra']),
    qtd: lerInt(json['qtd']),
    preco: lerDouble(json['preco']),
    vendas: [for (final v in lerLista(json['vendas'])) Venda.fromJson(v)],
    mod: lerDouble(json['mod']),
  ).._ordem = json.keys.toList();

  String id;

  /// Id da compra de origem, nas cópias levadas para o mês seguinte.
  String? origem;
  String ticker;
  String tipo;
  String dataCompra;
  int qtd;
  double preco;
  List<Venda> vendas;
  @override
  double mod;

  List<String>? _ordem;

  Map<String, Object?> toJson() => emOrdem({
    'id': id,
    if (origem != null) 'origem': origem,
    'ticker': ticker,
    'tipo': tipo,
    'data_compra': dataCompra,
    'qtd': qtd,
    'preco': preco,
    'vendas': [for (final v in vendas) v.toJson()],
    'mod': mod,
  }, _ordem);
}
