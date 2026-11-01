// Planilha Google em rede: Drive e Sheets (google_sync.py:282-456).

import '../../nucleo/nucleo.dart';
import 'constantes.dart';
import 'erros.dart';
import 'pedidos.dart';
import 'sessao.dart';

/// Endereço para abrir a planilha no navegador.
String linkPlanilha(String sid) =>
    'https://docs.google.com/spreadsheets/d/$sid';

Map<String, Object?> _mapa(Object? o) =>
    o is Map ? o.cast<String, Object?>() : <String, Object?>{};

List<Object?> _lista(Object? o) => o is List ? o : const <Object?>[];

PropriedadesAba _propriedades(Object? bruta) {
  final p = _mapa(bruta);
  final g = _mapa(p['gridProperties']);
  return PropriedadesAba(
    sheetId: p['sheetId']! as int,
    titulo: p['title']! as String,
    linhas: g['rowCount'] as int?,
    colunas: g['columnCount'] as int?,
  );
}

class PlanilhaGoogle {
  PlanilhaGoogle(this.sessao);

  final SessaoGoogle sessao;

  Future<String?> buscarPlanilha([String dono = 'me']) async {
    final r = await sessao.req(
      'GET',
      '$urlDrive/files',
      params: {
        'q': consultaPlanilha(dono),
        'fields': 'files(id)',
        'orderBy': 'modifiedTime desc',
        'pageSize': 5,
        'spaces': 'drive',
      },
    );
    final arquivos = _lista(r['files']);
    return arquivos.isEmpty ? null : _mapa(arquivos.first)['id']! as String;
  }

  Future<bool> planilhaExiste(String sid) async {
    try {
      final r = await sessao.req(
        'GET',
        '$urlDrive/files/$sid',
        params: {'fields': 'id,trashed'},
      );
      final lixeira = r['trashed'];
      return lixeira == null || lixeira == false;
    } on ErroGoogle catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  Future<String> criarPlanilha() async {
    final r = await sessao.req('POST', urlSheets, json: corpoCriacao());
    final sid = r['spreadsheetId']! as String;
    final ids = {
      for (final s in _lista(r['sheets']))
        _mapa(_mapa(s)['properties'])['title']! as String:
            _mapa(_mapa(s)['properties'])['sheetId']! as int,
    };
    await _formatar(sid, ids);
    return sid;
  }

  Future<void> _formatar(String sid, Map<String, int> ids) async {
    await sessao.req(
      'POST',
      '$urlSheets/$sid:batchUpdate',
      json: {'requests': pedidosFormatacao(ids)},
    );
  }

  /// Cria (formatadas) as abas que faltam em planilhas de versões anteriores.
  Future<Map<String, PropriedadesAba>> garantirAbas(String sid) async {
    final meta = await sessao.req(
      'GET',
      '$urlSheets/$sid',
      params: {
        'fields': 'sheets.properties(sheetId,title,gridProperties(rowCount,columnCount))',
      },
    );
    final abas = <String, PropriedadesAba>{};
    for (final s in _lista(meta['sheets'])) {
      final p = _propriedades(_mapa(s)['properties']);
      abas[p.titulo] = p;
    }
    final faltando = [
      for (final a in esquemaAbas)
        if (!abas.containsKey(a.nome)) a.nome,
    ];
    if (faltando.isEmpty) return abas;
    final r = await sessao.req(
      'POST',
      '$urlSheets/$sid:batchUpdate',
      json: pedidoAbasFaltantes(faltando),
    );
    final ids = <String, int>{};
    for (final rep in _lista(r['replies'])) {
      final add = _mapa(rep)['addSheet'];
      if (add == null) continue;
      final p = _mapa(_mapa(add)['properties']);
      ids[p['title']! as String] = p['sheetId']! as int;
    }
    await _formatar(sid, ids);
    for (final e in ids.entries) {
      abas[e.key] = PropriedadesAba(
        sheetId: e.value,
        titulo: e.key,
        linhas: 1000,
        colunas: esquemaDe(e.key).colunas.length,
      );
    }
    return abas;
  }

  /// Substitui o conteúdo de cada aba (exceto o cabeçalho) numa só operação.
  Future<void> escrever(String sid, Map<String, List<Linha>> dados) async {
    final abas = await garantirAbas(sid);
    await sessao.req(
      'POST',
      '$urlSheets/$sid:batchUpdate',
      json: {'requests': pedidosEscrita(abas, dados)},
    );
  }

  Future<Map<String, List<Linha>>> ler(String sid) async {
    final meta = await sessao.req(
      'GET',
      '$urlSheets/$sid',
      params: {'fields': 'sheets.properties(title,gridProperties.columnCount)'},
    );
    final colunas = <String, int?>{};
    for (final s in _lista(meta['sheets'])) {
      final p = _mapa(_mapa(s)['properties']);
      colunas[p['title']! as String] =
          _mapa(p['gridProperties'])['columnCount'] as int?;
    }
    final nomes = [
      for (final a in esquemaAbas)
        if (colunas.containsKey(a.nome)) a.nome,
    ];
    if (nomes.isEmpty) return normalizarLeitura({});
    final r = await sessao.req(
      'GET',
      '$urlSheets/$sid/values:batchGet',
      params: {
        'ranges': rangesLeitura(colunas),
        'valueRenderOption': 'UNFORMATTED_VALUE',
        'dateTimeRenderOption': 'SERIAL_NUMBER',
      },
    );
    final lidas = <String, List<List<Object?>>>{};
    final intervalos = _lista(r['valueRanges']);
    for (var i = 0; i < nomes.length && i < intervalos.length; i++) {
      lidas[nomes[i]] = [
        for (final l in _lista(_mapa(intervalos[i])['values']))
          List<Object?>.of(_lista(l)),
      ];
    }
    return normalizarLeitura(lidas);
  }

  Future<void> compartilhar(String sid, String email) async {
    await sessao.req(
      'POST',
      '$urlDrive/files/$sid/permissions',
      params: {
        'sendNotificationEmail': 'true',
        'emailMessage':
            '${sessao.email} compartilhou as operações da Calculadora DARF com você.',
      },
      json: {'role': 'reader', 'type': 'user', 'emailAddress': email},
    );
  }

  Future<void> descompartilhar(String sid, String email) async {
    final r = await sessao.req(
      'GET',
      '$urlDrive/files/$sid/permissions',
      params: {'fields': 'permissions(id,emailAddress,role)'},
    );
    for (final bruta in _lista(r['permissions'])) {
      final p = _mapa(bruta);
      final dele = (p['emailAddress'] as String? ?? '').toLowerCase();
      if (dele == email && p['role'] != 'owner') {
        await sessao.req(
          'DELETE',
          '$urlDrive/files/$sid/permissions/${p['id']}',
        );
      }
    }
  }
}
