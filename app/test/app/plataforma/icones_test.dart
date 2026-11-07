import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

// sha256 do ic_launcher.png padrão do `flutter create`, anotado antes de gerar os ícones.
const hashPadraoAnotado =
    '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180';

const tamanhos = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void main() {
  test('app_icon.ico do Windows é o assets/icone.ico da raiz', () {
    expect(
      File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      File('../assets/icone.ico').readAsBytesSync(),
    );
  });
  for (final e in tamanhos.entries) {
    test('mipmap-${e.key}/ic_launcher.png tem ${e.value}x${e.value}', () {
      final img = decodePng(
        File(
          'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
        ).readAsBytesSync(),
      )!;
      expect((img.width, img.height), (e.value, e.value));
    });
  }
  test('mipmap-xxxhdpi não é o ícone padrão do Flutter', () {
    expect(
      sha256
          .convert(
            File(
              'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
            ).readAsBytesSync(),
          )
          .toString(),
      isNot(hashPadraoAnotado),
    );
  });
}
