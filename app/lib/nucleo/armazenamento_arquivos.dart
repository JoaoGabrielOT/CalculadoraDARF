import 'dart:convert';
import 'dart:io';

import 'armazenamento.dart';

/// Arquivos numa pasta do disco, em UTF-8 sem BOM. A gravação vai para um
/// `.tmp` e é renomeada, para nunca deixar um arquivo pela metade.
class ArmazenamentoArquivos implements Armazenamento {
  ArmazenamentoArquivos(this.pasta);

  final String pasta;

  File _arquivo(String nome) => File('$pasta${Platform.pathSeparator}$nome');

  @override
  String? ler(String nome) {
    final arquivo = _arquivo(nome);
    if (!arquivo.existsSync()) return null;
    return utf8.decode(arquivo.readAsBytesSync());
  }

  @override
  void gravar(String nome, String conteudo) {
    Directory(pasta).createSync(recursive: true);
    final temporario = _arquivo('$nome.tmp');
    temporario.writeAsBytesSync(utf8.encode(conteudo), flush: true);
    temporario.renameSync(_arquivo(nome).path);
  }

  @override
  bool existe(String nome) => _arquivo(nome).existsSync();

  @override
  List<String> listar() {
    final dir = Directory(pasta);
    if (!dir.existsSync()) return [];
    return [
      for (final e in dir.listSync(followLinks: false))
        if (e is File) e.uri.pathSegments.last,
    ];
  }

  @override
  void apagar(String nome) {
    final arquivo = _arquivo(nome);
    if (arquivo.existsSync()) arquivo.deleteSync();
  }
}
