// Serviço de notícias (noticias.py:198-204, 237-277, 340-430): busca por
// ticker, decodificação do link, prévias das matérias e o ciclo de `atualizar`.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../nucleo/ambiente.dart';
import '../../nucleo/armazenamento.dart';
import '../../nucleo/noticias/estado.dart';
import '../executor.dart';
import '../http/cliente.dart';
import '../http/erros.dart';
import '../http/semaforo.dart';
import 'google_news.dart';
import 'html.dart';
import 'previas.dart';
import 'rss.dart';

const _simultaneas = 4;

/// `str(e)[:n]`, contando pontos de código.
String _cortar(String s, int n) {
  final r = s.runes;
  return r.length <= n ? s : String.fromCharCodes(r.take(n));
}

// Tarefas para o isolate: ficam fora da classe para não capturar `this`.
FutureOr<List<Noticia>> Function() _tarefaRss(
  List<int> xml,
  String ticker,
  String nome,
  double agora,
) =>
    () => lerRss(xml, ticker, nome: nome, agora: agora);

FutureOr<({String img, String resumo})> Function() _tarefaPrevia(
  String html,
  String url,
) =>
    () => lerPrevia(html, url);

/// Texto da resposta: charset do cabeçalho `Content-Type`, senão UTF-8
/// tolerante (também para charset desconhecido).
String _decodificarCorpo(List<int> bytes, Map<String, String> cabecalhos) {
  String? tipo;
  for (final e in cabecalhos.entries) {
    if (e.key.toLowerCase() == 'content-type') tipo = e.value;
  }
  final charset = tipo == null
      ? null
      : RegExp(
          r'charset\s*=\s*"?([^\s;"]+)',
          caseSensitive: false,
        ).firstMatch(tipo)?.group(1);
  final codec = charset == null ? null : Encoding.getByName(charset);
  if (codec != null && codec != utf8) return codec.decode(bytes);
  return utf8.decode(bytes, allowMalformed: true);
}

class ServicoNoticias {
  ServicoNoticias({
    required http.Client cliente,
    required Armazenamento armazenamento,
    Executar executar = executarEmIsolate,
  }) : // Parâmetro nomeado não pode ser privado.
       // ignore: prefer_initializing_formals
       _armazenamento = armazenamento,
       // ignore: prefer_initializing_formals
       _executar = executar,
       _rss = ClienteHttp(
         cliente,
         userAgent: uaNoticias,
         tempoLimite: const Duration(seconds: 20),
         maxSimultaneas: _simultaneas,
       ),
       _paginas = ClienteHttp(
         cliente,
         userAgent: uaNavegador['User-Agent'],
         cabecalhos: {'Accept-Language': uaNavegador['Accept-Language']!},
         tempoLimite: const Duration(seconds: 20),
       );

  final Armazenamento _armazenamento;
  final Executar _executar;
  final ClienteHttp _rss;
  final ClienteHttp _paginas;

  /// Vagas dos pedidos de páginas (`abrir` não tem limite próprio).
  final _vagasPaginas = Semaforo(_simultaneas);

  /// `buscar_ticker`: 429 vira [LimiteConsultas]; outro status ≥ 400, [ErroHttp].
  Future<List<Noticia>> buscarTicker(String ticker, {String nome = ''}) async {
    final url = urlBusca(ticker, nome: nome);
    final r = await _rss.enviar('GET', url);
    conferirStatus(r.statusCode, url, motivo: r.reasonPhrase);
    return _executar(_tarefaRss(r.bodyBytes, ticker, nome, ambiente.agora()));
  }

  /// Busca as notícias de todos os ativos do radar e grava o estado. Devolve
  /// (itens, novas relevantes). Um ativo com erro não impede os outros.
  Future<(List<Noticia>, List<Noticia>)> atualizar(
    List<(String, String)> radar, {
    double? agora,
    bool detalhes = false,
  }) async {
    final instante = (agora == null || agora == 0) ? ambiente.agora() : agora;
    final vagas = Semaforo(_simultaneas);
    final resultados = await Future.wait([
      for (final (t, nome) in radar)
        vagas.usar<(List<Noticia>?, String?)>(() async {
          try {
            return (await buscarTicker(t, nome: nome), null);
          } catch (e) {
            return (null, _cortar(e.toString(), 200));
          }
        }),
    ]);
    final listas = <List<Noticia>>[];
    final erros = <String, String>{};
    for (final (i, (lista, erro)) in resultados.indexed) {
      if (erro != null) {
        erros[radar[i].$1] = erro;
      } else {
        listas.add(lista!);
      }
    }
    // Sem `await` daqui até a gravação: ninguém muda o estado no meio.
    final d = lerEstado(_armazenamento);
    final novas = aplicarBusca(d, radar, listas, erros, instante);
    gravarEstado(_armazenamento, d);
    if (detalhes) {
      try {
        await enriquecer(d.itens);
      } catch (_) {
        // a prévia é um extra: a busca já está gravada
      }
    }
    return (d.itens, novas);
  }

  /// `decodificar_link`: endereço real da matéria; o próprio link se não for do
  /// Google Notícias; `null` se a página não traz a assinatura ou o endereço
  /// devolvido não é http.
  Future<String?> decodificarLink(String link) async {
    final gid = idArtigo(link);
    if (gid == null) return link;
    // Sem conferir o status da página, como o Python. O tempo limite é total
    // (no Python é por leitura), por isso maior que o das demais chamadas.
    final pagina = await _vagasPaginas.usar(
      () => _paginas.enviar(
        'GET',
        Uri.parse('https://news.google.com/rss/articles/$gid'),
        tempoLimite: const Duration(seconds: 60),
      ),
    );
    final assinatura = assinaturaArtigo(
      _decodificarCorpo(pagina.bodyBytes, pagina.headers),
    );
    if (assinatura == null) return null;
    final corpo = corpoDecodificacao(gid, assinatura.ts, assinatura.sg);
    final url = Uri.parse(urlDecodificar);
    final r = await _vagasPaginas.usar(
      () => _paginas.enviar(
        'POST',
        url,
        // `quote_plus` do `urlencode` do requests
        corpo: 'f.req=${quotePython(corpo, seguro: ' ').replaceAll(' ', '+')}',
        cabecalhos: const {
          'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        },
      ),
    );
    // O Python chama `raise_for_status` direto: o 429 também é erro HTTP comum.
    if (r.statusCode == 429) {
      throw ErroHttp(
        429,
        '429 Client Error: ${r.reasonPhrase ?? ''} for url: $url',
      );
    }
    conferirStatus(r.statusCode, url, motivo: r.reasonPhrase);
    return urlDaRespostaBatch(_decodificarCorpo(r.bodyBytes, r.headers));
  }

  /// `baixar_pagina`: lê só o começo da página (até o fim do `<head>`).
  /// Devolve (html, url final); página que não é HTML dá texto vazio.
  Future<(String, String)> baixarPagina(String url, {int limite = 600000}) {
    return _vagasPaginas.usar(() async {
      final r = await _paginas.abrir('GET', Uri.parse(url));
      Future<void> descartar() => r.blocos.listen((_) {}).cancel();
      try {
        conferirStatus(r.status, r.urlFinal, motivo: r.motivo);
      } catch (_) {
        await descartar();
        rethrow;
      }
      final tipo = r.cabecalhos.entries
          .where((e) => e.key.toLowerCase() == 'content-type')
          .map((e) => e.value)
          .firstOrNull;
      if (!(tipo ?? 'html').contains('html')) {
        await descartar();
        return ('', r.urlFinal.toString());
      }
      final bytes = <int>[];
      // Fim do <head> também quando ele cai na emenda de dois blocos.
      const fim = [0x3c, 0x2f, 0x68, 0x65, 0x61, 0x64, 0x3e]; // </head>
      var cauda = <int>[];
      await for (final bloco in r.blocos) {
        bytes.addAll(bloco);
        final janela = [...cauda, ...bloco];
        if (bytes.length >= limite || _contem(janela, fim)) break;
        cauda = janela.length < fim.length - 1
            ? janela
            : janela.sublist(janela.length - (fim.length - 1));
      }
      return (_decodificarCorpo(bytes, r.cabecalhos), r.urlFinal.toString());
    });
  }

  static bool _contem(List<int> texto, List<int> trecho) {
    for (var i = 0; i + trecho.length <= texto.length; i++) {
      var igual = true;
      for (var j = 0; j < trecho.length && igual; j++) {
        igual = texto[i + j] == trecho[j];
      }
      if (igual) return true;
    }
    return false;
  }

  /// `detalhar`: prévia da matéria; em falha guarda o erro para tentar de novo
  /// depois.
  Future<DetalheNoticia> detalhar(Noticia item) async {
    final det = DetalheNoticia(hora: ambiente.agora());
    try {
      final url = await decodificarLink(item.link);
      if (url == null || url.isEmpty) {
        det.erro = 'link';
        return det;
      }
      det.url = url;
      final (html, finalUrl) = await baixarPagina(url);
      det.url = finalUrl.isEmpty ? url : finalUrl;
      final previa = await _executar(_tarefaPrevia(html, det.url));
      det.img = previa.img;
      det.resumo = previa.resumo;
    } catch (e) {
      det.erro = _cortar(e.toString(), 120);
    }
    return det;
  }

  /// `enriquecer`: busca a prévia das [limite] matérias mais recentes que ainda
  /// não têm (ou cuja tentativa falhou há mais de 6 h). Devolve `true` se algo
  /// mudou.
  Future<bool> enriquecer(
    List<Noticia> itens, {
    int limite = maxDetalhes,
  }) async {
    final det = lerDetalhes(_armazenamento);
    final agora = ambiente.agora();
    bool precisa(Noticia i) {
      final d = det[i.id];
      return d == null ||
          ((d.erro ?? '').isNotEmpty && agora - d.hora > tentarDetalheDeNovo);
    }

    final faltam = itens.take(limite).where(precisa).toList();
    if (faltam.isEmpty) return false;
    final vagas = Semaforo(_simultaneas);
    final feitos = await Future.wait([
      for (final i in faltam) vagas.usar(() => detalhar(i)),
    ]);
    for (final (n, i) in faltam.indexed) {
      det[i.id] = feitos[n];
    }
    gravarDetalhes(_armazenamento, det, manter: {for (final i in itens) i.id});
    return true;
  }
}
