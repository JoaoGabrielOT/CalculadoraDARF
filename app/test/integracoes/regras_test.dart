import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Arquivos .dart de uma pasta, com caminho relativo normalizado para '/'.
Map<String, String> _arquivosDe(String pasta) {
  final raiz = Directory(pasta);
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
  final arquivos = _arquivosDe('lib/integracoes');

  test('integracoes não importa widgets, material, cupertino nem dart:ui', () {
    const proibidos = [
      'package:flutter/material.dart',
      'package:flutter/widgets.dart',
      'package:flutter/cupertino.dart',
      'dart:ui',
    ];
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      for (final p in proibidos) {
        if (texto.contains(p)) violacoes.add('$caminho usa $p');
      }
    });
    expect(violacoes, isEmpty);
  });

  test('package:flutter só em google/credenciais_asset.dart e só services.dart',
      () {
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      if (!texto.contains('package:flutter')) return;
      final permitido = caminho.endsWith('/google/credenciais_asset.dart') &&
          texto.contains('package:flutter/services.dart') &&
          !RegExp(r'package:flutter/(?!services\.dart)').hasMatch(texto);
      if (!permitido) violacoes.add(caminho);
    });
    expect(violacoes, isEmpty);
  });

  test('integracoes não usa .sort( nem .round(', () {
    const proibidos = ['.sort(', '.round('];
    final violacoes = <String>[];
    arquivos.forEach((caminho, texto) {
      for (final p in proibidos) {
        if (texto.contains(p)) violacoes.add('$caminho usa $p');
      }
    });
    expect(violacoes, isEmpty);
  });

  test('núcleo não importa integracoes', () {
    final violacoes = <String>[];
    _arquivosDe('lib/nucleo').forEach((caminho, texto) {
      if (texto.contains('integracoes/')) violacoes.add(caminho);
    });
    expect(violacoes, isEmpty);
  });
}
