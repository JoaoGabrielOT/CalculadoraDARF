// Porte dos testes de mesclagem e de OCO de tests/test_metas.py.

import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/mesclagem.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';

Meta _meta(Map<String, Object?> json) => Meta.fromJson(json);

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  // TestMesclagem.meta
  Meta metaPadrao({
    String status = 'ativa',
    num mod = 10,
    Map<String, Object?>? execucao,
  }) => _meta({
    'id': 'meta-1',
    'ticker': 'PETR4',
    'tipo': 'Ação',
    'lote_id': 'L1',
    'qtd': 100,
    'preco_alvo': 21.78,
    'criada_em': '2026-10-20T11:00:00-03:00',
    'status': status,
    'mod': mod,
    'execucao': ?execucao,
  });

  test('TestMesclagem.test_executada_vence_ativa_mesmo_mais_antiga', () {
    final ex = metaPadrao(
      status: 'executada',
      mod: 5,
      execucao: {'venda_id': 'auto-meta-1'},
    );
    var r = mesclarMetas([metaPadrao(mod: 99)], [ex]);
    expect(r.length, 1);
    expect(r[0].status, 'executada');
    r = mesclarMetas([ex], [metaPadrao(mod: 99)]);
    expect(r[0].status, 'executada');
  });

  test('TestMesclagem.test_mais_recente_vence_nos_demais', () {
    final r = mesclarMetas(
      [metaPadrao(mod: 1)],
      [metaPadrao(status: 'cancelada', mod: 2)],
    );
    expect(r[0].status, 'cancelada');
  });

  test(
    'TestCompatibilidadeStop.test_mesclagem_do_stop_movel_fica_com_o_maior',
    () {
      final baseStopMovel = {
        'id': 'meta-s',
        'ticker': 'PETR4',
        'tipo': 'Ação',
        'lote_id': 'L1',
        'qtd': 100,
        'gatilho': 'stop',
        'stop_inicial': 5.0,
        'movel': true,
        'criada_em': '2026-10-20T11:00:00-03:00',
        'status': 'ativa',
      };
      final n0 = {'desde': '2026-10-20', 'stop': 5.0, 'calc_em': '2026-10-20'};
      final local = _meta({
        ...baseStopMovel,
        'mod': 1,
        'stop_atual': 7.0,
        'niveis': [
          n0,
          {'desde': '2026-10-22', 'stop': 7.0, 'calc_em': '2026-10-21'},
        ],
      });
      final remoto = _meta({
        ...baseStopMovel,
        'mod': 2,
        'stop_atual': 6.0,
        'niveis': [
          n0,
          {'desde': '2026-10-21', 'stop': 6.0, 'calc_em': '2026-10-20'},
          {'desde': '2026-10-22', 'stop': 6.5, 'calc_em': '2026-10-21'},
        ],
      });
      var r = mesclarMetas([local], [remoto])[0];
      expect(r.stopAtual, 7.0);
      expect(
        [for (final n in r.niveis!) (n.desde, n.stop)],
        [('2026-10-20', 5.0), ('2026-10-21', 6.0), ('2026-10-22', 7.0)],
      );
      r = mesclarMetas([remoto], [local])[0];
      expect(r.stopAtual, 7.0);
    },
  );

  test('TestCompatibilidadeStop.test_mesclagem_nao_une_stop_executado', () {
    final b = {
      'id': 'meta-s',
      'ticker': 'PETR4',
      'tipo': 'Ação',
      'lote_id': 'L1',
      'qtd': 100,
      'gatilho': 'stop',
      'stop_inicial': 5.0,
      'movel': true,
      'criada_em': '2026-10-20T11:00:00-03:00',
      'mod': 1,
      'niveis': <Object?>[],
      'stop_atual': 5.0,
    };
    final r = mesclarMetas(
      [
        _meta({...b, 'status': 'executada', 'stop_atual': 5.0}),
      ],
      [
        _meta({...b, 'status': 'ativa', 'stop_atual': 8.0}),
      ],
    )[0];
    expect((r.status, r.stopAtual), ('executada', 5.0));
  });

  test(
    'TestRevisaoMesclagem.test_aparelho_antigo_nao_apaga_o_oco_na_mesclagem',
    () {
      final novo = {
        ...baseAlvo,
        'status': 'ativa',
        'mod': 1,
        'oco': 'oco-1',
        'cancelada_por': 'x',
      };
      final antigo = {
        ...baseAlvo,
        'status': 'executada',
        'mod': 2,
        'execucao': {
          'data': '2026-10-22',
          'hora': '10:00',
          'venda_id': 'auto-meta-a',
        },
      };
      for (final (local, remoto) in [(antigo, novo), (novo, antigo)]) {
        final r = mesclarMetas([_meta(local)], [_meta(remoto)])[0];
        expect(r.status, 'executada');
        expect(r.oco, 'oco-1');
        // só vale numa meta cancelada
        expect(r.toJson().containsKey('cancelada_por'), isFalse);
      }
    },
  );

  test(
    'TestRevisaoMesclagem.test_campos_novos_do_perdedor_em_meta_cancelada',
    () {
      final novo = {
        ...baseStop,
        'status': 'cancelada',
        'mod': 1,
        'oco': 'oco-1',
        'cancelada_por': 'meta-a',
        'cancelada_detalhe':
            'Cancelada automaticamente (OCO): alvo executado em 22/10',
      };
      final antigo = {
        ...baseAlvo,
        'id': 'meta-s',
        'status': 'cancelada',
        'mod': 2,
      };
      final r = mesclarMetas([_meta(antigo)], [_meta(novo)])[0];
      expect((r.oco, r.canceladaPor), ('oco-1', 'meta-a'));
      expect(r.toJson().containsKey('cancelada_detalhe'), isTrue);
    },
  );

  test(
    'TestRevisaoMesclagem.test_stop_nao_vira_alvo_nem_alvo_vira_stop_na_uniao',
    () {
      final stop = {...baseStop, 'id': 'meta-x', 'status': 'ativa', 'mod': 1};
      final alvo = {...baseAlvo, 'id': 'meta-x', 'status': 'ativa', 'mod': 2};
      final r = mesclarMetas([_meta(alvo)], [_meta(stop)])[0];
      expect(r.toJson().containsKey('gatilho'), isFalse);
      expect(r.toJson().containsKey('stop_atual'), isFalse);
    },
  );

  test('TestRevisaoMesclagem.test_stop_de_12_colunas_vencedor_recupera_os_campos_do_outro', () {
    // registro vencedor de um stop sem os campos novos (reescrito por aparelho
    // antigo): recupera tudo do outro
    final novo = {
      ...baseStop,
      'status': 'ativa',
      'mod': 1,
      'oco': 'oco-1',
      'stop_atual': 7.0,
      'niveis': [
        {'desde': '2026-10-20', 'stop': 7.0, 'calc_em': '2026-10-20'},
      ],
    };
    final pobre = {
      for (final e in baseAlvo.entries)
        if (e.key != 'preco_alvo') e.key: e.value,
      'id': 'meta-s',
      'status': 'executada',
      'mod': 2,
    };
    final r = mesclarMetas([_meta(pobre)], [_meta(novo)])[0];
    expect((r.gatilho, r.oco, r.stopAtual), ('stop', 'oco-1', 7.0));
  });

  test('TestRevisaoMesclagem.test_cancelada_vence_ativa_mesmo_mais_antiga', () {
    final n0 = {'desde': '2026-10-20', 'stop': 5.0, 'calc_em': '2026-10-20'};
    final n1 = {'desde': '2026-10-22', 'stop': 7.0, 'calc_em': '2026-10-21'};
    final cancelada = {
      ...baseStop,
      'status': 'cancelada',
      'mod': 1,
      'niveis': [n0],
    };
    final ativa = {
      ...baseStop,
      'status': 'ativa',
      'mod': 9,
      'niveis': [n0, n1],
      'stop_atual': 7.0,
    };
    for (final (local, remoto) in [(cancelada, ativa), (ativa, cancelada)]) {
      final r = mesclarMetas([_meta(local)], [_meta(remoto)])[0];
      expect(r.status, 'cancelada');
      // os níveis continuam unidos
      expect(r.stopAtual, 7.0);
      expect(r.niveis!.length, 2);
    }
  });

  test('TestOCO.test_resolver_oco_com_as_duas_executadas', () {
    final a = _meta({
      'id': 'meta-a',
      'ticker': 'PETR4',
      'tipo': 'Ação',
      'lote_id': 'L1',
      'qtd': 50,
      'preco_alvo': 20.0,
      'criada_em': '2026-10-20T11:00:00-03:00',
      'status': 'executada',
      'oco': 'oco-1',
      'execucao': {
        'data': '2026-10-22',
        'hora': '10:00',
        'venda_id': 'auto-meta-a',
      },
    });
    final s = _meta({
      'id': 'meta-s',
      'ticker': 'PETR4',
      'tipo': 'Ação',
      'lote_id': 'L1',
      'qtd': 50,
      'gatilho': 'stop',
      'stop_inicial': 9.0,
      'stop_atual': 9.0,
      'movel': false,
      'niveis': <Object?>[],
      'oco': 'oco-1',
      'criada_em': '2026-10-20T11:00:00-03:00',
      'status': 'executada',
      'execucao': {
        'data': '2026-10-21',
        'hora': '10:00',
        'venda_id': 'auto-meta-s',
      },
    });
    final d = base.repo.carregar('2026-10');
    d.lotes[0].vendas.addAll([
      Venda(id: 'auto-meta-a', data: '2026-10-22', qtd: 50, preco: 20.0),
      Venda(id: 'auto-meta-s', data: '2026-10-21', qtd: 50, preco: 9.0),
    ]);
    final alterados = resolverOco({'2026-10': d}, [a, s]);
    expect(alterados, {'2026-10'});
    // o stop foi o mais cedo
    expect((a.status, s.status), ('cancelada', 'executada'));
    expect([for (final v in d.lotes[0].vendas) v.id], ['auto-meta-s']);
    expect(d.excluidos.containsKey('auto-meta-a'), isTrue);
    expect(a.canceladaPor, 'meta-s');
  });

  // TestRevisaoOco.exec_
  Meta exec(
    Map<String, Object?> b, {
    required String data,
    required String hora,
    required String vendaId,
    num? barraTs,
    num mod = 0,
  }) => _meta({
    ...b,
    'status': 'executada',
    'oco': 'oco-1',
    'mod': mod,
    'execucao': {
      'data': data,
      'hora': hora,
      'venda_id': vendaId,
      'barra_ts': ?barraTs,
    },
  });

  test('TestRevisaoOco.test_empate_de_data_com_hora_vazia_prefere_o_stop', () {
    var alvo = exec(
      baseAlvo,
      data: '2026-10-22',
      hora: '',
      vendaId: 'auto-meta-a',
    );
    var stop = exec(
      baseStop,
      data: '2026-10-22',
      hora: '10:00',
      vendaId: 'auto-meta-s',
    );
    resolverOco({}, [alvo, stop]);
    expect((alvo.status, stop.status), ('cancelada', 'executada'));
    alvo = exec(
      baseAlvo,
      data: '2026-10-22',
      hora: '10:00',
      vendaId: 'auto-meta-a',
    );
    stop = exec(baseStop, data: '2026-10-22', hora: '', vendaId: 'auto-meta-s');
    resolverOco({}, [alvo, stop]);
    expect((alvo.status, stop.status), ('cancelada', 'executada'));
  });

  test('TestRevisaoOco.test_barra_ts_desempata_quando_disponivel', () {
    final alvo = exec(
      baseAlvo,
      data: '2026-10-22',
      hora: '10:00',
      barraTs: 100,
      vendaId: 'auto-meta-a',
    );
    final stop = exec(
      baseStop,
      data: '2026-10-22',
      hora: '10:00',
      barraTs: 200,
      vendaId: 'auto-meta-s',
    );
    resolverOco({}, [alvo, stop]);
    expect((alvo.status, stop.status), ('executada', 'cancelada'));
  });

  test('TestRevisaoOco.test_data_mais_cedo_continua_vencendo', () {
    final alvo = exec(
      baseAlvo,
      data: '2026-10-21',
      hora: '',
      vendaId: 'auto-meta-a',
    );
    final stop = exec(
      baseStop,
      data: '2026-10-22',
      hora: '10:00',
      vendaId: 'auto-meta-s',
    );
    resolverOco({}, [alvo, stop]);
    expect((alvo.status, stop.status), ('executada', 'cancelada'));
  });

  test('TestRevisaoOco.test_meta_cancelada_pelo_oco_recebe_mod_novo', () {
    final alvo = exec(
      baseAlvo,
      data: '2026-10-22',
      hora: '10:00',
      vendaId: 'auto-meta-a',
      mod: 1.0,
    );
    final stop = exec(
      baseStop,
      data: '2026-10-21',
      hora: '10:00',
      vendaId: 'auto-meta-s',
      mod: 1.0,
    );
    resolverOco({}, [alvo, stop]);
    expect(alvo.mod, greaterThan(1.0));
    expect(stop.mod, 1.0);
  });
}
