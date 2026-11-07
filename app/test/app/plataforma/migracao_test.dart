import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/app/plataforma/migracao.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mês e config reais da 1.12 (gerados pelo Python, plano 1).
final Map<String, Object?> _arquivos = () {
  final ref = jsonDecode(
    File('test/referencias/modelos.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final casos = (ref['casos']! as List).cast<Map<String, Object?>>();
  return Map<String, Object?>.from(
    casos.firstWhere((c) => c['nome'] == 'config_pelo_python')['entrada']!
        as Map,
  );
}();

String get _mes => jsonEncode(_arquivos['2026-10.json']);
String get _config => jsonEncode(_arquivos['config.json']);

/// No Windows de desenvolvimento o listSync devolve '\': compara com '/'.
List<String> _android(String raiz) => [
  for (final p in origensAndroid([raiz], destino: '$raiz/dados'))
    p.replaceAll('\\', '/'),
];

String _barra(String s) => s.replaceAll(r'\', '/');

void main() {
  late Directory tmp;
  late String origem;
  late String destino;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('migracao_test');
    origem = '${tmp.path}/origem';
    destino = '${tmp.path}/suporte/dados';
    Directory(origem).createSync(recursive: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void escrever(String caminho, String texto) {
    final f = File(caminho)..createSync(recursive: true);
    f.writeAsStringSync(texto);
  }

  void montarOrigem() {
    escrever('$origem/config.json', _config);
    escrever('$origem/token.json', '{"token": "t"}');
    escrever('$origem/2026-10.json', _mes);
    File('$origem/logos/PETR4.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    File('$origem/noticias_img/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([4, 5]);
  }

  group('migrarDados112', () {
    test('copia a árvore inteira e grava o marcador', () {
      montarOrigem();
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.erro, isNull);
      expect(r.origem, origem);
      expect(r.copiados, 5);
      expect(r.divergentes, isEmpty);
      expect(File('$destino/logos/PETR4.png').existsSync(), isTrue);
      expect(File('$destino/noticias_img/a.jpg').readAsBytesSync(), [4, 5]);
      final marcador = jsonDecode(
        File('$destino/.migrado_1_12.json').readAsStringSync(),
      ) as Map;
      expect(marcador['copiados'], 5);
      expect(marcador['origem'], origem);
      expect(File('$origem/config.json').existsSync(), isTrue);
      expect(File('$origem/logos/PETR4.png').existsSync(), isTrue);
    });

    test('com marcador não copia nada', () {
      montarOrigem();
      Directory(destino).createSync(recursive: true);
      escrever('$destino/$nomeMarcadorMigracao', '{}');
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.origem, isNull);
      expect(File('$destino/config.json').existsSync(), isFalse);
    });

    test('não sobrescreve arquivo que já existe no destino', () {
      montarOrigem();
      escrever('$destino/config.json', 'novo');
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.copiados, 4);
      expect(File('$destino/config.json').readAsStringSync(), 'novo');
    });

    test('arquivo que perde dado na leitura entra em divergentes', () {
      final mes = jsonDecode(_mes) as Map<String, Object?>;
      ((mes['lotes']! as List).first as Map)['x'] = 1;
      final texto = jsonEncode(mes);
      escrever('$origem/2026-10.json', texto);
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.divergentes, ['2026-10.json']);
      expect(File('$destino/2026-10.json').readAsStringSync(), texto);
    });

    test('JSON ilegível entra em divergentes e é copiado', () {
      escrever('$origem/config.json', '{não é json');
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.divergentes, ['config.json']);
      expect(File('$destino/config.json').readAsStringSync(), '{não é json');
      expect(r.erro, isNull);
    });

    test('erro na cópia não grava marcador e devolve o erro', () {
      montarOrigem();
      escrever(destino, 'sou um arquivo');
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.erro, isNotNull);
      expect(r.origem, isNull);
      expect(File('$destino/$nomeMarcadorMigracao').existsSync(), isFalse);
    });

    test('sem origem candidata não grava marcador', () {
      final r = migrarDados112(
        destino: destino,
        origens: [origem, '${tmp.path}/inexistente'],
      );
      expect(r.origem, isNull);
      expect(r.erro, isNull);
      expect(File('$destino/$nomeMarcadorMigracao').existsSync(), isFalse);
    });
  });

  group('nova tentativa', () {
    String mesDivergente() {
      final mes = jsonDecode(_mes) as Map<String, Object?>;
      ((mes['lotes']! as List).first as Map)['x'] = 1;
      return jsonEncode(mes);
    }

    test('falha no meio: sem marcador; a próxima passada completa', () {
      montarOrigem();
      escrever('$origem/2026-10.json', mesDivergente());
      escrever('$origem/zzz/x.png', 'x');
      // falha só depois do arquivo do mês (a cópia segue a ordem do caminho)
      escrever('$destino/zzz', 'arquivo no lugar da pasta');
      final r1 = migrarDados112(destino: destino, origens: [origem]);
      expect(r1.erro, isNotNull);
      expect(File('$destino/$nomeMarcadorMigracao').existsSync(), isFalse);
      File('$destino/zzz').deleteSync();
      final r2 = migrarDados112(destino: destino, origens: [origem]);
      expect(r2.erro, isNull);
      expect(r2.divergentes, ['2026-10.json']);
      expect(File('$destino/logos/PETR4.png').readAsBytesSync(), [1, 2, 3]);
      expect(File('$destino/$nomeMarcadorMigracao').existsSync(), isTrue);
    });

    test('sobra .migrando truncada é apagada e o arquivo é recopiado', () {
      montarOrigem();
      escrever('$destino/config.json.migrando', '{trunc');
      escrever('$destino/logos/PETR4.png.migrando', 'x');
      final r = migrarDados112(destino: destino, origens: [origem]);
      expect(r.erro, isNull);
      expect(r.copiados, 5);
      expect(File('$destino/config.json').readAsStringSync(), _config);
      expect(File('$destino/config.json.migrando').existsSync(), isFalse);
      expect(File('$destino/logos/PETR4.png.migrando').existsSync(), isFalse);
    });

    test('origem com letra que muda de tamanho em minúsculas', () {
      final o = '${tmp.path}/İdados';
      escrever('$o/config.json', _config);
      escrever('$o/logos/a.png', 'a');
      final r = migrarDados112(destino: destino, origens: [o]);
      expect(r.copiados, 2);
      expect(File('$destino/logos/a.png').existsSync(), isTrue);
    });
  });

  group('origens', () {
    test('origensWindows lê caminho com acentos e BOM', () {
      final pasta = '${tmp.path}\\Área de Trabalho\\João\\dados';
      Directory(pasta).createSync(recursive: true);
      File('${tmp.path}/$nomeArquivoOrigem')
          .writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode('$pasta\r\n')]);
      expect(origensWindows(tmp.path), [pasta]);
    });

    test(
      'origensWindows sem arquivo ou com pasta inexistente devolve vazio',
      () {
        expect(origensWindows(tmp.path), isEmpty);
        escrever('${tmp.path}/$nomeArquivoOrigem', '${tmp.path}/nao_existe\n');
        expect(origensWindows(tmp.path), isEmpty);
      },
    );

    test('origensAndroid acha a pasta do Flet e ignora o destino', () {
      final raiz = '${_barra(tmp.path)}/raiz';
      escrever('$raiz/flet/app_storage/config.json', _config);
      escrever('$raiz/flet/app_storage/token.json', '{}');
      escrever('$raiz/dados/config.json', _config);
      expect(_android(raiz), ['$raiz/flet/app_storage']);
    });

    test('origensAndroid põe a pasta com token antes das outras', () {
      final raiz = '${_barra(tmp.path)}/raiz';
      escrever('$raiz/a/config.json', _config);
      escrever('$raiz/b/config.json', _config);
      escrever('$raiz/b/token.json', '{}');
      expect(_android(raiz).first, '$raiz/b');
    });

    test('origensAndroid respeita a profundidade', () {
      final raiz = '${_barra(tmp.path)}/raiz';
      escrever('$raiz/a/b/c/d/e/config.json', _config);
      expect(_android(raiz), isEmpty);
      escrever('$raiz/a/b/c/d/config.json', _config);
      expect(_android(raiz), ['$raiz/a/b/c/d']);
    });
  });

  test(
    'preservaOriginal aceita 1 e 1.0 e chaves a mais, recusa chave perdida',
    () {
      expect(preservaOriginal({'a': 1}, {'a': 1.0, 'b': 2}), isTrue);
      expect(preservaOriginal({'a': 1, 'x': 'y'}, {'a': 1}), isFalse);
      expect(preservaOriginal([1, 2], [1]), isFalse);
    },
  );

  test(
    'avisoMigracao: nada com sucesso limpo; texto com erro e com divergências',
    () {
      expect(avisoMigracao(const ResultadoMigracao()), isNull);
      expect(
        avisoMigracao(const ResultadoMigracao(origem: 'o', copiados: 3)),
        isNull,
      );
      expect(avisoMigracao(const ResultadoMigracao(erro: 'falhou')), (
        'Dados da versão anterior',
        'Não foi possível copiar os dados da versão anterior: falhou. '
            'O app tenta de novo na próxima abertura.',
      ));
      expect(
        avisoMigracao(
          const ResultadoMigracao(
            origem: 'o',
            copiados: 3,
            divergentes: ['a.json', 'b.json'],
          ),
        ),
        (
          'Dados da versão anterior',
          'Copiados 3 arquivos de o. Confira estes arquivos, que não foram '
              'lidos por inteiro: a.json, b.json.',
        ),
      );
    },
  );

  test('migrarNaPartida roda no isolate e nunca lança', () async {
    montarOrigem();
    final r = await migrarNaPartida(
      pastaSuporte: tmp.path,
      destino: destino,
      windows: false,
      raizesAndroid: [origem],
    );
    expect(r.erro, isNull);
    expect(r.copiados, 5);
  });
}
