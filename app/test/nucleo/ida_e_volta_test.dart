@Tags(['ida_e_volta'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/compat/json_python.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
import 'package:calculadoradarf/nucleo/planilha/sincronizacao.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

// Ida e volta Dart -> Python: para cada roteiro de sincronizacao.json grava em
// build/ida_e_volta/<nome>.json o que o Dart grava na planilha (linhas e
// células) e o estado local que ele espera ler de volta. Quem confere é
// ferramentas/conferir_ida_e_volta.py (py -3.12, na raiz do repositório).

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('grava a ida e volta de cada roteiro de sincronização', () {
    final pasta = Directory('build/ida_e_volta');
    if (pasta.existsSync()) pasta.deleteSync(recursive: true);
    pasta.createSync(recursive: true);

    final casos = carregarCasos('sincronizacao');
    expect(casos, isNotEmpty);
    for (final caso in casos) {
      final entrada = _mapa(caso.entrada);
      ambiente = Ambiente.fixo(agora: (entrada['agora']! as num).toDouble());
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final cfg = repo.lerConfig();
      final abas = <String, List<Linha>>{
        for (final e in _mapa(entrada['abas']).entries)
          e.key: [
            for (final l in e.value! as List<Object?>)
              List<Object?>.of(l! as List<Object?>),
          ],
      };

      final r = sincronizarLinhas(repo, cfg, abas);

      final doc = {
        'nome': caso.nome,
        'linhas': r.linhas,
        'celulas': {
          for (final e in r.linhas.entries)
            e.key: [
              for (final l in e.value) [for (final v in l) celula(v)],
            ],
        },
        'estado': {
          'meses': {
            for (final e in repo.carregarMeses().entries)
              e.key: e.value.toJson(),
          },
          'cfg': cfg.toJson(),
        },
      };
      File('${pasta.path}/${caso.nome}.json')
          .writeAsStringSync(jsonPython(doc), encoding: utf8);
    }
    // um arquivo por caso: o conferidor Python recusa pasta parcial
    expect(pasta.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      for (final c in casos) '${c.nome}.json',
    });
  });
}
