import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao_medio.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/mesclagem.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/planilha/reconstrucao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

Mes? _mes(Object? o) => o == null ? null : Mes.fromJson(_mapa(o));

Map<String, Mes> _meses(Object? o) => {
  for (final e in _mapa(o).entries) e.key: Mes.fromJson(_mapa(e.value)),
};

List<Meta> _metas(Object? o) => [
  for (final m in _lista(o)) Meta.fromJson(_mapa(m)),
];

List<Nivel>? _niveis(Object? o) =>
    o == null ? null : [for (final n in _lista(o)) Nivel.fromJson(_mapa(n))];

Map<String, Object?> _mesesJson(Map<String, Mes> m) => {
  for (final e in m.entries) e.key: e.value.toJson(),
};

List<Object?> _metasJson(List<Meta> m) => [for (final x in m) x.toJson()];

Map<String, double> _excl(Object? o) => {
  for (final e in _mapa(o).entries) e.key: (e.value! as num).toDouble(),
};

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('mesclagem'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('mesclagem')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = _mapa(caso.entrada);
      final Object? atual;
      switch (caso.funcao) {
        case 'mesclar_mes':
          final local = _mes(e['local']);
          final remoto = _mes(e['remoto']);
          final r = mesclarMes(local, remoto);
          // um lado nulo devolve a mesma instância do outro
          if (local == null) expect(r, same(remoto));
          if (remoto == null) expect(r, same(local));
          atual = {'mes': r?.toJson()};
        case 'deduplicar_auto':
          final meses = _meses(e['meses']);
          final alterados = deduplicarAuto(meses);
          atual = {
            'alterados': alterados.toList()..sort(),
            'meses': _mesesJson(meses),
          };
        case 'mesclar_lista':
          final excl = _excl(e['excl']);
          final prefixo = e['prefixo']! as String;
          if (e['lista'] == 'amigos') {
            final r = mesclarLista<Amigo>(
              [for (final a in _lista(e['local'])) Amigo.fromJson(_mapa(a))],
              [for (final a in _lista(e['remoto'])) Amigo.fromJson(_mapa(a))],
              (a) => a.email,
              excl,
              prefixo,
            );
            atual = {
              'itens': [for (final a in r) a.toJson()],
            };
          } else {
            final r = mesclarLista<ItemRadar>(
              [
                for (final a in _lista(e['local']))
                  ItemRadar.fromJson(_mapa(a)),
              ],
              [
                for (final a in _lista(e['remoto']))
                  ItemRadar.fromJson(_mapa(a)),
              ],
              (a) => a.ticker,
              excl,
              prefixo,
            );
            atual = {
              'itens': [for (final a in r) a.toJson()],
            };
          }
        case 'mesclar_metas':
          atual = {
            'metas': _metasJson(
              mesclarMetas(_metas(e['local']), _metas(e['remoto'])),
            ),
          };
        case 'unir_niveis':
          atual = {
            'niveis': [
              for (final n in unirNiveis(_niveis(e['a']), _niveis(e['b'])))
                n.toJson(),
            ],
          };
        case 'execucao_antes':
          atual = {
            'ordem': execucaoAntes(
              Meta.fromJson(_mapa(e['a'])),
              Meta.fromJson(_mapa(e['b'])),
            ),
          };
        case 'resolver_oco':
          final meses = _meses(e['meses']);
          final metas = _metas(e['metas']);
          final avisos = <String>[];
          final alterados = resolverOco(meses, metas, avisos: avisos);
          atual = {
            'alterados': alterados.toList()..sort(),
            'meses': _mesesJson(meses),
            'metas': _metasJson(metas),
            'avisos': avisos,
          };
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
      conferir(atual, caso.saida);
    });
  }

  group('marcador de método', () {
    Mes marcado(String mes, {double mod = 10, bool fechado = false}) => Mes(
      mes: mes,
      mod: mod,
      fechado: fechado,
      metodo: metodoCustoMedio,
      posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 2550.0)},
      prejuizoAnterior: PrejuizoAcumulado(comum: 120.5),
    );
    Mes semMarcador(String mes, {double mod = 20, bool fechado = false}) =>
        Mes(mes: mes, mod: mod, fechado: fechado);
    Map<String, Object?> campos(Mes m) {
      final j = m.toJson();
      return {
        for (final k in ['metodo', 'posicao_inicial', 'prejuizo_anterior'])
          if (j.containsKey(k)) k: j[k],
      };
    }

    final esperado = {
      'metodo': 'custo_medio',
      'posicao_inicial': {
        'PETR4': {'qtd': 100, 'custo': 2550.0},
      },
      'prejuizo_anterior': {'comum': 120.5, 'day_trade': 0.0},
    };

    test('marcador é monotônico na mesclagem', () {
      // local com marcador x remoto sem e com mod maior (planilha regravada
      // por uma 1.12): marcador mantido, nos dois sentidos
      final r1 = mesclarMes(marcado('2026-11'), semMarcador('2026-11'))!;
      expect(campos(r1), esperado);
      expect(r1.mod, 20.0);
      final r2 = mesclarMes(semMarcador('2026-11'), marcado('2026-11'))!;
      expect(campos(r2), esperado);
      // mesmo mod (a 1.12 só regravou a planilha)
      final r3 = mesclarMes(
        marcado('2026-11'),
        semMarcador('2026-11', mod: 10),
      )!;
      expect(campos(r3), esperado);
      // mês fechado sem marcador no vencedor (fechado pelo método antigo):
      // sem marcador
      final r4 = mesclarMes(
        marcado('2026-11'),
        semMarcador('2026-11', fechado: true),
      )!;
      expect(campos(r4), isEmpty);
      expect(r4.fechado, isTrue);
      // fechado sem marcador no perdedor não tira o marcador do vencedor
      final r5 = mesclarMes(
        semMarcador('2026-11', mod: 5, fechado: true),
        marcado('2026-11'),
      )!;
      expect(campos(r5), esperado);
    });

    test('mês fechado pelo custo médio continua marcado quando a 1.12 perde '
        'o marcador', () {
      // remoto (planilha regravada) sem marcador e com mod maior, também
      // fechado: o mês foi fechado pelo custo médio e não muda de método
      final local = marcado('2026-11', fechado: true);
      final r = mesclarMes(local, semMarcador('2026-11', fechado: true))!;
      expect(campos(r), esperado);
      expect(r.fechado, isTrue);
      // ida pela planilha: a linha regravada pela 1.12 não tem a coluna 14
      final linha = montarLinhas([r], Config())['Resumo']!.single;
      final lido = reconstruir({
        'Resumo': [linha.sublist(0, 13)],
      }).meses['2026-11']!;
      expect(lido.metodo, isNull);
      final denovo = mesclarMes(r, lido)!;
      expect(campos(denovo), esperado);
      expect(usaCustoMedio(denovo, mesDeCorte([denovo])), isTrue);
    });

    test('dois marcadores: vence o do mod maior', () {
      final outro = marcado('2026-11', mod: 30)
        ..prejuizoAnterior = PrejuizoAcumulado(dayTrade: 7.5);
      final r = mesclarMes(marcado('2026-11'), outro)!;
      expect(campos(r)['prejuizo_anterior'], {'comum': 0.0, 'day_trade': 7.5});
    });

    test('sem marcador nos dois lados: nenhum campo novo', () {
      final r = mesclarMes(semMarcador('2026-11'), semMarcador('2026-11'))!;
      expect(campos(r), isEmpty);
    });

    test('conflito de corte entre aparelhos', () {
      // aparelho A migrou em 10/2026 (10 e 11 marcados); B, offline, em
      // 11/2026 (10 sem marcador e alterado depois)
      final m10 = mesclarMes(marcado('2026-10'), semMarcador('2026-10'))!;
      final m11 = mesclarMes(marcado('2026-11'), marcado('2026-11', mod: 30))!;
      final corte = mesDeCorte([m10, m11]);
      expect(corte, '2026-10');
      expect(usaCustoMedio(m10, corte), isTrue);
      expect(usaCustoMedio(m11, corte), isTrue);
      // B já fechou 10/2026 pelo método antigo: fica por compra para sempre
      // e o corte efetivo passa a 11/2026
      final f10 = mesclarMes(
        marcado('2026-10'),
        semMarcador('2026-10', fechado: true),
      )!;
      final corte2 = mesDeCorte([f10, m11]);
      expect(corte2, '2026-11');
      expect(usaCustoMedio(f10, corte2), isFalse);
      expect(usaCustoMedio(m11, corte2), isTrue);
    });

    test('Mes.fromJson aceita só custo_medio e não apaga valor inesperado', () {
      final marcadoJson = Mes.fromJson({
        'mes': '2026-11',
        'metodo': 'custo_medio',
      });
      expect(marcadoJson.metodo, metodoCustoMedio);
      for (final v in [7, 'outro', true, <Object?>[]]) {
        final m = Mes.fromJson({'mes': '2026-11', 'metodo': v});
        expect(m.metodo, isNull, reason: '$v');
        // a próxima gravação devolve o valor como estava
        expect(m.toJson()['metodo'], v, reason: '$v');
        // e a mesclagem com um lado marcado não perde o marcador
        final r = mesclarMes(m..mod = 50, marcado('2026-11'))!;
        expect(r.metodo, metodoCustoMedio, reason: '$v');
      }
      expect(
        Mes.fromJson({'mes': '2026-11', 'metodo': null}).toJson(),
        isNot(contains('metodo')),
      );
    });
  });
}
