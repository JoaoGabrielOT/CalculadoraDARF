import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/abas.dart';
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
          // meses sem marcador: as 13 primeiras células são as do Python e a
          // 14ª fica vazia
          final linhas = semDetalhesDoResumo(montarLinhas(meses, cfg));
          conferir(
            linhas,
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
          final normal = normalizarLeitura(lidas);
          // o Python corta o Resumo em 13 colunas; a 2.1 lê também a 14ª
          final brutas = lidas['Resumo'] ?? const <List<Object?>>[];
          normal['Resumo'] = [
            for (final (i, l) in normal['Resumo']!.indexed)
              () {
                expect(l, hasLength(14));
                expect(l[13], brutas[i].length > 13 ? brutas[i][13] : '');
                return l.sublist(0, 13);
              }(),
          ];
          conferir(normal, caso.saida);
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

  group('coluna Detalhes do Resumo', () {
    test('coluna 14 gravada com o marcador e o próprio mês', () {
      final marcado = Mes(
        mes: '2026-11',
        mod: 7,
        metodo: metodoCustoMedio,
        posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 2550.0)},
        prejuizoAnterior: PrejuizoAcumulado(comum: 120.5),
      );
      final resumo = montarLinhas([marcado], Config())['Resumo']!;
      expect(resumo.single, hasLength(14));
      expect(resumo.single[0], '11/2026');
      expect(resumo.single[12], 7.0);
      expect(
        resumo.single[13],
        '{"mes":"2026-11","metodo":"custo_medio",'
        '"posicao_inicial":{"PETR4":{"qtd":100,"custo":2550.0}},'
        '"prejuizo_anterior":{"comum":120.5,"day_trade":0.0}}',
      );
    });

    test('meses sem marcador têm as 13 primeiras células idênticas às de '
        'hoje e a 14ª vazia', () {
      final semMarcador = Mes(mes: '2026-10', fechado: true, mod: 3);
      final resumo = montarLinhas([semMarcador], Config())['Resumo']!;
      expect(resumo.single, [
        '10/2026', 'Fechado', 0.0, 'Sim', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, //
        0.0, 0.0, 3.0, '',
      ]);
    });

    test('esquema: Detalhes é a 14ª coluna do Resumo, oculta (tipo id)', () {
      final c = esquemaDe('Resumo').colunas;
      expect(c, hasLength(14));
      expect([c[13].titulo, c[13].tipo, c[13].largura], ['Detalhes', 'id', 80]);
    });
  });
}
