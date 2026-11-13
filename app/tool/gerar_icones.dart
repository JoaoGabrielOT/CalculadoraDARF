// Gera os ícones do app a partir de ../assets: app_icon.ico (Windows) e
// ic_launcher.png de cada densidade (Android) e os ícones da Web (web/). Rodar dentro de app/:
// dart run tool/gerar_icones.dart
import 'dart:io';

import 'package:image/image.dart';

const tamanhos = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

Future<void> main() async {
  final ico = File('../assets/icone.ico').readAsBytesSync();
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);

  var fonte = decodePng(File('../assets/icone_janela.png').readAsBytesSync())!;
  if (fonte.width < 192) {
    fonte = decodeIco(ico)!;
  }

  for (final e in tamanhos.entries) {
    final redim = copyResize(
      fonte,
      width: e.value,
      height: e.value,
      interpolation: Interpolation.average,
    );
    File('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png')
        .writeAsBytesSync(encodePng(redim));
  }

  _gerarWeb();
}

// Ícones da PWA a partir de ../assets/logo.png (1024x1024).
void _gerarWeb() {
  final logo = decodePng(File('../assets/logo.png').readAsBytesSync())!;
  Image redim(int t) => copyResize(
    logo,
    width: t,
    height: t,
    interpolation: Interpolation.average,
  );
  void salvar(String caminho, Image img) =>
      File('web/$caminho').writeAsBytesSync(encodePng(img));

  // Logo a `fracao` do lado, centrado sobre quadrado opaco #0D1117.
  Image sobreFundo(int lado, double fracao) {
    final fundo = Image(width: lado, height: lado, numChannels: 4);
    fill(fundo, color: ColorRgba8(0x0D, 0x11, 0x17, 255));
    final t = (lado * fracao).round();
    final off = (lado - t) ~/ 2;
    return compositeImage(fundo, redim(t), dstX: off, dstY: off);
  }

  salvar('icons/Icon-192.png', redim(192));
  salvar('icons/Icon-512.png', redim(512));
  salvar('favicon.png', redim(32));
  salvar('icons/Icon-maskable-192.png', sobreFundo(192, 0.8));
  salvar('icons/Icon-maskable-512.png', sobreFundo(512, 0.8));
  salvar('icons/apple-touch-icon.png', sobreFundo(180, 1.0));
}
