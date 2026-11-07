// Sem a fonte dos símbolos (Linux, CI) os goldens são pulados com o motivo,
// em vez de falharem pixel a pixel. Este teste não tem a tag golden.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../apoio/fontes.dart';

void main() {
  late Directory windir;

  setUp(() => windir = Directory.systemTemp.createTempSync('windir'));
  tearDown(() => windir.deleteSync(recursive: true));

  test('sem seguisym.ttf devolve o motivo para pular', () {
    final motivo = motivoParaPularGoldens(windir: windir.path);
    expect(motivo, contains('seguisym.ttf'));
    expect(motivo, contains('Windows'));
  });

  test('com seguisym.ttf não pula', () {
    Directory('${windir.path}/Fonts').createSync();
    File('${windir.path}/Fonts/seguisym.ttf').writeAsBytesSync([0]);
    expect(motivoParaPularGoldens(windir: windir.path), isNull);
  });
}
