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

/// Roteiro só do Dart (sem referência do Python; o conferidor aceita os
/// nomes com `dart_`): mês fechado sem marcador e mês aberto com o marcador de
/// custo médio (coluna 14 do Resumo) e uma venda de duas compras (`g.1`/`g.2`).
const _marcadorEGrupo = 'dart_marcador_e_grupo';

final _entradaMarcadorEGrupo = <String, Object?>{
  'agora': 1763000000.25,
  'arquivos': {
    '2026-10.json': {
      'mes': '2026-10',
      'fechado': true,
      'darf_anterior': 0.0,
      'lotes': <Object?>[],
      'excluidos': <String, Object?>{},
      'mod': 40.5,
    },
    '2026-11.json': {
      'mes': '2026-11',
      'fechado': false,
      'darf_anterior': 0.0,
      'lotes': [
        {
          'id': 'c1',
          'ticker': 'VALE3',
          'tipo': 'Ação',
          'data_compra': '2026-09-15',
          'qtd': 10,
          'preco': 60.0,
          'vendas': <Object?>[],
          'mod': 41.5,
          'origem': 'v0',
        },
        {
          'id': 'a1',
          'ticker': 'PETR4',
          'tipo': 'Ação',
          'data_compra': '2026-11-03',
          'qtd': 100,
          'preco': 25.0,
          'vendas': [
            {
              'id': 'g.1',
              'data': '2026-11-10',
              'qtd': 30,
              'preco': 30.0,
              'mod': 42.5,
            },
          ],
          'mod': 41.5,
        },
        {
          'id': 'b1',
          'ticker': 'PETR4',
          'tipo': 'Ação',
          'data_compra': '2026-11-04',
          'qtd': 50,
          'preco': 27.0,
          'vendas': [
            {
              'id': 'g.2',
              'data': '2026-11-10',
              'qtd': 20,
              'preco': 30.0,
              'mod': 42.5,
            },
          ],
          'mod': 41.5,
        },
      ],
      'excluidos': <String, Object?>{},
      'mod': 42.5,
      'metodo': 'custo_medio',
      'posicao_inicial': {
        'VALE3': {'qtd': 10, 'custo': 600.0},
      },
      'prejuizo_anterior': {'comum': 12.5, 'day_trade': 0.0},
    },
    'config.json': {'tema': 'Dark'},
  },
  'abas': <String, Object?>{},
};

/// Sincroniza o roteiro [entrada], grava `<pasta>/<nome>.json` e devolve as
/// linhas gravadas na planilha.
Map<String, List<Linha>> _gravar(
  Directory pasta,
  String nome,
  Map<String, Object?> entrada,
) {
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
    'nome': nome,
    'linhas': r.linhas,
    'celulas': {
      for (final e in r.linhas.entries)
        e.key: [
          for (final l in e.value) [for (final v in l) celula(v)],
        ],
    },
    'estado': {
      'meses': {
        for (final e in repo.carregarMeses().entries) e.key: e.value.toJson(),
      },
      'cfg': cfg.toJson(),
    },
  };
  File('${pasta.path}/$nome.json')
      .writeAsStringSync(jsonPython(doc), encoding: utf8);
  return r.linhas;
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('grava a ida e volta de cada roteiro de sincronização', () {
    final pasta = Directory('build/ida_e_volta');
    if (pasta.existsSync()) pasta.deleteSync(recursive: true);
    pasta.createSync(recursive: true);

    final casos = carregarCasos('sincronizacao');
    expect(casos, isNotEmpty);
    for (final caso in casos) {
      _gravar(pasta, caso.nome, _mapa(caso.entrada));
    }
    final linhas = _gravar(pasta, _marcadorEGrupo, _entradaMarcadorEGrupo);
    expect(
      [for (final l in linhas['Resumo']!) l[13]],
      [
        '',
        '{"mes":"2026-11","metodo":"custo_medio",'
            '"posicao_inicial":{"VALE3":{"qtd":10,"custo":600.0}},'
            '"prejuizo_anterior":{"comum":12.5,"day_trade":0.0}}',
      ],
    );
    expect([for (final l in linhas['Vendas']!) l[14]], ['g.1', 'g.2']);
    // um arquivo por caso: o conferidor Python recusa pasta parcial
    expect(pasta.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      for (final c in casos) '${c.nome}.json',
      '$_marcadorEGrupo.json',
    });
  });
}
