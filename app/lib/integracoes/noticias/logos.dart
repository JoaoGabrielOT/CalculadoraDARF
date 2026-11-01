// Logos das empresas e favicons das fontes, com cache e ausência lembrada por
// 7 dias (noticias.py:473-511; SVG da brapi: android/main.py:140-149).

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../nucleo/ambiente.dart';
import '../../nucleo/erros.dart';
import '../../nucleo/noticias/estado.dart';
import '../../nucleo/noticias/texto.dart';
import '../cache_binario.dart';
import '../http/cliente.dart';
import 'imagens.dart';

const _assinaturaPng = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

bool _ehPng(Uint8List b) {
  if (b.length < _assinaturaPng.length) return false;
  for (var i = 0; i < _assinaturaPng.length; i++) {
    if (b[i] != _assinaturaPng[i]) return false;
  }
  return true;
}

/// `b"<svg" in r.content`.
bool _ehSvg(Uint8List b) {
  final alvo = ascii.encode('<svg');
  for (var i = 0; i + alvo.length <= b.length; i++) {
    var igual = true;
    for (var j = 0; j < alvo.length; j++) {
      if (b[i + j] != alvo[j]) {
        igual = false;
        break;
      }
    }
    if (igual) return true;
  }
  return false;
}

class Logos {
  /// [http] já vem com o User-Agent de notícias e o limite de 15 s.
  Logos({required ClienteHttp http, required CacheBinario cache})
    : // Parâmetro nomeado não pode ser privado.
      // ignore: prefer_initializing_formals
      _http = http,
      // ignore: prefer_initializing_formals
      _cache = cache;

  final ClienteHttp _http;
  final CacheBinario _cache;

  /// `baixar_imagem`: do cache; ausência recente → `null`; só grava `.falta`
  /// quando o servidor respondeu 403, 404 ou 200 inválido.
  Future<Uint8List?> _baixar(
    String url,
    String nome,
    String nomeFalta,
    bool Function(Uint8List) valido,
  ) async {
    final guardado = await _cache.ler(nome);
    if (guardado != null) return guardado;
    final desde = await _cache.modificadoEm(nomeFalta);
    if (desde != null &&
        ambiente.agora() - desde.microsecondsSinceEpoch / 1000000 <
            validadeLogoAusente) {
      return null;
    }
    final http.Response resposta;
    try {
      resposta = await _http.enviar('GET', Uri.parse(url));
    } on ErroConexao {
      return null; // sem rede: tenta de novo na próxima vez
    }
    final status = resposta.statusCode;
    if (status == 200 && valido(resposta.bodyBytes)) {
      await _cache.gravar(nome, resposta.bodyBytes);
      await _cache.apagar(nomeFalta);
      return resposta.bodyBytes;
    }
    if (status == 403 || status == 404 || status == 200) {
      await _cache.gravar(nomeFalta, const []);
    }
    return null;
  }

  /// PNG da logo do ativo: primeiro o do ticker, depois o da raiz.
  Future<Uint8List?> logoPng(String ticker) async {
    for (final url in urlsLogo(ticker).$1) {
      final nome = url.substring(url.lastIndexOf('/') + 1);
      final base = nome.substring(0, nome.length - 4); // with_suffix('.falta')
      final b = await _baixar(url, 'logos/$nome', 'logos/$base.falta', _ehPng);
      if (b != null && b.isNotEmpty) return b;
    }
    return null;
  }

  Future<Uint8List?> logoSvg(String ticker) => _baixar(
    urlsLogo(ticker).$2,
    'logos/svg/$ticker.svg',
    'logos/svg/$ticker.falta',
    _ehSvg,
  );

  Future<Uint8List?> favicon(Noticia item) {
    final d = dominio(item.fonteUrl);
    if (d.isEmpty) return Future.value();
    final nome = nomeArquivoFavicon(d);
    return _baixar(
      urlFavicon(item),
      'logos/fontes/$nome',
      'logos/fontes/${nome.substring(0, nome.length - 4)}.falta',
      _ehPng,
    );
  }
}
