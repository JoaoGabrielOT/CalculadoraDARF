// Porte dos testes de `mesclar_tudo` de tests/test_metas.py (TestMesclagem,
// TestMesclagemEntreMeses, TestOCO e TestRevisaoOco).

import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/planilha/reconstrucao.dart';
import 'package:calculadoradarf/nucleo/planilha/sincronizacao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';

/// `({}, [], [], {})`: a planilha sem nada.
DadosPlanilha _vazio() =>
    DadosPlanilha(meses: {}, amigos: [], radar: [], excluidos: {}, caixa: null);

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  // nc.montar_linhas(nc.listar_meses(), cfg)
  Map<String, List<Linha>> linhasDe(Config cfg) =>
      montarLinhas(base.repo.carregarMeses().values.toList(), cfg);

  // TestOCO.par e TestRevisaoOco.par
  (Meta, Meta) par({int qtd = 100}) {
    final a = criarMeta(
      base.repo,
      base.cfg,
      'L1',
      qtd,
      21.78,
      agora: base.criada,
    );
    final s = criarStop(
      base.repo,
      base.cfg,
      'L1',
      qtd,
      9.0,
      ocoCom: a.id,
      agora: base.criada,
    );
    return (a, s);
  }

  test('TestMesclagem.test_mesclar_tudo_nao_duplica_venda_nem_meta', () async {
    final m = base.criar();
    await base.verificar([barra('2026-10-21T10:00:00', 30)]);
    final local = base.repo.lerConfig();
    final linhas = linhasDe(local);
    expect(linhas['Metas']!.length, 1);
    final remotoMetas = reconstruirMetas(linhas);
    expect(remotoMetas[0].execucao!['venda_id'], 'auto-${m.id}');
    final mudou = mesclarTudo(
      base.repo,
      reconstruir(linhas),
      local,
      metasR: remotoMetas,
    );
    expect(mudou, isFalse);
    expect(base.lote().vendas.length, 1);
    expect(local.metas.length, 1);
  });

  test('TestMesclagem.test_aparelho_com_meta_ativa_recebe_executada', () async {
    final m = base.criar();
    await base.verificar([barra('2026-10-21T10:00:00', 30)]);
    final linhas = linhasDe(base.repo.lerConfig());
    final remoto = reconstruir(linhas);
    final remotoMetas = reconstruirMetas(linhas);
    // estado do segundo aparelho: meta ainda ativa (alterada depois) e sem a venda
    final d = base.repo.carregar('2026-10');
    d.lotes[0].vendas = [];
    d.excluidos = {};
    // aparelho que nunca viu a venda (não é uma exclusão)
    base.repo.salvar(d, carimbar: false);
    final ativa = Meta.fromJson({
      for (final e in m.toJson().entries)
        if (e.key != 'execucao') e.key: e.value,
      'status': 'ativa',
      'mod': 9e9,
    });
    final outro = base.repo.lerConfig()..metas = [ativa];
    expect(mesclarTudo(base.repo, remoto, outro, metasR: remotoMetas), isTrue);
    expect(outro.metas[0].status, 'executada');
    expect(base.lote().vendas.length, 1);
  });

  test('TestMesclagemEntreMeses.test_venda_auto_em_meses_diferentes_fica_so_no_mais_antigo', () {
    final v = {
      'id': 'auto-meta-x',
      'data': '2026-10-31',
      'qtd': 50,
      'preco': 20.0,
    };
    final d10 = base.repo.carregar('2026-10');
    d10.lotes[0].vendas.add(Venda.fromJson({...v}));
    base.repo.salvar(d10);
    final d11 = mesVazio('2026-11');
    d11.lotes.add(
      Lote.fromJson({
        'id': 'L1~2026-11',
        'origem': 'L1',
        'ticker': 'PETR4',
        'tipo': 'Ação',
        'data_compra': '2026-10-01',
        'qtd': 100,
        'preco': 10.0,
        'vendas': [
          {...v, 'data': '2026-11-01'},
        ],
      }),
    );
    base.repo.salvar(d11);
    expect(mesclarTudo(base.repo, _vazio(), base.cfg), isTrue);
    expect([for (final x in base.lote().vendas) x.id], ['auto-meta-x']);
    expect(base.lote(mes: '2026-11', lid: 'L1~2026-11').vendas, isEmpty);
  });

  test('TestOCO.test_mesclar_tudo_resolve_oco_duplo', () {
    final (a, s) = par();
    // aparelho 1 executou o alvo, aparelho 2 executou o stop
    final d = base.repo.carregar('2026-10');
    d.lotes[0].vendas.add(
      Venda(id: 'auto-${a.id}', data: '2026-10-22', qtd: 100, preco: 21.78),
    );
    base.repo.salvar(d);
    final remotoMetas = [
      for (final m in base.cfg.metas)
        if (m.id == s.id)
          Meta.fromJson({
            ...m.toJson(),
            'status': 'executada',
            'mod': 5e9,
            'execucao': {
              'data': '2026-10-21',
              'hora': '10:00',
              'venda_id': 'auto-${m.id}',
              'preco_usado': 9.0,
            },
          }),
    ];
    final local = base.repo.lerConfig();
    for (final m in local.metas) {
      if (m.id == a.id) {
        m.status = 'executada';
        m.execucao = {
          'data': '2026-10-22',
          'hora': '10:00',
          'venda_id': 'auto-${a.id}',
          'preco_usado': 21.78,
        };
      }
    }
    final remotoMes = mesVazio('2026-10');
    remotoMes.lotes.add(
      Lote.fromJson({
        ...base.lote().toJson(),
        'vendas': [
          {
            'id': 'auto-${s.id}',
            'data': '2026-10-21',
            'qtd': 100,
            'preco': 9.0,
            'mod': 9e9,
          },
        ],
      }),
    );
    final remoto = DadosPlanilha(
      meses: {'2026-10': remotoMes},
      amigos: [],
      radar: [],
      excluidos: {},
      caixa: null,
    );
    expect(mesclarTudo(base.repo, remoto, local, metasR: remotoMetas), isTrue);
    expect([for (final v in base.lote().vendas) v.id], ['auto-${s.id}']);
    final porId = {for (final m in local.metas) m.id: m};
    expect(
      (porId[a.id]!.status, porId[s.id]!.status),
      ('cancelada', 'executada'),
    );
  });

  group('TestRevisaoOco', () {
    // TestRevisaoOco.setUp: o lote passa a ter 200 ações
    setUp(() {
      final d = base.repo.carregar('2026-10');
      d.lotes[0].qtd = 200;
      base.repo.salvar(d);
    });

    // TestRevisaoOco.registrar_venda
    void registrarVenda(Meta meta, String data, double preco) {
      final d = base.repo.carregar('2026-10');
      d.lotes[0].vendas.add(
        Venda(id: 'auto-${meta.id}', data: data, qtd: meta.qtd, preco: preco),
      );
      base.repo.salvar(d);
      meta.status = 'executada';
      meta.execucao = {
        'venda_id': 'auto-${meta.id}',
        'data': data,
        'hora': '10:00',
        'preco_usado': preco,
        'origem': 'teste',
        'barra_ts': 0,
        'motivo': 'teste',
      };
      base.repo.gravarConfig(base.cfg);
    }

    test('TestRevisaoOco.test_mesclar_tudo_devolve_aviso_de_mes_fechado', () {
      final (a, s) = par();
      registrarVenda(a, '2026-10-22', 21.78);
      registrarVenda(s, '2026-10-21', 9.0);
      final d = base.repo.carregar('2026-10');
      d.fechado = true;
      base.repo.salvar(d);
      final avisos = <String>[];
      mesclarTudo(base.repo, _vazio(), base.cfg, metasR: [], avisos: avisos);
      expect(avisos.length, 1);
      expect(
        [for (final v in base.lote().vendas) v.id],
        ['auto-${a.id}', 'auto-${s.id}'],
      );
    });
  });
}
