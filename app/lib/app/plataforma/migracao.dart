// Migração dos dados da 1.12 (Flet) para a pasta `dados/` do app Flutter.
// Copia sem sobrescrever e sem apagar a origem; roda uma vez (marcador).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../../nucleo/nucleo.dart';

const nomeMarcadorMigracao = '.migrado_1_12.json'; // dentro de dados/
const nomeArquivoOrigem =
    'migracao_origem.txt'; // na pasta de suporte, pai de dados/

class ResultadoMigracao {
  const ResultadoMigracao({
    this.origem,
    this.copiados = 0,
    this.divergentes = const [],
    this.erro,
  });

  /// null = nada migrado nesta partida.
  final String? origem;
  final int copiados;

  /// Caminhos relativos, ordenados.
  final List<String> divergentes;
  final String? erro;
}

final _arquivoMes = RegExp(r'^\d{4}-\d{2}\.json$');

String _normalizado(String caminho) {
  var c = caminho.replaceAll('\\', '/');
  while (c.length > 1 && c.endsWith('/')) {
    c = c.substring(0, c.length - 1);
  }
  return Platform.isWindows ? c.toLowerCase() : c;
}

String _nomeBase(String caminho) {
  final c = caminho.replaceAll('\\', '/');
  return c.substring(c.lastIndexOf('/') + 1);
}

bool _dentroDe(String caminho, String pasta) {
  final c = _normalizado(caminho);
  final p = _normalizado(pasta);
  return c == p || c.startsWith('$p/');
}

bool _ehCandidata(Directory pasta) {
  try {
    for (final e in pasta.listSync(followLinks: false)) {
      if (e is! File) continue;
      final nome = _nomeBase(e.path);
      if (nome == 'config.json' || _arquivoMes.hasMatch(nome)) return true;
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

/// Pasta de dados da 1.12 no Windows: a primeira linha de
/// `<pastaSuporte>/migracao_origem.txt` (gravada pelo instalador).
List<String> origensWindows(String pastaSuporte) {
  try {
    final arquivo = File(
      '$pastaSuporte${Platform.pathSeparator}$nomeArquivoOrigem',
    );
    if (!arquivo.existsSync()) return [];
    var bytes = arquivo.readAsBytesSync();
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    final texto = utf8.decode(bytes, allowMalformed: true);
    for (final linha in const LineSplitter().convert(texto)) {
      final t = linha.trim();
      if (t.isEmpty) continue;
      return Directory(t).existsSync() ? [t] : [];
    }
  } on FileSystemException {
    return [];
  }
  return [];
}

/// Pastas candidatas sob [raizes] (a do Flet guardava os dados em
/// `FLET_APP_STORAGE_DATA`, dentro de `/data/data/<appId>/`).
List<String> origensAndroid(
  List<String> raizes, {
  required String destino,
  int profundidade = 4,
}) {
  final achadas = <String>[];
  void varrer(Directory pasta, int nivel) {
    if (_dentroDe(pasta.path, destino)) return;
    if (_ehCandidata(pasta)) achadas.add(pasta.path);
    if (nivel >= profundidade) return;
    try {
      for (final e in pasta.listSync(followLinks: false)) {
        if (e is Directory) varrer(e, nivel + 1);
      }
    } on FileSystemException {
      return;
    }
  }

  for (final raiz in raizes) {
    final d = Directory(raiz);
    if (d.existsSync()) varrer(d, 0);
  }
  int mod(String pasta) {
    try {
      return File('$pasta/config.json')
          .lastModifiedSync()
          .millisecondsSinceEpoch;
    } on FileSystemException {
      return 0;
    }
  }

  final comToken = [
    for (final p in achadas)
      if (File('$p/token.json').existsSync()) p,
  ];
  final resto = [
    for (final p in achadas)
      if (!comToken.contains(p)) p,
  ];
  return [
    ...comToken,
    ...ordenadoPor(resto, (p) => [mod(p)], reverso: true),
  ];
}

/// O que o Dart lê de [original] preserva tudo o que ele tinha (chaves a mais
/// no reconstruído são os padrões).
bool preservaOriginal(Object? original, Object? reconstruido) {
  if (original is Map) {
    if (reconstruido is! Map) return false;
    for (final e in original.entries) {
      if (!reconstruido.containsKey(e.key)) return false;
      if (!preservaOriginal(e.value, reconstruido[e.key])) return false;
    }
    return true;
  }
  if (original is List) {
    if (reconstruido is! List || reconstruido.length != original.length) {
      return false;
    }
    for (var i = 0; i < original.length; i++) {
      if (!preservaOriginal(original[i], reconstruido[i])) return false;
    }
    return true;
  }
  return original == reconstruido; // 1 == 1.0 no Dart
}

bool _leituraPreserva(File arquivo, String nome) {
  try {
    var texto = utf8.decode(arquivo.readAsBytesSync());
    if (texto.startsWith('﻿')) texto = texto.substring(1);
    final json = jsonPythonDecode(texto);
    if (json is! Map) return false;
    final mapa = Map<String, Object?>.from(json);
    final reconstruido = nome == 'config.json'
        ? Config.fromJson(mapa).toJson()
        : Mes.fromJson(mapa).toJson();
    return preservaOriginal(json, reconstruido);
  } catch (_) {
    return false;
  }
}

ResultadoMigracao migrarDados112({
  required String destino,
  required List<String> origens,
}) {
  try {
    if (File('$destino/$nomeMarcadorMigracao').existsSync()) {
      return const ResultadoMigracao();
    }
    String? origem;
    for (final o in origens) {
      if (_normalizado(o) == _normalizado(destino)) continue;
      if (_ehCandidata(Directory(o))) {
        origem = o;
        break;
      }
    }
    if (origem == null) return const ResultadoMigracao();

    Directory(destino).createSync(recursive: true);
    var copiados = 0;
    final divergentes = <String>[];
    final base = _normalizado(origem).length;
    for (final e in Directory(
      origem,
    ).listSync(recursive: true, followLinks: false)) {
      final rel = e.path
          .replaceAll('\\', '/')
          .substring(base)
          .replaceAll(RegExp(r'^/+'), '');
      if (rel.isEmpty || rel == nomeMarcadorMigracao) continue;
      final alvo = '$destino/$rel';
      if (e is Directory) {
        Directory(alvo).createSync(recursive: true);
      } else if (e is File) {
        if (File(alvo).existsSync()) continue;
        Directory(File(alvo).parent.path).createSync(recursive: true);
        e.copySync(alvo);
        copiados++;
        if ((rel == 'config.json' || _arquivoMes.hasMatch(rel)) &&
            !_leituraPreserva(e, rel)) {
          divergentes.add(rel);
        }
      }
    }
    final ordenados = ordenadoPor(divergentes, (d) => [d]);
    File('$destino/$nomeMarcadorMigracao').writeAsStringSync(
      jsonEncode({
        'origem': origem,
        'em': DateTime.now().toIso8601String(),
        'copiados': copiados,
        'divergentes': ordenados,
      }),
    );
    return ResultadoMigracao(
      origem: origem,
      copiados: copiados,
      divergentes: ordenados,
    );
  } on FileSystemException catch (e) {
    return ResultadoMigracao(erro: e.toString());
  }
}

/// Aviso a mostrar depois da migração; null com sucesso limpo.
(String, String)? avisoMigracao(ResultadoMigracao r) {
  if (r.erro != null) {
    return (
      'Dados da versão anterior',
      'Não foi possível copiar os dados da versão anterior: ${r.erro}. '
          'O app tenta de novo na próxima abertura.',
    );
  }
  if (r.divergentes.isNotEmpty) {
    return (
      'Dados da versão anterior',
      'Copiados ${r.copiados} arquivos de ${r.origem}. Confira estes '
          'arquivos, que não foram lidos por inteiro: '
          '${r.divergentes.join(', ')}.',
    );
  }
  return null;
}

/// Roda a migração fora da thread da interface (muitas imagens). Nunca lança.
Future<ResultadoMigracao> migrarNaPartida({
  required String pastaSuporte,
  required String destino,
  required bool windows,
  List<String> raizesAndroid = const [],
}) async {
  try {
    final origens = windows
        ? origensWindows(pastaSuporte)
        : origensAndroid(raizesAndroid, destino: destino);
    return await Isolate.run(
      () => migrarDados112(destino: destino, origens: origens),
    );
  } catch (e) {
    return ResultadoMigracao(erro: e.toString());
  }
}

/// Migração da partida com as pastas reais do app (usada por `iniciarApp`):
/// `pastaSuporte` é o pai de [dados]; no Android as raízes são as do Flet.
Future<ResultadoMigracao> migrarDadosDoApp({
  required String dados,
  required bool windows,
}) async {
  try {
    return await migrarNaPartida(
      pastaSuporte: Directory(dados).parent.path,
      destino: dados,
      windows: windows,
      raizesAndroid: windows
          ? const []
          : [
              (await getApplicationSupportDirectory()).path,
              (await getApplicationDocumentsDirectory()).path,
            ],
    );
  } catch (e) {
    return ResultadoMigracao(erro: e.toString());
  }
}
