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

  test('backup no mesmo segundo vai para outra pasta e não copia backups', () {
    final agora = DateTime(2026, 11, 8, 9, 5, 3);
    final p1 = fazerBackup(dados, agora);
    final p2 = fazerBackup(dados, agora);
    expect(p2, isNot(p1));
    expect(p2.startsWith('$dados${sep}backup${sep}pre-$versaoApp-'), isTrue);
    expect(conteudo(p2).keys.toSet(), conteudo(p1).keys.toSet());
    expect(Directory(p2).listSync().whereType<Directory>(), isEmpty);
  });

  test('pasta de dados inexistente lança FileSystemException', () {
    expect(
      () => fazerBackup('${tmp.path}${sep}nada', DateTime(2026)),
      throwsA(isA<FileSystemException>()),
    );
  });
}
