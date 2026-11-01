import 'dart:io';
import 'dart:typed_data';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../apoio/cliente_falso.dart';

final _cabecalhoPng = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
final _png = [..._cabecalhoPng, 1, 2, 3];

Noticia _noticia(String fonteUrl) => Noticia(
  id: 'n1',
  titulo: 'Título da matéria sobre o mercado',
  link: 'https://site.com/n1',
  fonte: 'Valor',
  fonteUrl: fonteUrl,
  data: 1760000000,
  tickers: [],
  temas: [],
);

class _CacheQuebrado extends CacheBinarioMemoria {
  @override
  Future<Uint8List?> ler(String nome) =>
      throw const FileSystemException('disco cheio');
}

void main() {
  late CacheBinarioMemoria cache;
  setUp(() {
    ambiente = Ambiente.fixo();
    cache = CacheBinarioMemoria(
      relogio: () => DateTime.fromMicrosecondsSinceEpoch(
        (ambiente.agora() * 1000000).round(),
      ),
    );
  });
  tearDown(() => ambiente = Ambiente.sistema());

  Logos logos(ClienteFalso f) =>
      Logos(http: Logos.clientePadrao(f), cache: cache);

  test('clientePadrao: UA de notícias e 15 s; clienteNavegador: UA do navegador e 20 s', () async {
    final falso = ClienteFalso.fila([RespostaFalsa(200), RespostaFalsa(200)]);
    final padrao = Logos.clientePadrao(falso);
    expect(padrao.tempoLimite, const Duration(seconds: 15));
    await padrao.enviar('GET', Uri.parse('https://x.com/a'));
    expect(falso.pedidos.last.cabecalhos['user-agent'], uaNoticias);

    final navegador = Logos.clienteNavegador(falso);
    expect(navegador.tempoLimite, const Duration(seconds: 20));
    await navegador.enviar('GET', Uri.parse('https://x.com/a'));
    expect(
      falso.pedidos.last.cabecalhos['user-agent'],
      uaNavegador['User-Agent'],
    );
    expect(falso.pedidos.last.cabecalhos['accept-language'], 'pt-BR,pt;q=0.9');
  });

  // Os nomes vêm das URLs do núcleo.
  String nomeUrl(String u) => u.substring(u.lastIndexOf('/') + 1);
  String falta(String png) => 'logos/${png.substring(0, png.length - 4)}.falta';
  final (urlsPng, _) = urlsLogo('PETR4');
  final nomePetr4 = nomeUrl(urlsPng[0]);
  final nomePetr = nomeUrl(urlsPng[1]);
  final falta4 = falta(nomePetr4);

  test('logoPng: PNG válido grava e apaga .falta', () async {
    // ausência de 8 dias atrás: já venceu
    ambiente = Ambiente.fixo(agora: 1761000000.123 - 8 * 86400);
    await cache.gravar(falta4, []);
    ambiente = Ambiente.fixo();
    final falso = ClienteFalso.fila([RespostaFalsa(200, bytes: _png)]);
    final r = await logos(falso).logoPng('PETR4');
    expect(r, _png);
    expect(falso.pedidos.single.url.toString(), urlsPng[0]);
    expect(falso.pedidos.single.cabecalhos['user-agent'], uaNoticias);
    expect(await cache.ler('logos/$nomePetr4'), _png);
    expect(await cache.modificadoEm(falta4), isNull);
    // segunda chamada: do cache, sem rede
    expect(await logos(falso).logoPng('PETR4'), _png);
    expect(falso.pedidos, hasLength(1));
  });

  for (final (nome, resposta) in <(String, RespostaFalsa Function())>[
    ('404', () => RespostaFalsa(404)),
    ('403', () => RespostaFalsa(403)),
    ('200 não-PNG', () => RespostaFalsa(200, texto: '<html>')),
  ]) {
    test(
      'logoPng: $nome grava .falta e não tenta de novo por 7 dias',
      () async {
        final falso = ClienteFalso.fila([resposta(), resposta()]);
        final l = logos(falso);
        expect(await l.logoPng('PETR4'), isNull);
        expect(falso.pedidos, hasLength(2));
        expect(await cache.ler(falta4), isEmpty);
        expect(await cache.ler('logos/$nomePetr4'), isNull);
        // 6 dias depois: nenhum pedido novo
        ambiente = Ambiente.fixo(agora: 1761000000.123 + 6 * 86400);
        expect(await l.logoPng('PETR4'), isNull);
        expect(falso.pedidos, hasLength(2));
      },
    );
  }

  test('logoPng: depois de 7 dias tenta de novo', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(404),
      RespostaFalsa(404),
      RespostaFalsa(200, bytes: _png),
    ]);
    final l = logos(falso);
    expect(await l.logoPng('PETR4'), isNull);
    ambiente = Ambiente.fixo(agora: 1761000000.123 + 7 * 86400 + 1);
    expect(await l.logoPng('PETR4'), _png);
    expect(falso.pedidos, hasLength(3));
    expect(falso.pedidos.last.url.toString(), urlsPng[0]);
  });

  test('logoPng: sem rede e 500 não gravam .falta', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(0, erro: http.ClientException('sem rede')),
      RespostaFalsa(500),
    ]);
    expect(await logos(falso).logoPng('PETR4'), isNull);
    expect(falso.pedidos, hasLength(2));
    expect(await cache.modificadoEm(falta4), isNull);
    expect(await cache.modificadoEm(falta(nomePetr)), isNull);
  });

  test('logoPng tenta PETR4 e depois PETR', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(404),
      RespostaFalsa(200, bytes: _png),
    ]);
    expect(await logos(falso).logoPng('PETR4'), _png);
    expect(falso.pedidos.map((p) => p.url.toString()), urlsPng);
    expect(await cache.ler('logos/$nomePetr'), _png);
    expect(await cache.modificadoEm(falta4), isNotNull);
  });

  test('logoPng sem raiz diferente faz um só pedido', () async {
    final falso = ClienteFalso.fila([RespostaFalsa(404)]);
    expect(await logos(falso).logoPng('ABCD'), isNull);
    expect(falso.pedidos, hasLength(1));
  });

  test('logoSvg e favicon nos caminhos do cache', () async {
    final svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'.codeUnits;
    final fav = [..._cabecalhoPng, 9];
    final falso = ClienteFalso.fila([
      RespostaFalsa(200, bytes: svg),
      RespostaFalsa(200, bytes: fav),
      RespostaFalsa(404),
      RespostaFalsa(404),
    ]);
    final l = logos(falso);
    expect(await l.logoSvg('PETR4'), svg);
    expect(falso.pedidos[0].url.toString(), urlsLogo('PETR4').$2);
    expect(await cache.ler('logos/svg/PETR4.svg'), svg);

    final n = _noticia('https://valor.globo.com:8080/x');
    expect(await l.favicon(n), fav);
    expect(falso.pedidos[1].url.toString(), urlFavicon(n));
    expect(await cache.ler('logos/fontes/valor.globo.com_8080.png'), fav);

    expect(await l.logoSvg('VALE3'), isNull);
    expect(await cache.ler('logos/svg/VALE3.falta'), isEmpty);
    expect(await l.logoSvg('VALE3'), isNull);
    expect(falso.pedidos, hasLength(3));

    expect(await l.favicon(_noticia('https://sem.png/x')), isNull);
    expect(await cache.ler('logos/fontes/sem.png.png'), isNull);
    expect(await cache.ler('logos/fontes/sem.png.falta'), isEmpty);
  });

  test('exceção qualquer vira sem logo (cache que falha)', () async {
    final falso = ClienteFalso.fila([]);
    final l = Logos(http: ClienteHttp(falso), cache: _CacheQuebrado());
    expect(await l.logoPng('PETR4'), isNull);
    expect(await l.logoSvg('PETR4'), isNull);
    expect(falso.pedidos, isEmpty);
  });

  test('favicon sem domínio → null sem pedido', () async {
    final falso = ClienteFalso.fila([]);
    expect(await logos(falso).favicon(_noticia('')), isNull);
    expect(falso.pedidos, isEmpty);
  });
}
