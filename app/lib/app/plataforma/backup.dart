// Backup da pasta de dados antes de uma migração (§11). Recuperação: fechar
// o app, copiar os arquivos de `backup/pre-<versão>-*/` de volta para a pasta
// de dados e reinstalar a versão anterior.

import 'dart:io';

import '../../versao.dart';

String _dois(int n) => n.toString().padLeft(2, '0');

/// Copia todos os `*.json` de [pastaDados] (sem subpastas) para
/// `backup/pre-<versaoApp>-AAAAMMDD-HHMMSS/`, confere quantidade e tamanhos e
/// devolve a pasta. Diferença ou falha de cópia lança [FileSystemException].
String fazerBackup(String pastaDados, DateTime agora) {
  final sep = Platform.pathSeparator;
  final origem = [
    for (final f in Directory(pastaDados).listSync().whereType<File>())
      if (f.path.toLowerCase().endsWith('.json')) f,
  ];
  final carimbo =
      '${agora.year}${_dois(agora.month)}${_dois(agora.day)}-'
      '${_dois(agora.hour)}${_dois(agora.minute)}${_dois(agora.second)}';
  final base = '$pastaDados${sep}backup${sep}pre-$versaoApp-$carimbo';
  var pasta = base;
  // dois backups no mesmo segundo não se misturam
  for (var i = 2; Directory(pasta).existsSync(); i++) {
    pasta = '$base-$i';
  }
  Directory(pasta).createSync(recursive: true);
  for (final f in origem) {
    f.copySync('$pasta$sep${f.uri.pathSegments.last}');
  }
  final copias = {
    for (final f in Directory(pasta).listSync().whereType<File>())
      f.uri.pathSegments.last: f.lengthSync(),
  };
  if (copias.length != origem.length ||
      origem.any((f) => copias[f.uri.pathSegments.last] != f.lengthSync())) {
    throw FileSystemException('Backup incompleto', pasta);
  }
  return pasta;
}
