// Fumaça com `executarEmIsolate` de verdade: as tarefas enviadas ao isolate não
// podem capturar objetos que não atravessam a fronteira (a falha só aparece
// com o executor real; os demais testes usam `executarDireto`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'apoio/cliente_falso.dart';

const _titulo = 'Petrobras anuncia dividendos extraordinários de bilhões';

String _rss() =>
    '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>'
    '<title>x</title><item><title>$_titulo - Valor</title>'
    '<link>https://news.google.com/rss/articles/X1</link>'
    '<pubDate>Mon, 20 Oct 2025 10:00:00 GMT</pubDate>'
    '<source url="https://valor.globo.com">Valor</source></item>'
    '</channel></rss>';

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: 1761000000.0));
  tearDown(() => ambiente = Ambiente.sistema());

  test('decodificarJson acima de 64 KB no isolate real', () async {
    final lista = List.filled(limiteJsonDireto, 1);
    final corpo = utf8.encode(jsonEncode({'a': lista, 'b': 'ç'}));
    expect(corpo.length, greaterThan(limiteJsonDireto));
    final r = await decodificarJson(corpo, executarEmIsolate) as Map;
    expect((r['a'] as List).length, limiteJsonDireto);
    expect(r['b'], 'ç');
  });

  test('decodificarJson inválido acima de 64 KB → FormatException', () async {
    final corpo = utf8.encode('<html>${'x' * limiteJsonDireto}</html>');
    await expectLater(
      decodificarJson(corpo, executarEmIsolate),
      throwsFormatException,
    );
  });

  test('buscarTicker (lerRss) no isolate real', () async {
    final falso = ClienteFalso.fila([RespostaFalsa(200, texto: _rss())]);
    final servico = ServicoNoticias(
      cliente: falso,
      armazenamento: ArmazenamentoMemoria(),
    );
    final itens = await servico.buscarTicker('PETR4', nome: 'Petrobras');
    expect(itens, hasLength(1));
    expect(itens.single.titulo, startsWith('Petrobras anuncia'));
  });

  test('detalhar (lerPrevia) no isolate real', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(
        200,
        texto:
            '<html><head><meta property="og:image" content="/img/a.jpg">'
            '<meta name="description" content="Resumo a"></head></html>',
        cabecalhos: {'content-type': 'text/html; charset=utf-8'},
      ),
    ]);
    final servico = ServicoNoticias(
      cliente: falso,
      armazenamento: ArmazenamentoMemoria(),
    );
    final det = await servico.detalhar(
      Noticia(
        id: 'a',
        titulo: 'Título da matéria a sobre o mercado',
        link: 'https://site.com/a',
        fonte: 'Valor',
        fonteUrl: '',
        data: 1760000000,
        tickers: ['PETR4'],
        temas: [],
      ),
    );
    expect(det.erro, anyOf(isNull, isEmpty));
    expect(det.resumo, 'Resumo a');
    expect(det.img, 'https://site.com/img/a.jpg');
  });

  test('baixarImagemNoticia (reduzirParaJpeg) no isolate real', () async {
    final imagem = img.Image(width: 1200, height: 800);
    img.fill(imagem, color: img.ColorRgb8(10, 120, 200));
    final png = img.encodePng(imagem);
    final falso = ClienteFalso.fila([RespostaFalsa(200, bytes: png)]);
    final cache = CacheBinarioMemoria();
    const url = 'https://exemplo.com/a.png';
    final nome = await baixarImagemNoticia(ClienteHttp(falso), cache, url);
    expect(nome, nomeImagemNoticia(url));
    final Uint8List jpeg = (await cache.ler(nome!))!;
    expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
    final lida = img.decodeJpg(jpeg)!;
    expect((lida.width, lida.height), (900, 600));
  });
}
