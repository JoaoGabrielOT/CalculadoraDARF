import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/metas/deteccao.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

List<Map<String, Object?>> _lista(Object? o) => [
  for (final e in o! as List<Object?>) _mapa(e),
];

double? _numOuNulo(Object? v) => (v as num?)?.toDouble();

List<Barra> _barras(Object? o) => [
  for (final b in _lista(o))
    Barra(
      ts: 0,
      dt: DataHora.parse(b['dt']! as String),
      alta: (b['alta']! as num).toDouble(),
      baixa: _numOuNulo(b['baixa']),
      abre: _numOuNulo(b['abre']),
    ),
];

List<Nivel> _niveis(Object? o) => [
  for (final n in _lista(o)) Nivel.fromJson(n),
];

List<BarraDiaria> _diarias(Object? o) => [
  for (final b in _lista(o))
    BarraDiaria(
      data: b['data']! as String,
      abre: _numOuNulo(b['abre']),
      alta: (b['alta']! as num).toDouble(),
      baixa: (b['baixa']! as num).toDouble(),
      fech: (b['fech']! as num).toDouble(),
    ),
];

int? _indice(List<Barra> barras, Barra? achada) {
  if (achada == null) return null;
  return barras.indexWhere((b) => identical(b, achada));
}

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('metas_deteccao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('metas_deteccao')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = caso.entrada == null ? null : _mapa(caso.entrada);
      final s = _mapa(caso.saida);
      switch (caso.funcao) {
        case 'achar_barra':
          final barras = _barras(e!['barras']);
          final r = acharBarra(
            barras,
            (e['alvo']! as num).toDouble(),
            DataHora.parse(e['criada']! as String),
          );
          conferir({'indice': _indice(barras, r)}, s);
        case 'nivel_vigente':
          conferir({
            'nivel': nivelVigente(_niveis(e!['niveis']), e['data']! as String),
          }, s);
        case 'achar_barra_stop':
          final barras = _barras(e!['barras']);
          final r = acharBarraStop(
            barras,
            _niveis(e['niveis']),
            DataHora.parse(e['criada']! as String),
          );
          conferir({
            'indice': _indice(barras, r?.$1),
            if (r != null) 'nivel': r.$2,
          }, s);
        case 'preco_execucao_stop':
          final barra = Barra(
            ts: 0,
            dt: DataHora.parse('2026-10-21T10:00:00-03:00'),
            alta: 0,
            abre: _numOuNulo(e!['abre']),
          );
          final (preco, gap) = precoExecucaoStop(
            barra,
            (e['nivel']! as num).toDouble(),
          );
          conferir({'preco': preco, 'gap': gap}, s);
        case 'atualizar_stop_movel':
          final meta = Meta.fromJson(_mapa(e!['meta']));
          final mudou = atualizarStopMovel(
            meta,
            _diarias(e['barras']),
            e['hoje']! as String,
          );
          final esperada = _mapa(s['meta']);
          conferir(
            {
              'mudou': mudou,
              'meta': {
                'stop_atual': meta.stopAtual,
                'niveis': meta.niveis == null
                    ? null
                    : [for (final n in meta.niveis!) n.toJson()],
              },
            },
            {
              'mudou': s['mudou'],
              'meta': {
                'stop_atual': esperada['stop_atual'],
                'niveis': esperada['niveis'],
              },
            },
          );
        case 'barras_aleatorias':
          // Só exporta as barras para os testes portados; confere que o JSON
          // tem o tamanho pedido.
          expect(_lista(s['barras']).length, (e!['n']! as num).toInt());
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }
}
