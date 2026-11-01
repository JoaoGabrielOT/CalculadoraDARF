// Atualizador (atualizador.py:21-98): consulta a última release do GitHub e
// baixa o instalador/APK conferindo tamanho e sha256. Trocar o executável e
// abrir o APK ficam para os planos 3 e 4, pela interface [InstalarAtualizacao].

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../nucleo/erros.dart';
import '../../versao.dart';
import '../executor.dart';
import '../http/cliente.dart';
import '../http/erros.dart';
import '../http/json.dart';

const repositorioGithub = 'JoaoGabrielOT/CalculadoraDARF';
const urlUltimaVersao =
    'https://api.github.com/repos/$repositorioGithub/releases/latest';
const nomeAssetWindows = 'CalculadoraDARF.exe';
const nomeAssetAndroid = 'CalculadoraDARF.apk';

/// Asset da release para a plataforma atual (ou a indicada, nos testes).
String nomeAssetDaPlataforma({bool? windows}) =>
    (windows ?? Platform.isWindows) ? nomeAssetWindows : nomeAssetAndroid;

/// `ErroAtualizacao` do Python.
class ErroAtualizacao extends ErroNucleo {
  ErroAtualizacao(super.mensagem);
}

/// Nova versão publicada; [sha256] vazio quando o GitHub não informa o `digest`.
class InfoAtualizacao {
  const InfoAtualizacao({
    required this.versao,
    required this.notas,
    required this.url,
    required this.tamanho,
    required this.sha256,
  });

  final String versao;
  final String notas;
  final String url;
  final int tamanho;
  final String sha256;
}

/// Executa a instalação do arquivo baixado (plano 3: Windows; plano 4: Android).
typedef InstalarAtualizacao = Future<void> Function(File arquivo);

/// `versao_tupla`: até três números do texto, completando com zeros.
(int, int, int) versaoTupla(String v) {
  final nums = RegExp(r'\d+')
      .allMatches(v.replaceFirst(RegExp(r'^[vV]+'), ''))
      .map((m) => int.tryParse(m[0]!) ?? 0)
      .take(3)
      .toList();
  int n(int i) => i < nums.length ? nums[i] : 0;
  return (n(0), n(1), n(2));
}

/// `versao_tupla(tag) > versao_tupla(atual)`.
bool versaoMaisNova(String tag, String atual) {
  final (a1, a2, a3) = versaoTupla(tag);
  final (b1, b2, b3) = versaoTupla(atual);
  if (a1 != b1) return a1 > b1;
  if (a2 != b2) return a2 > b2;
  return a3 > b3;
}

/// Dados da nova versão, ou `null` se não há (404, draft, prerelease, tag que
/// não é mais nova ou release sem o asset).
Future<InfoAtualizacao?> verificarAtualizacao(
  ClienteHttp http, {
  required String nomeAsset,
  String versaoAtual = versaoApp,
  Executar executar = executarEmIsolate,
}) async {
  final url = Uri.parse(urlUltimaVersao);
  final r = await http.enviar(
    'GET',
    url,
    cabecalhos: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'CalculadoraDARF',
    },
    tempoLimite: const Duration(seconds: 15),
  );
  if (r.statusCode == 404) return null;
  conferirStatus(r.statusCode, url, motivo: r.reasonPhrase);
  final Map<Object?, Object?> rel;
  try {
    rel = await decodificarJson(r.bodyBytes, executar) as Map<Object?, Object?>;
  } on FormatException {
    throw ErroAtualizacao('Resposta inválida do GitHub.');
  } on TypeError {
    throw ErroAtualizacao('Resposta inválida do GitHub.');
  }
  if (_verdadeiro(rel['draft']) || _verdadeiro(rel['prerelease'])) return null;
  final tag = rel['tag_name'] as String? ?? '';
  if (!versaoMaisNova(tag, versaoAtual)) return null;
  final assets = rel['assets'] as List? ?? const [];
  final asset = assets.cast<Map<String, Object?>>().where(
    (a) => a['name'] == nomeAsset,
  );
  if (asset.isEmpty) return null;
  final a = asset.first;
  final digest = a['digest'] as String? ?? '';
  return InfoAtualizacao(
    versao: tag.replaceFirst(RegExp(r'^[vV]+'), ''),
    notas: (rel['body'] as String? ?? '').trim(),
    url: a['browser_download_url']! as String,
    tamanho: (a['size'] as num?)?.toInt() ?? 0,
    sha256: digest.startsWith('sha256:') ? digest.substring(7) : '',
  );
}

/// Valor "verdadeiro" do Python para um campo JSON.
bool _verdadeiro(Object? v) => v != null && v != false && v != 0 && v != '';

/// Guarda o resultado do cálculo em fluxo do sha256.
class _GuardaDigest implements Sink<Digest> {
  Digest? valor;

  @override
  void add(Digest data) => valor = data;

  @override
  void close() {}
}

/// Baixa a atualização para [destino]. O corpo vai para um `.tmp` ao lado e só
/// vira [destino] depois de conferido; qualquer falha (inclusive cancelamento)
/// apaga só o parcial e relança o erro original. O [destino] não é apagado em
/// falha: ele só é tocado no rename final, e um instalador válido baixado antes
/// não deve ser descartado por uma tentativa que falhou. A limpeza é
/// melhor-esforço e nunca substitui o erro original.
Future<File> baixarAtualizacao(
  ClienteHttp http,
  InfoAtualizacao info,
  File destino, {
  void Function(int baixado, int total)? progresso,
  bool Function()? cancelado,
}) async {
  final parcial = File('${destino.path}.tmp');
  try {
    return await _baixar(http, info, destino, parcial, progresso, cancelado);
  } catch (_) {
    await _apagar(parcial);
    rethrow;
  }
}

Future<void> _apagar(File arquivo) async {
  try {
    await arquivo.delete();
  } on FileSystemException {
    // Melhor-esforço (já não existe, ou o antivírus o segura): não esconde o erro original.
  }
}

Future<File> _baixar(
  ClienteHttp http,
  InfoAtualizacao info,
  File destino,
  File parcial,
  void Function(int baixado, int total)? progresso,
  bool Function()? cancelado,
) async {
  void conferirCancelado() {
    if (cancelado?.call() ?? false) {
      throw ErroAtualizacao('Atualização cancelada.');
    }
  }

  conferirCancelado();
  final url = Uri.parse(info.url);
  final resposta = await http.abrir(
    'GET',
    url,
    cabecalhos: const {'User-Agent': 'CalculadoraDARF'},
    tempoLimite: const Duration(seconds: 30),
  );
  try {
    conferirStatus(resposta.status, url, motivo: resposta.motivo);
    final total =
        int.tryParse(_cabecalho(resposta.cabecalhos, 'content-length')) ??
        (info.tamanho > 0 ? info.tamanho : 0);

    final guarda = _GuardaDigest();
    final hash = sha256.startChunkedConversion(guarda);
    var baixado = 0;
    final arquivo = await parcial.open(mode: FileMode.write);
    try {
      await for (final bloco in resposta.blocos) {
        if (bloco.isEmpty) continue;
        if (cancelado?.call() ?? false) {
          throw ErroAtualizacao('Atualização cancelada.');
        }
        await arquivo.writeFrom(bloco);
        hash.add(bloco);
        baixado += bloco.length;
        progresso?.call(baixado, total);
      }
    } finally {
      await arquivo.close();
    }
    hash.close();
    conferirCancelado();

    if (info.tamanho > 0 && baixado != info.tamanho) {
      throw ErroAtualizacao('O download ficou incompleto.');
    }
    if (info.sha256.isNotEmpty &&
        guarda.valor.toString().toLowerCase() != info.sha256.toLowerCase()) {
      throw ErroAtualizacao('O arquivo baixado não confere com o publicado.');
    }
    return await parcial.rename(destino.path);
  } on FileSystemException {
    await _soltar(resposta);
    throw ErroAtualizacao(
      'Não foi possível gravar a atualização no disco. Verifique o espaço livre.',
    );
  } catch (_) {
    // Também solta o socket quando o erro é de escrita ou do próprio fluxo.
    await _soltar(resposta);
    rethrow;
  }
}

Future<void> _soltar(RespostaContinua resposta) async {
  try {
    await resposta.cancelar();
  } catch (_) {
    // Melhor-esforço.
  }
}

String _cabecalho(Map<String, String> cabecalhos, String nome) {
  for (final e in cabecalhos.entries) {
    if (e.key.toLowerCase() == nome) return e.value;
  }
  return '';
}
