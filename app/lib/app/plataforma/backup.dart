// Backup da pasta de dados antes de uma migração (§11). Recuperação: fechar
// o app, copiar os arquivos de `backup/pre-<versão>-*/` de volta para a pasta
// de dados e reinstalar a versão anterior.

import 'dart:io';

import '../../nucleo/compat/ordenacao.dart';
import '../../versao.dart';

String _dois(int n) => n.toString().padLeft(2, '0');

String _nome(FileSystemEntity e) =>
    e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

/// Copia todos os `*.json` de [pastaDados] (sem subpastas) para
/// `backup/pre-<versaoApp>-AAAAMMDD-HHMMSS/`, confere quantidade e tamanhos e
/// devolve a pasta. Diferença ou falha de cópia lança [FileSystemException].
///
/// Um backup por versão: se já existe um `pre-<versaoApp>-*`, devolve ele sem
/// copiar de novo (o primeiro é o dos dados de antes da versão). A cópia é
/// feita numa pasta temporária renomeada só depois da conferência, então uma
/// pasta `pre-*` existente está sempre completa.
String fazerBackup(String pastaDados, DateTime agora) {
  final sep = Platform.pathSeparator;
  final raiz = Directory('$pastaDados${sep}backup');
  final prefixo = 'pre-$versaoApp-';
  if (raiz.existsSync()) {
    final feitos = [
      for (final d in raiz.listSync().whereType<Directory>())
        if (_nome(d).startsWith(prefixo)) d.path,
    ];
    if (feitos.isNotEmpty) return ordenadoPor(feitos, (p) => [p]).first;
  }
  final origem = [
    for (final f in Directory(pastaDados).listSync().whereType<File>())
      if (f.path.toLowerCase().endsWith('.json')) f,
  ];
  final carimbo =
      '${agora.year}${_dois(agora.month)}${_dois(agora.day)}-'
      '${_dois(agora.hour)}${_dois(agora.minute)}${_dois(agora.second)}';
  final pasta = '${raiz.path}$sep$prefixo$carimbo';
  final temporaria = Directory('${raiz.path}$sep.$prefixo$carimbo.tmp');
  if (temporaria.existsSync()) temporaria.deleteSync(recursive: true);
  temporaria.createSync(recursive: true);
  try {
    for (final f in origem) {
      f.copySync('${temporaria.path}$sep${_nome(f)}');
    }
    final copias = {
      for (final f in temporaria.listSync().whereType<File>())
        _nome(f): f.lengthSync(),
    };
    if (copias.length != origem.length ||
        origem.any((f) => copias[_nome(f)] != f.lengthSync())) {
      throw FileSystemException('Backup incompleto', temporaria.path);
    }
    temporaria.renameSync(pasta);
  } catch (_) {
    try {
      temporaria.deleteSync(recursive: true);
    } catch (_) {
      // a pasta temporária não conta como backup
    }
    rethrow;
  }
  return pasta;
}
