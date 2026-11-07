import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Arquivos .dart do núcleo, com caminho relativo normalizado para '/'.
Map<String, String> _arquivosDoNucleo() {
  final raiz = Directory('lib/nucleo');
  final arquivos = <String, String>{};
  if (!raiz.existsSync()) return arquivos;
  for (final e in raiz.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      final rel = e.path.replaceAll('\\', '/');
      arquivos[rel] = e.readAsStringSync();
    }
  }
  return arquivos;
}

void main() {
  final arquivos = _arquivosDoNucleo();

  test('núcleo não importa Flutter, dart:ui nem rede', () {
    const proibidos = ['package:flutter', 'dart:ui', 'package:http'];
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      for (final p in proibidos) {
        if (texto.contains(p)) violacoes.add('$caminho usa $p');
      }
    });
    expect(violacoes, isEmpty);
  });

  test('dart:io só em armazenamento_arquivos.dart', () {
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      if (caminho.endsWith('/armazenamento_arquivos.dart')) return;
      if (texto.contains('dart:io')) violacoes.add(caminho);
    });
    expect(violacoes, isEmpty);
  });

  test('fora de compat/ não usa toStringAsFixed, .sort(, math.max, math.min, '
      '.round(, .roundToDouble(', () {
    const proibidos = [
      'toStringAsFixed',
      '.sort(',
      'math.max',
      'math.min',
      '.round(',
      '.roundToDouble(',
    ];
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      if (caminho.contains('/compat/')) return;
      for (final p in proibidos) {
        if (texto.contains(p)) violacoes.add('$caminho usa $p');
      }
    });
    expect(violacoes, isEmpty);
  });
}
