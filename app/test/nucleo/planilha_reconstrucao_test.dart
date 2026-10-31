import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
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
}
