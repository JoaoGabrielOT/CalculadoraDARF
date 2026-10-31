import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/mesclagem.dart';
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
}
