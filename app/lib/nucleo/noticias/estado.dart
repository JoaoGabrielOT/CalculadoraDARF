// Notícias: mesclagem, estado local e textos de notificação
// (noticias.py:17-30, 144-160, 178-195, 209-314).

import '../ambiente.dart';
import '../armazenamento.dart';
import '../compat/json_python.dart';
import '../compat/ordenacao.dart';
import '../modelos/com_mod.dart';
import 'texto.dart';

const maxDetalhes = 40; // matérias mais recentes que ganham prévia
const tentarDetalheDeNovo = 6 * 3600;
const intervalo = 10 * 60; // segundos entre buscas automáticas
const janelaNotificacao = 24 * 3600; // só notifica o publicado nas últimas 24 h
const maxItens = 150;
const maxVistos = 3000;
const maxNotificacoes = 3; // acima disso, uma notificação de resumo
const validadeLogoAusente = 7 * 86400;

const _arquivo = 'noticias.json';

/// Uma matéria do Google Notícias, já com os tickers e temas.
class Noticia {
  Noticia({
    required this.id,
    required this.titulo,
    required this.link,
    required this.fonte,
    required this.fonteUrl,
    required this.data,
    required this.tickers,
    required this.temas,
  });

  factory Noticia.fromJson(Map<String, Object?> json) {
    String texto(Object? v) => v is String ? v : '';
    List<String> textos(Object? v) => [
      if (v is List)
        for (final t in v)
          if (t is String) t,
    ];
    return Noticia(
      id: texto(json['id']),
      titulo: texto(json['titulo']),
      link: texto(json['link']),
      fonte: texto(json['fonte']),
      fonteUrl: texto(json['fonte_url']),
      data: lerDouble(json['data']),
      tickers: textos(json['tickers']),
      temas: textos(json['temas']),
    );
  }

  final String id;
  final String titulo;
  final String link;
  final String fonte;
  final String fonteUrl;
  final double data;
  List<String> tickers;
  List<String> temas;

  Map<String, Object?> toJson() => {
    'id': id,
    'titulo': titulo,
    'link': link,
    'fonte': fonte,
    'fonte_url': fonteUrl,
    'data': data,
    'tickers': tickers,
    'temas': temas,
  };

  Noticia _copia() => Noticia(
    id: id,
    titulo: titulo,
    link: link,
    fonte: fonte,
    fonteUrl: fonteUrl,
    data: data,
    tickers: [...tickers],
    temas: [...temas],
  );
}

/// `noticias.json`: matérias, o que já foi visto e o que foi lido.
class EstadoNoticias {
  EstadoNoticias({
    List<Noticia>? itens,
    Map<String, double>? vistos,
    List<String>? conhecidos,
    this.hora = 0,
    this.lidasAte = 0,
    Map<String, String>? erros,
  }) : itens = itens ?? [],
       vistos = vistos ?? {},
       conhecidos = conhecidos ?? [],
       erros = erros ?? {};

  factory EstadoNoticias.fromJson(Map<String, Object?> json) => EstadoNoticias(
    itens: [for (final i in lerLista(json['itens'])) Noticia.fromJson(i)],
    vistos: lerMapaDouble(json['vistos']),
    conhecidos: [
      if (json['conhecidos'] case final List<Object?> l)
        for (final t in l)
          if (t is String) t,
    ],
    hora: lerDouble(json['hora']),
    lidasAte: lerDouble(json['lidas_ate']),
    erros: lerMapaTexto(json['erros']),
  );

  /// Matérias mais recentes primeiro.
  List<Noticia> itens;

  /// id -> hora em que foi visto (evita notificar duas vezes).
  Map<String, double> vistos;

  /// Tickers cujas notícias antigas já foram marcadas como vistas.
  List<String> conhecidos;

  /// Hora da última busca.
  double hora;

  /// Notícias vistas até aqui não contam como novas na aba.
  double lidasAte;

  /// ticker -> erro da última busca.
  Map<String, String> erros;

  Map<String, Object?> toJson() => {
    'itens': [for (final i in itens) i.toJson()],
    'vistos': vistos,
    'conhecidos': conhecidos,
    'hora': hora,
    'lidas_ate': lidasAte,
    'erros': erros,
  };
}

/// Junta as notícias de vários ativos: a mesma matéria aparece uma vez, com
/// todos os tickers.
List<Noticia> mesclar(List<List<Noticia>> listas) {
  final porChave = <String, Noticia>{};
  for (final itens in listas) {
    for (final it in itens) {
      final k = chaveTitulo(it.titulo);
      final atual = porChave[k];
      if (atual == null) {
        porChave[k] = it._copia();
      } else {
        for (final t in it.tickers) {
          if (!atual.tickers.contains(t)) atual.tickers.add(t);
        }
      }
    }
  }
  final ordem = ordenadoPor(porChave.values, (i) => [i.data], reverso: true);
  return ordem.take(maxItens).toList();
}

/// `ler_estado`: arquivo ausente ou ilegível dá o estado vazio.
EstadoNoticias lerEstado(Armazenamento a) {
  final texto = a.ler(_arquivo);
  if (texto != null) {
    try {
      final json = jsonPythonDecode(texto);
      if (json is Map) return EstadoNoticias.fromJson(lerMapa(json));
    } on FormatException {
      // JSON inválido: começa vazio
    }
  }
  return EstadoNoticias();
}

/// `gravar_estado`: guarda só os [maxVistos] vistos mais recentes.
void gravarEstado(Armazenamento a, EstadoNoticias d) {
  if (d.vistos.length > maxVistos) {
    final ordem = ordenadoPor(d.vistos.entries, (e) => [e.value]);
    d.vistos = {
      for (final e in ordem.sublist(ordem.length - maxVistos)) e.key: e.value,
    };
  }
  a.gravar(_arquivo, jsonPython(d.toJson()));
}

/// Parte sem rede de `atualizar`: incorpora as [listas] buscadas (uma por ativo
/// sem erro, na ordem de [tickers]) ao estado [d] e devolve as novas relevantes.
/// Uma notícia relevante é nova quando ainda não foi vista, tem algum tema
/// importante e saiu nas últimas 24 h. Na primeira busca de um ativo, o que já
/// existe é marcado como visto sem notificar.
List<Noticia> aplicarBusca(
  EstadoNoticias d,
  List<(String, String)> tickers,
  List<List<Noticia>> listas,
  Map<String, String> erros,
  double agora,
) {
  final validos = {for (final (t, _) in tickers) t};
  final buscados = validos.difference(erros.keys.toSet());
  final antigos = <Noticia>[];
  for (final i in d.itens) {
    final copia = i._copia()
      ..tickers = [
        for (final t in i.tickers)
          if (validos.contains(t)) t,
      ];
    if (copia.tickers.isNotEmpty &&
        !copia.tickers.any((t) => buscados.contains(t))) {
      antigos.add(copia);
    }
  }
  final itens = mesclar([...listas, antigos]);
  final conhecidos = d.conhecidos.toSet();
  final novas = <Noticia>[];
  for (final it in itens) {
    if (d.vistos.containsKey(it.id)) continue;
    d.vistos[it.id] = agora;
    final estreia = !it.tickers.any(conhecidos.contains);
    if (it.temas.isNotEmpty &&
        !estreia &&
        agora - it.data <= janelaNotificacao) {
      novas.add(it);
    }
  }
  d.conhecidos = ordenadoPor({...conhecidos, ...buscados}, (t) => [t]);
  d.itens = itens;
  d.hora = agora;
  d.erros = erros;
  if (d.lidasAte == 0) d.lidasAte = agora;
  return novas;
}

double _agoraOuRelogio(double? agora) =>
    (agora == null || agora == 0) ? ambiente.agora() : agora;

bool precisaAtualizar(EstadoNoticias d, {double? agora}) =>
    _agoraOuRelogio(agora) - d.hora >= intervalo;

/// Chegou depois da última vez que a aba de notícias foi aberta.
bool ehNova(EstadoNoticias d, Noticia item) =>
    (d.vistos[item.id] ?? 0) > d.lidasAte;

int naoLidas(EstadoNoticias d) => d.itens.where((i) => ehNova(d, i)).length;

EstadoNoticias marcarLidas(Armazenamento a, {double? agora}) {
  final d = lerEstado(a);
  d.lidasAte = _agoraOuRelogio(agora);
  gravarEstado(a, d);
  return d;
}

/// (título, texto, link) para notificar; muitas novidades viram um resumo só.
List<(String, String, String)> textosNotificacao(List<Noticia> novas) {
  if (novas.length <= maxNotificacoes) {
    return [
      for (final i in novas)
        (
          '${i.tickers.take(3).join(', ')} · ${i.temas[0]}',
          i.fonte.isNotEmpty ? '${i.titulo} (${i.fonte})' : i.titulo,
          i.link,
        ),
    ];
  }
  final tickers = <String>[];
  for (final i in novas) {
    final novos = [
      for (final t in i.tickers)
        if (!tickers.contains(t)) t,
    ];
    tickers.addAll(novos);
  }
  return [
    (
      '${novas.length} notícias relevantes',
      'Sobre ${tickers.take(6).join(', ')}${tickers.length > 6 ? '…' : ''}',
      '',
    ),
  ];
}
