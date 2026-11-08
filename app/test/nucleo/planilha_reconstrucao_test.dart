import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/planilha/reconstrucao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

Map<String, List<Linha>> _abas(Object? entrada) => {
  for (final e in _mapa(entrada).entries)
    e.key: [
      for (final l in e.value! as List<Object?>)
        List<Object?>.of(l! as List<Object?>),
    ],
};

/// `mes_vazio` (nucleo.py:121-122) não tem a chave `mod` (vale 0 em todo
/// `.get("mod", 0)`); o `Mes` do Dart sempre a tem. Quando a referência não
/// a traz, exige `mod == 0` e a retira da comparação.
Map<String, Object?> _mesJson(Mes m, Object? esperado) {
  final json = m.toJson();
  if (!_mapa(esperado).containsKey('mod')) {
    expect(json.remove('mod'), 0.0, reason: 'mês sem mod na referência');
  }
  return json;
}

Map<String, Object?> _paraJson(DadosPlanilha d, Object? esperado) => {
  'meses': {
    for (final e in d.meses.entries)
      e.key: _mesJson(e.value, _mapa(_mapa(esperado)['meses'])[e.key]),
  },
  'amigos': [for (final a in d.amigos) a.toJson()],
  'radar': [for (final r in d.radar) r.toJson()],
  'excluidos': d.excluidos,
  'caixa': d.caixa?.toJson(),
};

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(
      versaoPythonDasReferencias('planilha_reconstrucao'),
      startsWith('3.12'),
    );
  });

  for (final caso in carregarCasos('planilha_reconstrucao')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final abas = _abas(caso.entrada);
      final dados = reconstruir(abas);
      final metas = reconstruirMetas(abas);
      conferir({
        'dados': _paraJson(dados, _mapa(caso.saida)['dados']),
        'metas': [for (final m in metas) m.toJson()],
      }, caso.saida);
    });
  }

  // O Python segue com inteiro grande (sem referência: não cabe em int64).
  test(
    'radar com Posição >= 2^63 reconstrói com pos nulo, demais intactos',
    () {
      final dados = reconstruir({
        'Radar': [
          ['PETR4', 'Petrobras', 46000, 71.5, 3],
          ['VALE3', 'Vale', 46001, 72.5, '1e19'],
          ['ITUB4', 'Itaú', 46002, 73.5, -1e30],
          ['WEGE3', 'Weg', 46003, 74.5, 7],
        ],
      });
      expect(dados.radar.map((r) => r.ticker), [
        'PETR4',
        'VALE3',
        'ITUB4',
        'WEGE3',
      ]);
      expect(dados.radar.map((r) => r.pos), [3, null, null, 7]);
      expect(dados.radar[1].mod, 72.5);
      expect(dados.radar[3].nome, 'Weg');
    },
  );

  test(
    'radar com Posição NaN ou infinita continua lançando (como o Python)',
    () {
      for (final p in ['nan', 'inf']) {
        expect(
          () => reconstruir({
            'Radar': [
              ['PETR4', 'P', 46000, 1, p],
            ],
          }),
          throwsFormatException,
          reason: p,
        );
      }
    },
  );

  group('coluna Detalhes do Resumo', () {
    const detalhes =
        '{"mes":"2026-11","metodo":"custo_medio",'
        '"posicao_inicial":{"PETR4":{"qtd":100,"custo":2550.0}},'
        '"prejuizo_anterior":{"comum":120.5,"day_trade":0.0}}';
    Linha resumo(String mes, [Object? col14]) => [
      mes, 'Aberto', 0, 'Sim', 0, 0, 0, 0, 0, 0, 0, 0, 5, //
      ?col14,
    ];

    test('coluna 14 gravada e lida', () {
      final marcado = Mes(
        mes: '2026-11',
        mod: 5,
        metodo: metodoCustoMedio,
        posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 2550.0)},
        prejuizoAnterior: PrejuizoAcumulado(comum: 120.5),
      );
      final linhas = montarLinhas([marcado], Config());
      final d = reconstruir(linhas).meses['2026-11']!;
      expect(d.metodo, metodoCustoMedio);
      expect(d.toJson(), {
        'mes': '2026-11',
        'fechado': false,
        'darf_anterior': 0.0,
        'lotes': <Object?>[],
        'excluidos': <String, Object?>{},
        'mod': 5.0,
        'metodo': 'custo_medio',
        'posicao_inicial': {
          'PETR4': {'qtd': 100, 'custo': 2550.0},
        },
        'prejuizo_anterior': {'comum': 120.5, 'day_trade': 0.0},
      });
    });

    test('planilha de 13 colunas aceita (sem marcador)', () {
      final d = reconstruir({
        'Resumo': [resumo('11/2026')],
      }).meses['2026-11']!;
      expect(d.metodo, isNull);
      expect(d.toJson().containsKey('metodo'), isFalse);
      expect(d.posicaoInicial, isNull);
      expect(d.prejuizoAnterior, isNull);
    });

    test('valor desalinhado ignorado (mês trocado)', () {
      final dados = reconstruir({
        'Resumo': [
          resumo('10/2026', detalhes), // valor do mês 11 na linha do 10
          resumo('11/2026', ''),
        ],
      });
      expect(dados.meses['2026-10']!.metodo, isNull);
      expect(dados.meses['2026-10']!.posicaoInicial, isNull);
      expect(dados.meses['2026-11']!.metodo, isNull);
    });

    test('valor inválido ignorado', () {
      for (final v in [
        'não é JSON',
        '[1, 2]',
        '{"mes":"2026-11"}',
        '{"mes":"2026-11","metodo":"outro"}',
        '{"mes":"2026-11","metodo":"custo_medio",'
            '"posicao_inicial":{"PETR4":{"qtd":1.5,"custo":1.0}}}',
        12,
      ]) {
        final d = reconstruir({
          'Resumo': [resumo('11/2026', v)],
        }).meses['2026-11']!;
        expect(d.metodo, isNull, reason: '$v');
        expect(d.posicaoInicial, isNull, reason: '$v');
      }
    });
  });
}
