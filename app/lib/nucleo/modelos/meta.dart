import 'com_mod.dart';

/// Degrau do stop móvel (`meta["niveis"]`).
class Nivel {
  Nivel({required this.desde, required this.stop, required this.calcEm});

  factory Nivel.fromJson(Map<String, Object?> json) => Nivel(
    desde: lerTexto(json['desde']),
    stop: lerDouble(json['stop']),
    calcEm: lerTexto(json['calc_em']),
  );

  String desde;
  double stop;
  String calcEm;

  Map<String, Object?> toJson() => {
    'desde': desde,
    'stop': stop,
    'calc_em': calcEm,
  };
}

const _chavesConhecidas = {
  'id',
  'ticker',
  'tipo',
  'lote_id',
  'qtd',
  'gatilho',
  'preco_alvo',
  'stop_inicial',
  'movel',
  'stop_atual',
  'niveis',
  'criada_em',
  'status',
  'lucro_desejado',
  'sugestao',
  'oco',
  'mod',
  'execucao',
  'ultimo_erro',
  'cancelada_por',
  'cancelada_detalhe',
};

/// Meta de venda automática (alvo ou stop). Campo nulo = chave ausente no
/// dicionário do Python; chaves desconhecidas ficam em [extras].
class Meta implements ComMod {
  Meta({
    required this.id,
    required this.ticker,
    this.tipo = '',
    required this.loteId,
    required this.qtd,
    this.precoAlvo,
    this.lucroDesejado,
    required this.criadaEm,
    this.status = 'ativa',
    this.ultimoErro,
    this.execucao,
    this.mod = 0,
    this.gatilho,
    this.stopInicial,
    this.stopAtual,
    this.movel,
    this.niveis,
    this.oco,
    this.canceladaPor,
    this.canceladaDetalhe,
    this.sugestao,
    Map<String, Object?>? extras,
  }) : extras = extras ?? {};

  factory Meta.fromJson(Map<String, Object?> json) => Meta(
    id: lerTexto(json['id']),
    ticker: lerTexto(json['ticker']),
    tipo: lerTexto(json['tipo']),
    loteId: lerTexto(json['lote_id']),
    qtd: lerInt(json['qtd']),
    precoAlvo: lerDoubleOuNulo(json['preco_alvo']),
    lucroDesejado: lerDoubleOuNulo(json['lucro_desejado']),
    criadaEm: lerTexto(json['criada_em']),
    status: lerTextoOuNulo(json['status']),
    ultimoErro: lerTextoOuNulo(json['ultimo_erro']),
    execucao: lerMapaOuNulo(json['execucao']),
    mod: lerDouble(json['mod']),
    gatilho: lerTextoOuNulo(json['gatilho']),
    stopInicial: lerDoubleOuNulo(json['stop_inicial']),
    stopAtual: lerDoubleOuNulo(json['stop_atual']),
    movel: lerBoolOuNulo(json['movel']),
    niveis: json['niveis'] is List
        ? [for (final n in lerLista(json['niveis'])) Nivel.fromJson(n)]
        : null,
    oco: lerTextoOuNulo(json['oco']),
    canceladaPor: lerTextoOuNulo(json['cancelada_por']),
    canceladaDetalhe: lerTextoOuNulo(json['cancelada_detalhe']),
    sugestao: lerMapaOuNulo(json['sugestao']),
    extras: {
      for (final e in json.entries)
        if (!_chavesConhecidas.contains(e.key)) e.key: copiaProfunda(e.value),
    },
  ).._ordem = json.keys.toList();

  String id;
  String ticker;
  String tipo;
  String loteId;
  int qtd;
  double? precoAlvo;
  double? lucroDesejado;
  String criadaEm;

  /// Nulo quando a meta foi gravada sem a chave (o Python lê com
  /// `m.get("status")`, que só vira "ativa" na descrição e na planilha).
  String? status;
  String? ultimoErro;
  Map<String, Object?>? execucao;
  @override
  double mod;

  /// `"stop"`; nulo nas metas de alvo (e nas gravadas antes do stop).
  String? gatilho;
  double? stopInicial;
  double? stopAtual;
  bool? movel;
  List<Nivel>? niveis;

  /// Id do grupo OCO.
  String? oco;
  String? canceladaPor;
  String? canceladaDetalhe;
  Map<String, Object?>? sugestao;
  Map<String, Object?> extras;

  List<String>? _ordem;

  /// `m.get("status", "ativa")`.
  String get statusOuAtiva => status ?? 'ativa';

  Map<String, Object?> toJson() => emOrdem({
    'id': id,
    'ticker': ticker,
    'tipo': tipo,
    'lote_id': loteId,
    'qtd': qtd,
    if (gatilho != null) 'gatilho': gatilho,
    if (precoAlvo != null) 'preco_alvo': precoAlvo,
    if (stopInicial != null) 'stop_inicial': stopInicial,
    if (movel != null) 'movel': movel,
    if (stopAtual != null) 'stop_atual': stopAtual,
    if (niveis != null) 'niveis': [for (final n in niveis!) n.toJson()],
    'criada_em': criadaEm,
    if (status != null) 'status': status,
    if (lucroDesejado != null) 'lucro_desejado': lucroDesejado,
    if (sugestao != null) 'sugestao': copiaProfunda(sugestao),
    if (oco != null) 'oco': oco,
    'mod': mod,
    if (execucao != null) 'execucao': copiaProfunda(execucao),
    if (ultimoErro != null) 'ultimo_erro': ultimoErro,
    if (canceladaPor != null) 'cancelada_por': canceladaPor,
    if (canceladaDetalhe != null) 'cancelada_detalhe': canceladaDetalhe,
    for (final e in extras.entries) e.key: copiaProfunda(e.value),
  }, _ordem);

  /// Cópia independente (inclusive as listas e mapas internos).
  Meta copiar() => Meta.fromJson(toJson());
}
