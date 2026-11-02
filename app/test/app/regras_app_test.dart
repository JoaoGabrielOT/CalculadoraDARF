import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectores (mapas sintéticos)', () {
    test('servicos/ e tema_visual.dart não importam package:flutter', () {
      expect(
        violacoesFlutterEmServicos({
          'lib/app/servicos/a.dart': "import 'package:flutter/material.dart';"
        }),
        isNotEmpty,
      );
      expect(
        violacoesFlutterEmServicos({
          'lib/app/tema/tema_visual.dart':
              "import 'package:flutter/foundation.dart';"
        }),
        isNotEmpty,
      );
      expect(
        violacoesFlutterEmServicos({
          'lib/app/tema/tema.dart': "import 'package:flutter/material.dart';",
          'lib/app/servicos/b.dart': "// import 'package:flutter/material.dart';",
        }),
        isEmpty,
      );
    });

    test('telas, componentes, estado, regras e tema não importam IO nem plugins',
        () {
      for (final pasta in ['telas', 'componentes', 'estado', 'regras', 'tema']) {
        for (final imp in [
          "import 'dart:io';",
          "import 'package:http/http.dart';",
          "import 'package:path_provider/path_provider.dart';",
          "import 'package:url_launcher/url_launcher.dart';",
          "import 'package:flutter_local_notifications/x.dart';",
        ]) {
          expect(
            violacoesImportsProibidosNaUi({'lib/app/$pasta/a.dart': imp}),
            isNotEmpty,
            reason: '$pasta: $imp',
          );
        }
      }
      expect(
        violacoesImportsProibidosNaUi(
            {'lib/app/plataforma/a.dart': "import 'dart:io';"}),
        isEmpty,
      );
      expect(
        violacoesImportsProibidosNaUi(
            {'lib/app/telas/a.dart': "// import 'dart:io';"}),
        isEmpty,
      );
    });

    test('plugins só em plataforma/', () {
      for (final imp in [
        "import 'package:path_provider/path_provider.dart';",
        "import 'package:url_launcher/url_launcher.dart';",
        "import 'package:flutter_local_notifications/x.dart';",
        "import 'package:flutter/services.dart';",
      ]) {
        expect(
          violacoesPluginsForaDePlataforma({'lib/app/estado/a.dart': imp}),
          isNotEmpty,
          reason: imp,
        );
        expect(
          violacoesPluginsForaDePlataforma({'lib/app/plataforma/a.dart': imp}),
          isEmpty,
          reason: imp,
        );
      }
    });

    test('exceção explícita só vale para o arquivo listado', () {
      const imp = "import 'package:flutter/services.dart';";
      expect(
        violacoesPluginsForaDePlataforma({'lib/app/telas/x.dart': imp},
            excecoes: const ['lib/app/telas/x.dart']),
        isEmpty,
      );
      expect(
        violacoesPluginsForaDePlataforma({'lib/app/telas/y.dart': imp},
            excecoes: const ['lib/app/telas/x.dart']),
        isNotEmpty,
      );
    });

    test('.sort( gera violação; comentário não', () {
      expect(violacoesSort({'lib/app/a.dart': 'lista.sort();'}), isNotEmpty);
      expect(violacoesSort({'lib/app/a.dart': '// nunca .sort( aqui'}), isEmpty);
      expect(violacoesSort({'lib/app/a.dart': 'ordenadoPor(l, f);'}), isEmpty);
    });

    test('componentes/ não importa a raiz app.dart', () {
      expect(
        violacoesComponenteImportaRaiz({
          'lib/app/componentes/a.dart': "import '../app.dart' show expandido;",
          'lib/app/componentes/b.dart':
              "import 'package:calculadoradarf/app/app.dart';",
        }),
        hasLength(2),
      );
      expect(
        violacoesComponenteImportaRaiz({
          'lib/app/componentes/a.dart': "import '../tema/layout.dart';",
          'lib/app/componentes/b.dart': "// import '../app.dart';",
          'lib/app/telas/c.dart': "import '../app.dart';",
        }),
        isEmpty,
      );
    });

    test('nucleo e integracoes que importam app/ geram violação', () {
      expect(
        violacoesImportaApp({
          'lib/nucleo/a.dart': "import '../app/estado/x.dart';",
          'lib/integracoes/b.dart':
              "import 'package:calculadoradarf/app/x.dart';",
        }),
        hasLength(2),
      );
      expect(
        violacoesImportaApp({
          'lib/nucleo/a.dart': "import 'dinheiro.dart';",
          'lib/integracoes/b.dart': "// import '../app/x.dart';",
        }),
        isEmpty,
      );
    });
  });

  group('código real', () {
    final app = _arquivosDe('lib/app');
    final nucleo = _arquivosDe('lib/nucleo');
    final integracoes = _arquivosDe('lib/integracoes');

    test('raiz do projeto encontrada e lib/app lido quando existe', () {
      // Caminho errado faria os testes abaixo passarem em silêncio.
      expect(File('pubspec.yaml').existsSync(), isTrue,
          reason: 'rode a partir de app/');
      expect(Directory('lib/nucleo').existsSync(), isTrue);
      // lib/app ainda não existe na Tarefa 1; a partir de que existir, tem
      // de ser lido (não vazio).
      if (Directory('lib/app').existsSync()) expect(app, isNotEmpty);
    });

    test('servicos/ e tema_visual.dart não importam package:flutter', () {
      expect(violacoesFlutterEmServicos(app), isEmpty);
    });

    test('telas, componentes, estado, regras e tema não importam IO nem plugins',
        () {
      expect(violacoesImportsProibidosNaUi(app), isEmpty);
    });

    test('só plataforma/ importa plugins', () {
      expect(violacoesPluginsForaDePlataforma(app), isEmpty);
    });

    test('lib/app não usa .sort(', () {
      expect(violacoesSort(app), isEmpty);
    });

    test('componentes/ não importa a raiz app.dart', () {
      expect(violacoesComponenteImportaRaiz(app), isEmpty);
    });

    test('nucleo e integracoes não importam app/', () {
      expect(nucleo, isNotEmpty);
      expect(integracoes, isNotEmpty);
      expect(violacoesImportaApp({...nucleo, ...integracoes}), isEmpty);
    });
  });
}

/// Texto sem as linhas de comentário (`//`), para não acusar menções em prosa.
String _semComentarios(String texto) => texto
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// Linhas `import`/`export` do arquivo, sem comentários.
Iterable<String> _imports(String texto) => _semComentarios(texto)
    .split('\n')
    .where((l) => RegExp(r'^\s*(import|export)\s').hasMatch(l));

bool _emPasta(String caminho, String pasta) =>
    caminho.contains('lib/app/$pasta/');

/// servicos/ e tema/tema_visual.dart rodam no isolate de serviços: sem Flutter.
List<String> violacoesFlutterEmServicos(Map<String, String> arquivos) {
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    final alvo = _emPasta(caminho, 'servicos') ||
        caminho.endsWith('lib/app/tema/tema_visual.dart');
    if (alvo && _semComentarios(bruto).contains('package:flutter')) {
      violacoes.add('$caminho usa package:flutter');
    }
  });
  return violacoes;
}

/// Componentes são folhas: nada de importar `app.dart` (a raiz importa as
/// telas, que importam os componentes).
List<String> violacoesComponenteImportaRaiz(Map<String, String> arquivos) {
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (!_emPasta(caminho, 'componentes')) return;
    for (final imp in _imports(bruto)) {
      if (RegExp(r'''['"](\.\./app\.dart|package:calculadoradarf/app/app\.dart)['"]''')
          .hasMatch(imp)) {
        violacoes.add('$caminho importa app.dart');
      }
    }
  });
  return violacoes;
}

/// Telas, componentes, estado, regras e tema sem IO de arquivo/rede nem plugins.
List<String> violacoesImportsProibidosNaUi(Map<String, String> arquivos) {
  const pastas = ['telas', 'componentes', 'estado', 'regras', 'tema'];
  const proibidos = [
    'dart:io',
    'package:http/',
    'package:path_provider/',
    'package:url_launcher/',
    'package:flutter_local_notifications/',
  ];
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (!pastas.any((p) => _emPasta(caminho, p))) return;
    for (final imp in _imports(bruto)) {
      for (final p in proibidos) {
        if (imp.contains(p)) violacoes.add('$caminho usa $p');
      }
    }
  });
  return violacoes;
}

/// Plugins (e `package:flutter/services.dart`) só em plataforma/, salvo os
/// arquivos da lista explícita (HapticFeedback/Clipboard em telas). Os
/// formulários usam só `LogicalKeyboardKey` (Enter salva, Esc cancela).
const List<String> excecoesServices = [
  'lib/app/telas/formularios/abrir_formulario.dart',
];

List<String> violacoesPluginsForaDePlataforma(
  Map<String, String> arquivos, {
  List<String> excecoes = excecoesServices,
}) {
  const plugins = [
    'package:path_provider/',
    'package:url_launcher/',
    'package:flutter_local_notifications/',
    'package:flutter/services.dart',
  ];
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (_emPasta(caminho, 'plataforma') || excecoes.contains(caminho)) return;
    for (final imp in _imports(bruto)) {
      for (final p in plugins) {
        if (imp.contains(p)) violacoes.add('$caminho usa $p');
      }
    }
  });
  return violacoes;
}

/// `.sort(` proibido em lib/app (usar `ordenadoPor`, estável como o Python).
List<String> violacoesSort(Map<String, String> arquivos) {
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (_semComentarios(bruto).contains('.sort(')) {
      violacoes.add('$caminho usa .sort(');
    }
  });
  return violacoes;
}

/// nucleo/ e integracoes/ não importam app/.
List<String> violacoesImportaApp(Map<String, String> arquivos) {
  final violacoes = <String>[];
  arquivos.forEach((caminho, bruto) {
    if (_imports(bruto).any((l) => RegExp(r"""['"/:]app/""").hasMatch(l))) {
      violacoes.add('$caminho importa app/');
    }
  });
  return violacoes;
}

/// Arquivos .dart de uma pasta, com caminho relativo normalizado para '/'.
Map<String, String> _arquivosDe(String pasta) {
  final raiz = Directory(pasta);
  final arquivos = <String, String>{};
  if (!raiz.existsSync()) return arquivos;
  for (final e in raiz.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) {
      arquivos[e.path.replaceAll('\\', '/')] = e.readAsStringSync();
    }
  }
  return arquivos;
}
