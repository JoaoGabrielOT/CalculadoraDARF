import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('planilha_montagem'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('planilha_montagem')) {
    test('${caso.funcao}: ${caso.nome}', () {
      switch (caso.funcao) {
        case 'montar_linhas':
          final entrada = _mapa(caso.entrada);
          final meses = [
            for (final m in entrada['meses']! as List<Object?>)
              Mes.fromJson(_mapa(m)),
          ];
          final cfg = Config.fromJson(_mapa(entrada['cfg']));
          conferir(
            montarLinhas(meses, cfg),
            caso.saida,
            // a ordem vem de um set no Python (nucleo.py:165-166)
            semOrdem: {r'$.Exclusões'},
          );
        case 'celula':
          conferir([
            for (final v in caso.entrada! as List<Object?>) celula(v),
          ], caso.saida);
        case 'normalizar_leitura':
          final lidas = {
            for (final e in _mapa(caso.entrada).entries)
              e.key: [
                for (final l in e.value! as List<Object?>)
                  List<Object?>.of(l! as List<Object?>),
              ],
          };
          conferir(normalizarLeitura(lidas), caso.saida);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }

  test('linhaMeta: stop sem preço-alvo, Execução em JSON com separadores', () {
    final stop = Meta.fromJson({
      'id': 'm1',
      'ticker': 'PETR4',
      'lote_id': 'L1',
      'qtd': 10,
      'gatilho': 'stop',
      'stop_inicial': 5.0,
      'criada_em': '2026-10-20T11:00:00-03:00',
    });
    final linha = linhaMeta(stop);
    expect(linha, hasLength(14));
    expect(linha[5], '');
    expect(linha[10], '');
    expect(linha[12], 'stop');
    expect(linha[13], '{"id":"m1","gatilho":"stop","stop_inicial":5.0}');
  });
}
