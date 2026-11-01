// Cache de arquivos binários (imagens e logos): mesmos nomes de arquivo do Python
// (`dados/noticias_img/`, `dados/logos/`), porque o plano 4 migra a pasta `dados/`.

import 'dart:io';
import 'dart:math';
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
  static final _sorteio = Random();

  File _arquivo(String nome) => File('$pasta/$nome');

  bool _varrido = false;

  /// Remove restos `.tmp` (de gravações interrompidas) com mais de 1 hora; uma
  /// varredura só por instância, e uma falha em um arquivo não impede os outros.
  void _limparTemporariosAntigos(File destino) {
    if (_varrido) return;
    _varrido = true;
    final limite = DateTime.now().subtract(const Duration(hours: 1));
    try {
      final dir = Directory(pasta);
      if (!dir.existsSync()) return;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File || !e.path.endsWith('.tmp')) continue;
        try {
          if (e.lastModifiedSync().isBefore(limite)) e.deleteSync();
        } on FileSystemException {
          // outro processo pode ter mexido nele
        }
      }
    } on FileSystemException {
      // limpeza é só higiene
    }
  }

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
    _limparTemporariosAntigos(destino);
    // Sufixo aleatório: duas instâncias (ou execuções) não se atropelam.
    final temporario = File(
      '${destino.path}.${_sorteio.nextInt(1 << 32).toRadixString(16)}.tmp',
    );
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
