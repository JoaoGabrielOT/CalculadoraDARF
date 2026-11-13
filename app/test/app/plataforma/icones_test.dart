import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart';

// sha256 do ic_launcher.png padrão do `flutter create`, anotado antes de gerar os ícones.
const hashPadraoAnotado =
    '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180';

// sha256 do web/icons/Icon-512.png padrão do `flutter create`, anotado antes de gerar os ícones.
const hashWebPadraoAnotado =
    'baccb205ae45f0b421be1657259b4943ac40c95094ab877f3bcbe12cd544dcbe';

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
  const web = {
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
    'web/icons/apple-touch-icon.png': 180,
    'web/favicon.png': 32,
  };
  for (final e in web.entries) {
    test('${e.key} tem ${e.value}x${e.value}', () {
      final img = decodePng(File(e.key).readAsBytesSync())!;
      expect((img.width, img.height), (e.value, e.value));
    });
  }
  for (final c in [
    'web/icons/apple-touch-icon.png',
    'web/icons/Icon-maskable-512.png',
  ]) {
    test('$c tem fundo opaco #0D1117 no canto', () {
      final img = decodePng(File(c).readAsBytesSync())!;
      final p = img.getPixel(0, 0);
      expect((p.r, p.g, p.b, p.a), (0x0D, 0x11, 0x17, 255));
    });
  }
  test('Icon-512 da web não é o ícone padrão do Flutter', () {
    expect(
      sha256
          .convert(File('web/icons/Icon-512.png').readAsBytesSync())
          .toString(),
      isNot(hashWebPadraoAnotado),
    );
  });
}
