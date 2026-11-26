// Relatórios de abertura no Drive: listagem da pasta e download do JSON.

import 'constantes.dart';
import 'sessao.dart';

/// Pasta "Calculadora DARF - Relatórios", preenchida por uma automação externa.
const pastaRelatorios = '1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B';

const consultaRelatorios =
    "'1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B' in parents and trashed = false and name contains 'relatorio-abertura-'";

/// Limite de páginas da listagem, contra um `nextPageToken` que nunca acaba.
const _maxPaginas = 50;

class ArquivoRelatorio {
  const ArquivoRelatorio({
    required this.id,
    required this.nome,
    required this.modificado,
  });

  final String id, nome, modificado;
}

/// Os arquivos da pasta são de outro cliente: só o `drive.readonly` os enxerga.
bool podeLerRelatorios(List<String>? escopos) =>
    escopos?.contains(escopoRelatorios) ?? false;

abstract interface class FonteRelatorios {
  List<String>? get escopos;

  Future<List<ArquivoRelatorio>> listar();

  Future<Map<String, Object?>> baixar(String id);
}

class DriveRelatorios implements FonteRelatorios {
  DriveRelatorios(this.sessao);

  final SessaoGoogle sessao;

  @override
  List<String>? get escopos => sessao.escopos;

  /// `files.list` paginado; itens sem `id`, `name` ou `modifiedTime` texto
  /// ficam de fora.
  @override
  Future<List<ArquivoRelatorio>> listar() async {
    final arquivos = <ArquivoRelatorio>[];
    final vistas = <String>{};
    String? pagina;
    for (var i = 0; i < _maxPaginas; i++) {
      final r = await sessao.req(
        'GET',
        '$urlDrive/files',
        params: {
          'q': consultaRelatorios,
          'fields': 'nextPageToken,files(id,name,modifiedTime)',
          'pageSize': 100,
          'pageToken': ?pagina,
        },
      );
      final files = r['files'];
      if (files is List) {
        for (final f in files) {
          if (f is! Map) continue;
          final id = f['id'], nome = f['name'], modificado = f['modifiedTime'];
          if (id is String && nome is String && modificado is String) {
            arquivos.add(
              ArquivoRelatorio(id: id, nome: nome, modificado: modificado),
            );
          }
        }
      }
      final proxima = r['nextPageToken'];
      if (proxima is! String || proxima.isEmpty || !vistas.add(proxima)) break;
      pagina = proxima;
    }
    return arquivos;
  }

  /// `files.get` com `alt=media`: o conteúdo do JSON.
  @override
  Future<Map<String, Object?>> baixar(String id) =>
      sessao.req('GET', '$urlDrive/files/$id', params: {'alt': 'media'});
}
