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

/// Texto sem as linhas de comentário (`//`), para não acusar menções em prosa.
String _semComentarios(String texto) => texto
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// Imports proibidos em integracoes: widgets, material, cupertino, dart:ui; e
/// package:flutter fora de google/credenciais_asset.dart (e só services.dart).
List<String> violacoesImportsIntegracoes(Map<String, String> arquivos) {
  const proibidos = [
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'package:flutter/cupertino.dart',
    'dart:ui',
  ];
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    final texto = _semComentarios(bruto);
    for (final p in proibidos) {
      if (texto.contains(p)) violacoes.add('$caminho usa $p');
    }
    if (!texto.contains('package:flutter')) return;
    final permitido = caminho.endsWith('/google/credenciais_asset.dart') &&
        texto.contains('package:flutter/services.dart') &&
        !RegExp(r'package:flutter/(?!services\.dart)').hasMatch(texto);
    if (!permitido) violacoes.add('$caminho usa package:flutter');
  });
  return violacoes;
}

/// `.sort(` e `.round(` proibidos em integracoes (linhas de comentário à parte).
List<String> violacoesSortRound(Map<String, String> arquivos) {
  const proibidos = ['.sort(', '.round('];
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    final texto = _semComentarios(bruto);
    for (final p in proibidos) {
      if (texto.contains(p)) violacoes.add('$caminho usa $p');
    }
  });
  return violacoes;
}

/// Arquivos do núcleo que importam integracoes/.
List<String> violacoesNucleoImportaIntegracoes(Map<String, String> arquivos) {
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (_semComentarios(bruto).contains('integracoes/')) {
      violacoes.add(caminho);
    }
  });
  return violacoes;
}

void main() {
  final integracoes = _arquivosDe('lib/integracoes');
  final nucleo = _arquivosDe('lib/nucleo');

  group('detectores (mapas sintéticos)', () {
    const g = 'lib/integracoes/google/credenciais_asset.dart';
    const outro = 'lib/integracoes/x.dart';

    test('imports proibidos geram violação', () {
      for (final imp in [
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/widgets.dart';",
        "import 'package:flutter/cupertino.dart';",
        "import 'dart:ui';",
        "import 'package:flutter/services.dart';",
      ]) {
        expect(violacoesImportsIntegracoes({outro: imp}), isNotEmpty,
            reason: imp);
      }
      expect(
        violacoesImportsIntegracoes(
            {g: "import 'package:flutter/foundation.dart';"}),
        isNotEmpty,
      );
      expect(
        violacoesImportsIntegracoes({
          g: "import 'package:flutter/services.dart';\n"
              "import 'package:flutter/foundation.dart';"
        }),
        isNotEmpty,
      );
    });

    test('services.dart em google/credenciais_asset.dart passa', () {
      expect(
        violacoesImportsIntegracoes(
            {g: "import 'package:flutter/services.dart';"}),
        isEmpty,
      );
    });

    test('.sort( e .round( geram violação; comentário não', () {
      expect(violacoesSortRound({outro: 'lista.sort();'}), isNotEmpty);
      expect(violacoesSortRound({outro: 'final a = x.round();'}), isNotEmpty);
      expect(violacoesSortRound({outro: '// nunca usar .sort( aqui'}), isEmpty);
      expect(violacoesSortRound({outro: '  /// evite .round( sempre'}), isEmpty);
    });

    test('núcleo que importa integracoes/ gera violação', () {
      expect(
        violacoesNucleoImportaIntegracoes({
          'lib/nucleo/a.dart': "import '../integracoes/integracoes.dart';"
        }),
        isNotEmpty,
      );
      expect(
        violacoesNucleoImportaIntegracoes({'lib/nucleo/a.dart': 'int x = 1;'}),
        isEmpty,
      );
    });
  });

  group('código real', () {
    test('integracoes não importa widgets, material, cupertino nem dart:ui',
        () {
      expect(integracoes, isNotEmpty);
      expect(
        violacoesImportsIntegracoes(integracoes)
            .where((v) => !v.endsWith('usa package:flutter')),
        isEmpty,
      );
    });

    test(
        'package:flutter só em google/credenciais_asset.dart e só services.dart',
        () {
      expect(integracoes, isNotEmpty);
      expect(
        violacoesImportsIntegracoes(integracoes)
            .where((v) => v.endsWith('usa package:flutter')),
        isEmpty,
      );
    });

    test('integracoes não usa .sort( nem .round(', () {
      expect(integracoes, isNotEmpty);
      expect(violacoesSortRound(integracoes), isEmpty);
    });

    test('núcleo não importa integracoes', () {
      expect(nucleo, isNotEmpty);
      expect(violacoesNucleoImportaIntegracoes(nucleo), isEmpty);
    });
  });
}
