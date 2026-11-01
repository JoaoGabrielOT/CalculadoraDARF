// Imagem da matéria reduzida e gravada como JPEG (noticias.py:433-455).

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../nucleo/compat/numeros.dart';
import '../../nucleo/compat/regex_python.dart';
import '../cache_binario.dart';
import '../executor.dart';
import '../http/cliente.dart';
import '../http/erros.dart';

/// Nome do cache da imagem (calculadora_darf.py:2264).
String nomeImagemNoticia(String url) =>
    'noticias_img/${sha1.convert(utf8.encode(url)).toString().substring(0, 20)}.jpg';

final _foraDoNome = erPython(r'[^\w.-]');

/// Nome do arquivo do favicon de um domínio (noticias.py:511).
String nomeArquivoFavicon(String dominio) =>
    '${dominio.replaceAll(_foraDoNome, '_')}.png';

/// Decodifica (JPEG, PNG, WebP, GIF), descarta o alfa, reduz para [largura] e
/// reencoda em JPEG qualidade 85; `null` se não for imagem ou for menor que 120×80.
Uint8List? reduzirParaJpeg(
  Uint8List dados, {
  int largura = 900,
  int maxPixels = 25000000,
}) {
  final info = img.findDecoderForData(dados)?.startDecode(dados);
  if (info == null || info.width * info.height > maxPixels) return null;
  final original = img.decodeImage(dados);
  if (original == null) return null;
  var imagem = original.convert(
    format: img.Format.uint8,
    numChannels: 3,
    noAnimation: true,
  );
  if (imagem.width < 120 || imagem.height < 80) return null;
  if (imagem.width > largura) {
    final altura = arredondar(imagem.height * largura / imagem.width, 0);
    imagem = img.copyResize(
      imagem,
      width: largura,
      height: altura.toInt(),
      interpolation: img.Interpolation.cubic,
    );
  }
  return img.encodeJpg(imagem, quality: 85);
}

/// Baixa, reduz e grava a imagem; devolve o nome no cache. Em cache não baixa;
/// corpo acima de [limite] ou imagem inválida dá `null`.
Future<String?> baixarImagemNoticia(
  ClienteHttp navegador,
  CacheBinario cache,
  String url, {
  Executar executar = executarEmIsolate,
  int largura = 900,
  int limite = 6000000,
}) async {
  final nome = nomeImagemNoticia(url);
  if (await cache.ler(nome) != null) return nome;
  final uri = Uri.parse(url);
  final resposta = await navegador.abrir('GET', uri);
  try {
    conferirStatus(resposta.status, uri, motivo: resposta.motivo);
  } catch (_) {
    await resposta.cancelar();
    rethrow;
  }
  final corpo = BytesBuilder(copy: false);
  await for (final bloco in resposta.blocos) {
    corpo.add(bloco);
    if (corpo.length > limite) {
      await resposta.cancelar();
      return null;
    }
  }
  final dados = corpo.takeBytes();
  final jpeg = await executar(() => reduzirParaJpeg(dados, largura: largura));
  if (jpeg == null) return null;
  await cache.gravar(nome, jpeg);
  return nome;
}
