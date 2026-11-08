import 'dart:io';

import 'package:calculadoradarf/app/plataforma/backup.dart';
import 'package:calculadoradarf/versao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String dados;
  final sep = Platform.pathSeparator;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_test');
    dados = '${tmp.path}${sep}dados';
    Directory('$dados${sep}cache').createSync(recursive: true);
    File('$dados${sep}2026-01.json').writeAsStringSync('{"mes": "2026-01"}');
    File('$dados${sep}config.json').writeAsStringSync('{"tema": "Dark"}');
    File('$dados${sep}token.json').writeAsBytesSync([0, 1, 2, 255]);
    File('$dados${sep}notas.txt').writeAsStringSync('fora');
    File('$dados${sep}cache${sep}x.json').writeAsStringSync('{}');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, List<int>> conteudo(String pasta) => {
    for (final f in Directory(pasta).listSync().whereType<File>())
      f.uri.pathSegments.last: f.readAsBytesSync(),
  };

  test('copia os *.json, confere e não toca a origem', () {
    final origem = conteudo(dados);
    final pasta = fazerBackup(dados, DateTime(2026, 11, 8, 9, 5, 3));
    expect(pasta, '$dados${sep}backup${sep}pre-$versaoApp-20261108-090503');
    final copia = conteudo(pasta);
    expect(copia.keys.toSet(), {'2026-01.json', 'config.json', 'token.json'});
    for (final e in copia.entries) {
      expect(e.value, origem[e.key], reason: e.key);
    }
    // só a pasta de backup foi criada; os arquivos de origem são os mesmos
    expect(conteudo(dados), origem);
    expect(File('$dados${sep}cache${sep}x.json').readAsStringSync(), '{}');
    expect(Directory(pasta).listSync().whereType<Directory>(), isEmpty);
  });

  test('um backup por versão: o segundo devolve o primeiro sem copiar', () {
    final p1 = fazerBackup(dados, DateTime(2026, 11, 8, 9, 5, 3));
    final copia = conteudo(p1);
    File('$dados${sep}2026-01.json').writeAsStringSync('{"mudou": true}');
    final p2 = fazerBackup(dados, DateTime(2026, 11, 9, 10));
    expect(p2, p1);
    expect(conteudo(p1), copia);
    expect(Directory('$dados${sep}backup').listSync().map((e) => e.path), [p1]);
  });

  test('backup de outra versão ou pasta temporária não conta', () {
    Directory('$dados${sep}backup${sep}pre-0.0.1-20200101-000000')
        .createSync(recursive: true);
    // sobra de uma cópia interrompida: incompleta, não é backup
    Directory('$dados${sep}backup$sep.pre-$versaoApp-20261108-090503.tmp')
        .createSync(recursive: true);
    final p = fazerBackup(dados, DateTime(2026, 11, 8, 9, 5, 3));
    expect(p, '$dados${sep}backup${sep}pre-$versaoApp-20261108-090503');
    expect(conteudo(p).keys.toSet(), {
      '2026-01.json',
      'config.json',
      'token.json',
    });
    expect(
      Directory('$dados${sep}backup$sep.pre-$versaoApp-20261108-090503.tmp')
          .existsSync(),
      isFalse,
    );
  });

  test('pasta de dados inexistente lança FileSystemException', () {
    expect(
      () => fazerBackup('${tmp.path}${sep}nada', DateTime(2026)),
      throwsA(isA<FileSystemException>()),
    );
  });
}
