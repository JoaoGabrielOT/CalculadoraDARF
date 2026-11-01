import 'dart:typed_data';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../nucleo/apoio/referencias.dart';
import '../apoio/cliente_falso.dart';

Uint8List _png(int l, int a, {bool alfa = false}) {
  final i = img.Image(width: l, height: a, numChannels: alfa ? 4 : 3);
  img.fill(i, color: img.ColorRgba8(200, 30, 30, alfa ? 128 : 255));
  return img.encodePng(i);
}

Uint8List _jpeg(int l, int a) {
  final i = img.Image(width: l, height: a);
  img.fill(i, color: img.ColorRgb8(10, 120, 200));
  return img.encodeJpg(i);
}

img.Image _ler(Uint8List b) => img.decodeJpg(b)!;

ClienteHttp _cliente(ClienteFalso f) => ClienteHttp(f);

void main() {
  group('reduzirParaJpeg', () {
    test('1800×1000 vira JPEG 900×500', () {
      final r = reduzirParaJpeg(_jpeg(1800, 1000))!;
      final i = _ler(r);
      expect((i.width, i.height), (900, 500));
    });

    test('altura no meio arredonda como o Python: 1800×1001 → 900×500', () {
      final i = _ler(reduzirParaJpeg(_png(1800, 1001))!);
      expect((i.width, i.height), (900, 500));
    });

    test('PNG com transparência vira JPEG', () {
      final r = reduzirParaJpeg(_png(400, 300, alfa: true))!;
      expect(r.sublist(0, 2), [0xFF, 0xD8]);
      final i = _ler(r);
      expect(i.numChannels, 3);
      expect((i.width, i.height), (400, 300));
    });

    test('acima do limite de pixels → null antes de decodificar', () {
      final png = _png(300, 200);
      expect(reduzirParaJpeg(png, maxPixels: 59999), isNull);
      expect(reduzirParaJpeg(png, maxPixels: 60000), isNotNull);
    });

    test('GIF também decodifica', () {
      final g = img.Image(width: 300, height: 200);
      img.fill(g, color: img.ColorRgb8(1, 2, 3));
      final r = reduzirParaJpeg(img.encodeGif(g))!;
      expect(_ler(r).width, 300);
    });

    test('menor que 120×80 → null; bytes que não são imagem → null; '
        'até 900 de largura mantém o tamanho', () {
      expect(reduzirParaJpeg(_png(119, 200)), isNull);
      expect(reduzirParaJpeg(_png(200, 79)), isNull);
      expect(reduzirParaJpeg(_png(120, 80)), isNotNull);
      expect(reduzirParaJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
      final i = _ler(reduzirParaJpeg(_png(900, 700))!);
      expect((i.width, i.height), (900, 700));
    });
  });

  test('nomeImagemNoticia', () {
    expect(
      nomeImagemNoticia('https://exemplo.com/a.jpg'),
      'noticias_img/f270ac75223f9eca1c70.jpg',
    );
  });

  group('baixarImagemNoticia', () {
    const url = 'https://exemplo.com/a.jpg';

    test('em cache não baixa', () async {
      final falso = ClienteFalso.fila([]);
      final cache = CacheBinarioMemoria();
      await cache.gravar(nomeImagemNoticia(url), [1]);
      final nome = await baixarImagemNoticia(
        _cliente(falso),
        cache,
        url,
        executar: executarDireto,
      );
      expect(nome, nomeImagemNoticia(url));
      expect(falso.pedidos, isEmpty);
    });

    test('acima de 6 MB → null e nada gravado', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(
          200,
          blocos: [List.filled(4000000, 1), List.filled(3000000, 1)],
        ),
      ]);
      final cache = CacheBinarioMemoria();
      final nome = await baixarImagemNoticia(
        _cliente(falso),
        cache,
        url,
        executar: executarDireto,
      );
      expect(nome, isNull);
      expect(await cache.ler(nomeImagemNoticia(url)), isNull);
      expect(falso.abortados, 1);
    });

    test('exatamente no limite ainda passa', () async {
      final corpo = _png(300, 200);
      final falso = ClienteFalso.fila([RespostaFalsa(200, bytes: corpo)]);
      final nome = await baixarImagemNoticia(
        _cliente(falso),
        CacheBinarioMemoria(),
        url,
        executar: executarDireto,
        limite: corpo.length,
      );
      expect(nome, isNotNull);
    });

    test('grava e devolve o nome; usa os cabeçalhos do cliente', () async {
      final corpo = _png(1000, 500);
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, blocos: [corpo.sublist(0, 50), corpo.sublist(50)]),
      ]);
      final cache = CacheBinarioMemoria();
      final nome = await baixarImagemNoticia(
        ClienteHttp(falso, userAgent: uaNavegador['User-Agent']),
        cache,
        url,
        executar: executarDireto,
      );
      expect(nome, nomeImagemNoticia(url));
      final gravado = await cache.ler(nome!);
      expect(_ler(gravado!).width, 900);
      expect(falso.pedidos.single.url.toString(), url);
      expect(
        falso.pedidos.single.cabecalhos['user-agent'],
        uaNavegador['User-Agent'],
      );
    });

    test('imagem pequena ou inválida → null sem gravar', () async {
      final cache = CacheBinarioMemoria();
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, bytes: _png(50, 50)),
        RespostaFalsa(200, texto: '<html>'),
      ]);
      for (var k = 0; k < 2; k++) {
        expect(
          await baixarImagemNoticia(
            _cliente(falso),
            cache,
            url,
            executar: executarDireto,
          ),
          isNull,
        );
      }
      expect(await cache.ler(nomeImagemNoticia(url)), isNull);
    });

    test('status de erro vira ErroHttp, como o raise_for_status', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(404, motivo: 'Not Found'),
      ]);
      await expectLater(
        baixarImagemNoticia(
          _cliente(falso),
          CacheBinarioMemoria(),
          url,
          executar: executarDireto,
        ),
        throwsA(isA<ErroHttp>()),
      );
      expect(falso.abortados, 1);
    });

    test('falha de transporte vira ErroConexao', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(0, erro: http.ClientException('caiu')),
      ]);
      expect(
        baixarImagemNoticia(
          _cliente(falso),
          CacheBinarioMemoria(),
          url,
          executar: executarDireto,
        ),
        throwsA(isA<ErroConexao>()),
      );
    });
  });

  final casos = carregarCasos('noticias_rede');
  for (final c in casos.where((c) => c.funcao == 'arquivo_favicon')) {
    test('favicon: ${c.nome}', () {
      expect(nomeArquivoFavicon(c.entrada! as String), c.saida);
    });
  }
}
