// Modelo tolerante do Relatório de Abertura de Mercado (JSON gerado por uma
// automação externa). Campo ausente ou de tipo errado vira null; enum
// desconhecido vira neutra; campos extras são ignorados.

import '../compat/ordenacao.dart';

/// Leitura do ativo, na ordem do termômetro.
enum Leitura { positiva, mista, neutra, negativa }

enum Direcao { alta, queda, neutra }

String? _chave(Object? v) => v is String ? v.trim().toLowerCase() : null;

Leitura leituraDe(Object? v) => Leitura.values.firstWhere(
  (l) => l.name == _chave(v),
  orElse: () => Leitura.neutra,
);

Direcao direcaoDe(Object? v) => Direcao.values.firstWhere(
  (d) => d.name == _chave(v),
  orElse: () => Direcao.neutra,
);

String? _texto(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

int? _inteiro(Object? v) => v is int
    ? v
    : (v is num && v.isFinite && v == v.truncate() ? v.toInt() : null);

double? _numero(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// Contagem do termômetro: negativo ou inválido vale 0.
int _naoNegativo(Object? v) {
  final n = _inteiro(v) ?? 0;
  return n < 0 ? 0 : n;
}

List<Object?> _lista(Object? v) => v is List ? v : const [];

Map<String, Object?>? _mapa(Object? v) =>
    v is Map ? v.cast<String, Object?>() : null;

List<String> _textos(Object? v) => [for (final e in _lista(v)) ?_texto(e)];

/// `AAAA-MM-DD` de um dia que existe no calendário; senão null.
String? _dataIso(Object? v) {
  final s = _texto(v);
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  return d != null && d.toIso8601String().startsWith(s) ? s : null;
}

class Fonte {
  const Fonte({required this.nome, required this.url});

  final String nome;
  final String url;

  static Fonte? deJson(Object? json) {
    final m = _mapa(json);
    final url = _texto(m?['url']);
    if (m == null || url == null) return null;
    return Fonte(nome: _texto(m['nome']) ?? url, url: url);
  }
}

List<Fonte> _fontes(Object? v) => [for (final e in _lista(v)) ?Fonte.deJson(e)];

class Indicador {
  const Indicador({
    required this.nome,
    required this.valor,
    this.variacao,
    this.direcao = Direcao.neutra,
    this.contexto,
  });

  final String nome;
  final String valor;
  final String? variacao;
  final Direcao direcao;
  final String? contexto;

  static Indicador? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return Indicador(
      nome: _texto(m['nome']) ?? '—',
      valor: _texto(m['valor']) ?? '—',
      variacao: _texto(m['variacao']),
      direcao: direcaoDe(m['direcao']),
      contexto: _texto(m['contexto']),
    );
  }
}

class Termometro {
  const Termometro({
    this.positiva = 0,
    this.mista = 0,
    this.neutra = 0,
    this.negativa = 0,
  });

  final int positiva;
  final int mista;
  final int neutra;
  final int negativa;

  int get total => positiva + mista + neutra + negativa;

  int de(Leitura l) => switch (l) {
    Leitura.positiva => positiva,
    Leitura.mista => mista,
    Leitura.neutra => neutra,
    Leitura.negativa => negativa,
  };

  static Termometro deJson(Map<String, Object?> m) => Termometro(
    positiva: _naoNegativo(m['positiva']),
    mista: _naoNegativo(m['mista']),
    neutra: _naoNegativo(m['neutra']),
    negativa: _naoNegativo(m['negativa']),
  );

  static Termometro contar(Iterable<Leitura> leituras) {
    final c = {for (final l in Leitura.values) l: 0};
    for (final l in leituras) {
      c[l] = c[l]! + 1;
    }
    return Termometro(
      positiva: c[Leitura.positiva]!,
      mista: c[Leitura.mista]!,
      neutra: c[Leitura.neutra]!,
      negativa: c[Leitura.negativa]!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Termometro &&
      other.positiva == positiva &&
      other.mista == mista &&
      other.neutra == neutra &&
      other.negativa == negativa;

  @override
  int get hashCode => Object.hash(positiva, mista, neutra, negativa);
}

class Preco {
  const Preco({
    this.texto,
    this.valor,
    this.data,
    this.variacao,
    this.direcao = Direcao.neutra,
    this.observacao,
  });

  final String? texto;
  final double? valor;
  final String? data;
  final String? variacao;
  final Direcao direcao;
  final String? observacao;

  static Preco? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return Preco(
      texto: _texto(m['texto']),
      valor: _numero(m['valor']),
      data: _texto(m['data']),
      variacao: _texto(m['variacao']),
      direcao: direcaoDe(m['direcao']),
      observacao: _texto(m['observacao']),
    );
  }
}

class PrecoExterior {
  const PrecoExterior({
    this.ticker,
    this.bolsa,
    this.texto,
    this.valor,
    this.data,
    this.variacao,
    this.direcao = Direcao.neutra,
  });

  final String? ticker;
  final String? bolsa;
  final String? texto;
  final double? valor;
  final String? data;
  final String? variacao;
  final Direcao direcao;

  static PrecoExterior? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return PrecoExterior(
      ticker: _texto(m['ticker']),
      bolsa: _texto(m['bolsa']),
      texto: _texto(m['texto']),
      valor: _numero(m['valor']),
      data: _texto(m['data']),
      variacao: _texto(m['variacao']),
      direcao: direcaoDe(m['direcao']),
    );
  }
}

/// Texto normalizado (minúsculas, sem espaços nas pontas); vazio vira null.
String? _normalizado(Object? v) {
  final t = _chave(v);
  return t == null || t.isEmpty ? null : t;
}

/// Acima disso o número é lixo, não um placar.
const _maxPlacar = 1000000;

/// Votos das casas: compra, neutra e venda.
class Placar {
  const Placar({
    required this.compra,
    required this.neutra,
    required this.venda,
  });

  final int compra;
  final int neutra;
  final int venda;

  int get total => compra + neutra + venda;

  /// Só aceita mapa com as três chaves inteiras >= 0; senão null.
  static Placar? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    final c = _inteiro(m['compra']);
    final n = _inteiro(m['neutra']);
    final v = _inteiro(m['venda']);
    if (c == null ||
        n == null ||
        v == null ||
        c < 0 ||
        n < 0 ||
        v < 0 ||
        c > _maxPlacar ||
        n > _maxPlacar ||
        v > _maxPlacar) {
      return null;
    }
    return Placar(compra: c, neutra: n, venda: v);
  }

  @override
  bool operator ==(Object other) =>
      other is Placar &&
      other.compra == compra &&
      other.neutra == neutra &&
      other.venda == venda;

  @override
  int get hashCode => Object.hash(compra, neutra, venda);
}

class ItemEspecialista {
  const ItemEspecialista({
    this.casa,
    this.recomendacao,
    this.classificacao,
    this.precoAlvo,
    this.potencial,
    this.data,
    this.url,
    this.precoAlvoValor,
    this.moedaAlvo,
    this.prazoAlvo,
    this.motivo,
    this.fraseGuia,
  });

  final String? casa;
  final String? recomendacao;

  /// Texto cru normalizado: `compra`, `neutra`, `venda`, `sem_classificacao`…
  final String? classificacao;
  final String? precoAlvo;
  final String? potencial;
  final String? data;
  final String? url;

  /// Alvo como número (só número JSON; texto vira null).
  final double? precoAlvoValor;
  final String? moedaAlvo;
  final String? prazoAlvo;
  final String? motivo;
  final String? fraseGuia;

  static ItemEspecialista? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return ItemEspecialista(
      casa: _texto(m['casa']),
      recomendacao: _texto(m['recomendacao']),
      classificacao: _normalizado(m['classificacao']),
      precoAlvo: _texto(m['precoAlvo']),
      potencial: _texto(m['potencial']),
      data: _texto(m['data']),
      url: _texto(m['url']),
      precoAlvoValor: _numero(m['precoAlvoValor']),
      moedaAlvo: _texto(m['moedaAlvo']),
      prazoAlvo: _texto(m['prazoAlvo']),
      motivo: _texto(m['motivo']),
      fraseGuia: _texto(m['fraseGuia']),
    );
  }
}

class Especialistas {
  const Especialistas({
    this.resumo,
    this.consenso,
    this.placar,
    this.itens = const [],
    this.precoReferencia,
    this.alvoMedio,
    this.alvoMin,
    this.alvoMax,
    this.potencialMedio,
    this.guiaLeigo,
  });

  final String? resumo;

  /// Texto cru normalizado; a conversão para o enum fica em `destaques.dart`.
  final String? consenso;
  final Placar? placar;
  final List<ItemEspecialista> itens;

  /// Textos prontos do JSON (ex.: "R$ 56,90 em 26/11", "+18,9%").
  final String? precoReferencia;
  final String? alvoMedio;
  final String? alvoMin;
  final String? alvoMax;
  final String? potencialMedio;
  final String? guiaLeigo;

  static Especialistas deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return const Especialistas();
    return Especialistas(
      resumo: _texto(m['resumo']),
      consenso: _normalizado(m['consenso']),
      placar: Placar.deJson(m['placar']),
      itens: [for (final e in _lista(m['itens'])) ?ItemEspecialista.deJson(e)],
      precoReferencia: _texto(m['precoReferencia']),
      alvoMedio: _texto(m['alvoMedio']),
      alvoMin: _texto(m['alvoMin']),
      alvoMax: _texto(m['alvoMax']),
      potencialMedio: _texto(m['potencialMedio']),
      guiaLeigo: _texto(m['guiaLeigo']),
    );
  }
}

class AtivoRelatorio {
  const AtivoRelatorio({
    this.posicao,
    required this.ticker,
    this.empresa,
    this.descricao,
    this.tipoAtivo,
    this.leitura = Leitura.neutra,
    this.explicacao,
    this.dono,
    this.preco,
    this.precoExterior,
    this.noticias,
    this.especialistas = const Especialistas(),
    this.riscos,
    this.fontes = const [],
  });

  final int? posicao;
  final String ticker;
  final String? empresa;
  final String? descricao;
  final String? tipoAtivo;
  final Leitura leitura;
  final String? explicacao;
  final String? dono;
  final Preco? preco;
  final PrecoExterior? precoExterior;
  final String? noticias;
  final Especialistas especialistas;
  final String? riscos;
  final List<Fonte> fontes;

  static AtivoRelatorio? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return AtivoRelatorio(
      posicao: _inteiro(m['posicao']),
      ticker: _texto(m['ticker']) ?? '—',
      empresa: _texto(m['empresa']),
      descricao: _texto(m['descricao']),
      tipoAtivo: _texto(m['tipoAtivo']),
      leitura: leituraDe(m['leitura']),
      explicacao: _texto(m['explicacao']),
      dono: _texto(m['dono']),
      preco: Preco.deJson(m['preco']),
      precoExterior: PrecoExterior.deJson(m['precoExterior']),
      noticias: _texto(m['noticias']),
      especialistas: Especialistas.deJson(m['especialistas']),
      riscos: _texto(m['riscos']),
      fontes: _fontes(m['fontes']),
    );
  }
}

class EducacaoRisco {
  const EducacaoRisco({this.titulo, this.formula, this.exemplo, this.alerta});

  final String? titulo;
  final String? formula;
  final String? exemplo;
  final String? alerta;

  static EducacaoRisco? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return EducacaoRisco(
      titulo: _texto(m['titulo']),
      formula: _texto(m['formula']),
      exemplo: _texto(m['exemplo']),
      alerta: _texto(m['alerta']),
    );
  }
}

class OrigemAtivos {
  const OrigemAtivos({this.planilha, this.aba, this.quantidade});

  final String? planilha;
  final String? aba;
  final int? quantidade;

  static OrigemAtivos? deJson(Object? json) {
    final m = _mapa(json);
    if (m == null) return null;
    return OrigemAtivos(
      planilha: _texto(m['planilha']),
      aba: _texto(m['aba']),
      quantidade: _inteiro(m['quantidade']),
    );
  }
}

class Relatorio {
  const Relatorio({
    required this.schemaVersion,
    this.tipo,
    required this.data,
    this.dataExtenso,
    this.geradoEm,
    this.titulo,
    this.origemAtivos,
    this.avisosTopo = const [],
    this.alertas = const [],
    this.indicadores = const [],
    this.resumo,
    required this.termometro,
    required this.termometroDoJson,
    this.ativos = const [],
    this.educacaoRisco,
    this.aviso,
    this.fontesCenario = const [],
  });

  final int schemaVersion;
  final String? tipo;
  final String data;
  final String? dataExtenso;
  final String? geradoEm;
  final String? titulo;
  final OrigemAtivos? origemAtivos;
  final List<String> avisosTopo;
  final List<String> alertas;
  final List<Indicador> indicadores;
  final String? resumo;

  /// O do JSON quando existe; senão, a contagem pelos ativos.
  final Termometro termometro;
  final bool termometroDoJson;
  final List<AtivoRelatorio> ativos;
  final EducacaoRisco? educacaoRisco;
  final String? aviso;
  final List<Fonte> fontesCenario;

  /// Schema mais novo que o conhecido (1): renderiza mesmo assim, com aviso.
  bool get versaoNova => schemaVersion > 1;

  Termometro get contagemAtivos =>
      Termometro.contar(ativos.map((a) => a.leitura));

  bool get termometroDiverge =>
      termometroDoJson && termometro != contagemAtivos;

  /// [json] precisa ser um objeto; o resto é tolerante. [dataDoArquivo]
  /// (`AAAA-MM-DD`, do nome do arquivo) vale quando `data` falta ou é inválida.
  static Relatorio deJson(Object? json, {String? dataDoArquivo}) {
    final m = _mapa(json);
    if (m == null) {
      throw const FormatException('Relatório: o JSON não é um objeto');
    }
    // Sem posição vai para o fim, na ordem original (ordenação estável).
    final ativos = ordenadoCom(
      [for (final e in _lista(m['ativos'])) ?AtivoRelatorio.deJson(e)],
      (a, b) {
        final pa = a.posicao, pb = b.posicao;
        if (pa == null || pb == null) {
          return pa == pb ? 0 : (pa == null ? 1 : -1);
        }
        return pa.compareTo(pb);
      },
    );
    var tj = _mapa(m['termometro']);
    // Sem nenhuma das quatro chaves numéricas, vale como ausente.
    if (tj != null &&
        !Leitura.values.any((l) => _inteiro(tj![l.name]) != null)) {
      tj = null;
    }
    return Relatorio(
      schemaVersion: _inteiro(m['schemaVersion']) ?? 1,
      tipo: _texto(m['tipo']),
      data: _dataIso(m['data']) ?? dataDoArquivo ?? '',
      dataExtenso: _texto(m['dataExtenso']),
      geradoEm: _texto(m['geradoEm']),
      titulo: _texto(m['titulo']),
      origemAtivos: OrigemAtivos.deJson(m['origemAtivos']),
      avisosTopo: _textos(m['avisosTopo']),
      alertas: _textos(m['alertas']),
      indicadores: [
        for (final e in _lista(m['indicadores'])) ?Indicador.deJson(e),
      ],
      resumo: _texto(m['resumo']),
      termometro: tj != null
          ? Termometro.deJson(tj)
          : Termometro.contar(ativos.map((a) => a.leitura)),
      termometroDoJson: tj != null,
      ativos: ativos,
      educacaoRisco: EducacaoRisco.deJson(m['educacaoRisco']),
      aviso: _texto(m['aviso']),
      fontesCenario: _fontes(m['fontesCenario']),
    );
  }
}
