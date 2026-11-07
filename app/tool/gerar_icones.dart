// Gera os ícones do app a partir de ../assets: app_icon.ico (Windows) e
// ic_launcher.png de cada densidade (Android). Rodar dentro de app/:
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
}
