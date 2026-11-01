// Cache de arquivos binários (imagens e logos): mesmos nomes de arquivo do Python
// (`dados/noticias_img/`, `dados/logos/`), porque o plano 4 migra a pasta `dados/`.

import 'dart:io';
import 'dart:typed_data';

/// Arquivos binários por nome relativo; `/` no nome separa subpastas.
abstract interface class CacheBinario {
  Future<Uint8List?> ler(String nome);

  Future<void> gravar(String nome, List<int> bytes);

  Future<DateTime?> modificadoEm(String nome);

  Future<void> apagar(String nome);
}

/// Cache em memória (testes); [relogio] dá a data de gravação.
class CacheBinarioMemoria implements CacheBinario {
  CacheBinarioMemoria({DateTime Function()? relogio})
    : _relogio = relogio ?? DateTime.now;

  final DateTime Function() _relogio;
  final Map<String, (Uint8List, DateTime)> _arquivos = {};

  @override
  Future<Uint8List?> ler(String nome) async {
    final a = _arquivos[nome];
    return a == null ? null : Uint8List.fromList(a.$1);
  }

  @override
  Future<void> gravar(String nome, List<int> bytes) async {
    _arquivos[nome] = (Uint8List.fromList(bytes), _relogio());
  }

  @override
  Future<DateTime?> modificadoEm(String nome) async => _arquivos[nome]?.$2;

  @override
  Future<void> apagar(String nome) async {
    _arquivos.remove(nome);
  }
}

/// Cache em uma pasta do disco; grava em `.tmp` e renomeia, para nunca deixar
/// um arquivo pela metade.
class CacheBinarioArquivos implements CacheBinario {
  CacheBinarioArquivos(this.pasta);

  final String pasta;
  int _sequencia = 0;

  File _arquivo(String nome) => File('$pasta/$nome');

  @override
  Future<Uint8List?> ler(String nome) async {
    try {
      return await _arquivo(nome).readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> gravar(String nome, List<int> bytes) async {
    final destino = _arquivo(nome);
    await destino.parent.create(recursive: true);
    final temporario = File('${destino.path}.${_sequencia++}.tmp');
    try {
      await temporario.writeAsBytes(bytes, flush: true);
      await temporario.rename(destino.path);
    } catch (_) {
      if (temporario.existsSync()) temporario.deleteSync();
      rethrow;
    }
  }

  @override
  Future<DateTime?> modificadoEm(String nome) async {
    try {
      return await _arquivo(nome).lastModified();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> apagar(String nome) async {
    try {
      await _arquivo(nome).delete();
    } on PathNotFoundException {
      // já não existe
    }
  }
}
