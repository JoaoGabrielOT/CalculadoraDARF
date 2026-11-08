import 'com_mod.dart';
import 'meta.dart';

/// Amigo com quem a planilha é compartilhada.
class Amigo implements ComMod {
  Amigo({required this.email, required this.desde, this.mod = 0});

  factory Amigo.fromJson(Map<String, Object?> json) => Amigo(
    email: lerTexto(json['email']),
    desde: lerTexto(json['desde']),
    mod: lerDouble(json['mod']),
  );

  String email;
  String desde;
  @override
  double mod;

  Map<String, Object?> toJson() => {'email': email, 'desde': desde, 'mod': mod};
}

/// Ativo acompanhado no radar; `pos` é a ordem escolhida pelo usuário.
class ItemRadar implements ComMod {
  ItemRadar({
    required this.ticker,
    this.nome = '',
    required this.desde,
    this.pos,
    this.mod = 0,
  });

  factory ItemRadar.fromJson(Map<String, Object?> json) => ItemRadar(
    ticker: lerTexto(json['ticker']),
    nome: lerTexto(json['nome']),
    desde: lerTexto(json['desde']),
    pos: lerIntOuNulo(json['pos']),
    mod: lerDouble(json['mod']),
  ).._ordem = json.keys.toList();

  String ticker;
  String nome;
  String desde;
  int? pos;
  @override
  double mod;

  List<String>? _ordem;

  Map<String, Object?> toJson() => emOrdem({
    'ticker': ticker,
    'nome': nome,
    'desde': desde,
    if (pos != null) 'pos': pos,
    'mod': mod,
  }, _ordem);
}

/// Saldo disponível informado pelo usuário (`cfg["caixa"]`).
class Caixa implements ComMod {
  Caixa({this.saldo = 0, this.data = '', this.mod = 0});

  factory Caixa.fromJson(Map<String, Object?> json) => Caixa(
    saldo: lerDouble(json['saldo']),
    data: lerTexto(json['data']),
    mod: lerDouble(json['mod']),
  );

  double saldo;
  String data;
  @override
  double mod;

  Map<String, Object?> toJson() => {'saldo': saldo, 'data': data, 'mod': mod};
}

const _chavesConhecidas = {
  'tema',
  'amigos',
  'radar',
  'planilhas',
  'pendente',
  'excluidos',
  'caixa',
  'metas',
};

/// `config.json`. As chaves que o app não conhece (`noticias_notificar`,
/// `radar_ordem_lista`...) ficam em [extras] e voltam na gravação.
class Config {
  Config({
    this.tema = 'Dark',
    List<Amigo>? amigos,
    List<ItemRadar>? radar,
    Map<String, String>? planilhas,
    this.pendente = false,
    Map<String, double>? excluidos,
    Caixa? caixa,
    List<Meta>? metas,
    Map<String, Object?>? extras,
  }) : amigos = amigos ?? [],
       radar = radar ?? [],
       planilhas = planilhas ?? {},
       excluidos = excluidos ?? {},
       caixa = caixa ?? Caixa(),
       metas = metas ?? [],
       extras = extras ?? {};

  /// Como `ler_config`: chave ausente assume o padrão de `CONFIG_PADRAO`.
  factory Config.fromJson(Map<String, Object?> json) => Config(
    tema: lerTexto(json['tema'], 'Dark'),
    amigos: [for (final a in lerLista(json['amigos'])) Amigo.fromJson(a)],
    radar: [for (final r in lerLista(json['radar'])) ItemRadar.fromJson(r)],
    planilhas: lerMapaTexto(json['planilhas']),
    pendente: lerBool(json['pendente']),
    excluidos: lerMapaDouble(json['excluidos']),
    caixa: Caixa.fromJson(lerMapa(json['caixa'])),
    metas: [for (final m in lerLista(json['metas'])) Meta.fromJson(m)],
    extras: {
      for (final e in json.entries)
        if (!_chavesConhecidas.contains(e.key)) e.key: copiaProfunda(e.value),
    },
  ).._ordem = json.keys.toList();

  String tema;
  List<Amigo> amigos;
  List<ItemRadar> radar;

  /// E-mail -> id da planilha.
  Map<String, String> planilhas;
  bool pendente;

  /// `"<lista>:<chave>"` -> momento da exclusão.
  Map<String, double> excluidos;
  Caixa caixa;
  List<Meta> metas;
  Map<String, Object?> extras;

  /// Ids das migrações de dados aplicadas neste aparelho (`migracoes.dart`),
  /// guardados nas [extras] (não vão para a planilha).
  List<String> get migracoes {
    final v = extras['migracoes'];
    return [
      if (v is List)
        for (final x in v)
          if (x is String) x,
    ];
  }

  set migracoes(List<String> ids) => extras['migracoes'] = [...ids];

  List<String>? _ordem;

  Map<String, Object?> toJson() => emOrdem({
    'tema': tema,
    'amigos': [for (final a in amigos) a.toJson()],
    'radar': [for (final r in radar) r.toJson()],
    'planilhas': {...planilhas},
    'pendente': pendente,
    'excluidos': {...excluidos},
    'caixa': caixa.toJson(),
    'metas': [for (final m in metas) m.toJson()],
    for (final e in extras.entries) e.key: copiaProfunda(e.value),
  }, _ordem);
}
