// Porte dos testes de verificação e execução automática de metas de
// tests/test_metas.py (TestCriacao.test_cancelar, TestExecucao, TestStop,
// TestStopMovel, TestOCO, TestCorrecoesRevisao, TestRevisaoOco,
// TestRevisaoStopMovel, TestCompatibilidadeStop.test_descricao_do_stop).

import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/metas/descricao.dart';
import 'package:calculadoradarf/nucleo/metas/verificacao.dart' as ver;
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/mesclagem.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';

/// `TestStopMovel.barras`: [n] pregões consecutivos terminando em [fim].
List<BarraDiaria> _barras({
  int n = 30,
  String fim = '2026-10-22',
  double alta = 11.0,
  double baixa = 9.0,
  double fech = 10.0,
}) => [
  for (var i = 0; i < n; i++)
    dia(somarDias(fim, -(n - 1 - i)), alta, baixa, fech),
];

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  Future<ver.RelatorioMetas?> verificar(
    List<Barra> barras, {
    DataHora? agora,
  }) => base.verificar(barras, agora: agora);

  List<String> vendas() => [for (final v in base.lote().vendas) v.id];

  // TestStop.stop
  Meta stop([double preco = 9.0]) =>
      criarStop(base.repo, base.cfg, 'L1', 100, preco, agora: base.criada);

  // TestStopMovel.movel
  Meta movel([double preco = 5.0]) => criarStop(
    base.repo,
    base.cfg,
    'L1',
    100,
    preco,
    movel: true,
    agora: base.criada,
  );

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

  // TestOCO.metas: as metas gravadas, por id.
  Map<String, Meta> metas() => {
    for (final m in base.repo.lerConfig().metas) m.id: m,
  };

  group('TestCriacao', () {
    test('TestCriacao.test_cancelar', () async {
      final m = base.criar();
      cancelarMeta(base.repo, base.cfg, m.id);
      expect(base.cfg.metas[0].status, 'cancelada');
      expect(await verificar([barra('2026-10-21T10:00:00', 30)]), isNull);
      expect(restante(base.lote()), 100);
    });
  });

  group('TestExecucao', () {
    test('TestExecucao.test_executa_no_preco_alvo_e_data_da_barra', () async {
      final m = base.criar();
      final rel = await verificar([barra('2026-10-21T10:30:00', 21.9)]);
      expect(rel!.executadas.length, 1);
      final meta = base.repo.lerConfig().metas[0];
      expect(meta.status, 'executada');
      final ex = meta.execucao!;
      expect(
        (ex['data'], ex['hora'], ex['preco_usado']),
        ('2026-10-21', '10:30', 21.78),
      );
      expect(ex['venda_id'], 'auto-${m.id}');
      expect(ex['motivo'], contains('21,90'));
      expect(ex['origem'], contains('1m'));
      final v = base.lote().vendas[0];
      expect(
        (v.id, v.data, v.qtd, v.preco),
        ('auto-${m.id}', '2026-10-21', 100, 21.78),
      );
      expect(restante(base.lote()), 0);
      expect(apurar(base.repo.carregar('2026-10')).ops.length, 1);
    });

    test('TestExecucao.test_segunda_verificacao_nao_duplica', () async {
      base.criar();
      final barras = [barra('2026-10-21T10:30:00', 22)];
      await verificar(barras);
      expect(await verificar(barras), isNull); // nada mais ativo
      expect(base.lote().vendas.length, 1);
    });

    test(
      'TestExecucao.test_meta_executada_nao_reexecuta_mesmo_forcada',
      () async {
        base.criar();
        final barras = [barra('2026-10-21T10:30:00', 22)];
        await verificar(barras);
        final rel = ver.aplicar(base.repo, base.cfg, {
          'PETR4': ver.HistoricoOk(
            await historicoFixo(barras)('PETR4', base.criada),
          ),
        });
        expect(rel.executadas, isEmpty);
        expect(base.lote().vendas.length, 1);
      },
    );

    test('TestExecucao.test_reinicio_reconcilia_sem_duplicar', () async {
      final m = base.criar();
      // simula o app fechado entre a gravação da venda e a do status
      final d = base.repo.carregar('2026-10');
      d.lotes[0].vendas.add(
        Venda(id: 'auto-${m.id}', data: '2026-10-21', qtd: 100, preco: 21.78),
      );
      base.repo.salvar(d);
      final cfg2 = base.repo.lerConfig();
      expect(cfg2.metas[0].status, 'ativa');
      final rel = await ver.verificar(
        base.repo,
        cfg2,
        historicoFixo([barra('2026-10-22T10:00:00', 40)]),
        agora: dt('2026-10-25T18:00:00'),
      );
      expect(rel!.reconciliadas.length, 1);
      expect(cfg2.metas[0].status, 'executada');
      expect(base.repo.lerConfig().metas[0].status, 'executada');
      expect(base.lote().vendas.length, 1);
      expect(base.lote().vendas[0].data, '2026-10-21');
    });

    test('TestExecucao.test_app_fechado_dias_depois', () async {
      base.criar();
      final barras = [
        barra('2026-10-22T14:20:00', 21.0),
        barra('2026-10-23T10:05:00', 21.80),
        barra('2026-10-24T10:05:00', 25),
      ];
      await verificar(barras, agora: dt('2026-10-29T09:00:00'));
      expect(base.lote().vendas[0].data, '2026-10-23');
      expect(base.cfg.metas[0].execucao!['hora'], '10:05');
    });

    test('TestExecucao.test_sem_atingir_permanece_ativa_sem_erro', () async {
      base.criar();
      await verificar([barra('2026-10-21T10:00:00', 20)]);
      expect(base.cfg.metas[0].status, 'ativa');
      expect(base.cfg.metas[0].ultimoErro, isNull);
      expect(base.lote().vendas, isEmpty);
    });

    test(
      'TestExecucao.test_quantidade_insuficiente_na_execucao_invalida',
      () async {
        base.criar();
        final d = base.repo.carregar('2026-10');
        d.lotes[0].vendas.add(
          Venda(id: 'manual', data: '2026-10-19', qtd: 60, preco: 12.0),
        );
        base.repo.salvar(d);
        final rel = await verificar([barra('2026-10-21T10:00:00', 30)]);
        expect(rel!.invalidas.length, 1);
        final meta = base.cfg.metas[0];
        expect(meta.status, 'inválida');
        expect(meta.ultimoErro, contains('Quantidade insuficiente'));
        expect(vendas(), ['manual']); // venda manual intacta
      },
    );

    test('TestExecucao.test_falha_de_fonte_mantem_ativa_com_erro', () async {
      base.criar();
      final rel = await ver.verificar(
        base.repo,
        base.cfg,
        historicoErro,
        agora: dt('2026-10-25T18:00:00'),
      );
      expect(rel!.erros.length, 1);
      final meta = base.repo.lerConfig().metas[0];
      expect(meta.status, 'ativa');
      expect(meta.ultimoErro, contains('Sem dados'));
      expect(base.lote().vendas, isEmpty);
      // a próxima verificação com sucesso limpa o erro
      await verificar([barra('2026-10-21T10:00:00', 20)]);
      expect(base.cfg.metas[0].ultimoErro, isNull);
    });

    test('TestExecucao.test_falha_generica_vira_mensagem', () async {
      base.criar();
      await ver.verificar(
        base.repo,
        base.cfg,
        (t, d) async => throw ErroConexao('x'),
      );
      expect(base.cfg.metas[0].ultimoErro, 'Sem conexão com a internet.');
    });

    test('TestExecucao.test_trava_concorrente', () async {
      base.criar();
      expect(ver.tentarIniciarVerificacao(), isTrue);
      try {
        expect(await verificar([barra('2026-10-21T10:00:00', 99)]), isNull);
      } finally {
        ver.encerrarVerificacao();
      }
      expect(base.lote().vendas, isEmpty);
    });

    test('TestExecucao.test_alvo_em_mes_seguinte_aguarda_fechamento_e_executa_depois', () async {
      base.criar();
      final barras = [barra('2026-11-03T10:00:00', 30)];
      final rel = await verificar(barras, agora: dt('2026-11-04T09:00:00'));
      expect(rel!.aguardando.length, 1);
      expect(base.cfg.metas[0].status, 'ativa');
      expect(base.cfg.metas[0].ultimoErro, contains('Feche o mês'));
      expect(base.lote().vendas, isEmpty);
      fecharMes(base.repo, base.repo.carregar('2026-10'));
      await verificar(barras, agora: dt('2026-11-04T09:00:00'));
      expect(base.cfg.metas[0].status, 'executada');
      expect(base.repo.carregar('2026-10').lotes[0].vendas, isEmpty);
      final carregado = base.repo.carregar('2026-11').lotes[0];
      expect(carregado.vendas[0].data, '2026-11-03');
    });

    test('TestExecucao.test_mes_fechado_invalida', () async {
      base.criar();
      fecharMes(base.repo, base.repo.carregar('2026-10'));
      await verificar([
        barra('2026-10-21T10:00:00', 30),
      ], agora: dt('2026-11-04T09:00:00'));
      expect(base.cfg.metas[0].status, 'inválida');
      expect(base.cfg.metas[0].ultimoErro, contains('fechado'));
    });
  });

  group('TestStop', () {
    test('TestStop.test_maxima_acima_do_alvo_nao_dispara_stop', () async {
      stop(9.0);
      await verificar([barraS('2026-10-21T10:00:00', 50, 9.5, 10)]);
      expect(base.cfg.metas[0].status, 'ativa');
      expect(base.lote().vendas, isEmpty);
    });

    test('TestStop.test_execucao_no_stop', () async {
      final m = stop(9.0);
      final rel = await verificar([
        barraS('2026-10-21T10:30:00', 10, 8.95, 9.5),
      ]);
      expect(rel!.executadas.length, 1);
      final ex = base.cfg.metas[0].execucao!;
      expect(
        (ex['preco_usado'], ex['gatilho'], ex['data']),
        (9.0, 'stop', '2026-10-21'),
      );
      expect(ex['motivo'], contains('mínima 8,95 ≤ stop 9,00'));
      expect(base.lote().vendas[0].preco, 9.0);
      expect(base.lote().vendas[0].id, 'auto-${m.id}');
      expect(apurar(base.repo.carregar('2026-10')).ops[0].imposto, 0);
    });

    test('TestStop.test_gap_de_baixa_usa_a_abertura', () async {
      stop(9.0);
      await verificar([barraS('2026-10-21T10:00:00', 9.0, 8.4, 8.5)]);
      final ex = base.cfg.metas[0].execucao!;
      expect(ex['preco_usado'], 8.5);
      expect(ex['motivo'], contains('abertura em gap 8,50'));
    });

    test('TestStop.test_abertura_acima_do_stop_executa_no_stop', () async {
      stop(9.0);
      await verificar([barraS('2026-10-21T10:00:00', 9.5, 8.9, 9.2)]);
      expect(base.cfg.metas[0].execucao!['preco_usado'], 9.0);
    });
  });

  group('TestStopMovel', () {
    test('TestStopMovel.test_falha_de_dados_mantem_o_stop', () async {
      movel(4.0);
      Future<HistoricoIntradiario> historico(String t, DataHora d) async =>
          HistoricoIntradiario(
            barras: [barraS('2026-10-21T10:00:00', 10, 9.0)],
            fonte: 'Yahoo',
            intervalo: '1h',
          );
      Future<Diarias> quebra(String t, String d) => throw SemDados('sem dados');
      await ver.verificar(
        base.repo,
        base.cfg,
        historico,
        agora: dt('2026-10-25T18:00:00'),
        diarias: quebra,
      );
      expect(base.cfg.metas[0].stopAtual, 4.0);
      expect(base.cfg.metas[0].status, 'ativa');
    });

    test('TestStopMovel.test_verificar_sobe_o_stop_e_depois_dispara', () async {
      movel(4.0);
      final horario = [
        barraS('2026-10-21T10:00:00', 10, 5.5, 6.0),
        barraS('2026-10-22T10:00:00', 10, 4.9, 6.0),
      ];
      Future<HistoricoIntradiario> historico(String t, DataHora d) async =>
          HistoricoIntradiario(
            barras: horario,
            fonte: 'Yahoo',
            intervalo: '1h',
          );
      Future<Diarias> diarias(String t, String d) async => Diarias(
        barras: _barras(fim: '2026-10-22'),
        hoje: '2026-10-23',
      );
      final rel = await ver.verificar(
        base.repo,
        base.cfg,
        historico,
        agora: dt('2026-10-23T09:00:00'),
        diarias: diarias,
      );
      expect(rel!.executadas.length, 1);
      final meta = base.cfg.metas[0];
      expect(meta.stopAtual, 5.0);
      expect(meta.execucao!['data'], '2026-10-22');
    });
  });

  group('TestOCO', () {
    test('TestOCO.test_alvo_executa_e_cancela_o_stop', () async {
      final (a, s) = par();
      final rel = await verificar([barraS('2026-10-21T10:00:00', 30, 15, 16)]);
      expect([for (final m in rel!.executadas) m.id], [a.id]);
      final m = metas();
      expect((m[a.id]!.status, m[s.id]!.status), ('executada', 'cancelada'));
      expect(m[s.id]!.canceladaPor, a.id);
      expect(
        m[s.id]!.canceladaDetalhe,
        contains('Cancelada automaticamente (OCO): alvo executado em 21/10'),
      );
      expect(vendas(), ['auto-${a.id}']);
    });

    test('TestOCO.test_stop_executa_e_cancela_o_alvo', () async {
      final (a, s) = par();
      await verificar([barraS('2026-10-21T10:00:00', 12, 8.5, 9.5)]);
      final m = metas();
      expect((m[a.id]!.status, m[s.id]!.status), ('cancelada', 'executada'));
      expect(m[a.id]!.canceladaDetalhe, contains('stop executado'));
      expect(vendas(), ['auto-${s.id}']);
    });

    test('TestOCO.test_mesma_barra_vence_o_stop', () async {
      final (a, s) = par();
      await verificar([barraS('2026-10-21T10:00:00', 30, 8.0, 15)]);
      final m = metas();
      expect((m[a.id]!.status, m[s.id]!.status), ('cancelada', 'executada'));
      expect(base.lote().vendas.length, 1);
    });

    test('TestOCO.test_barras_diferentes_vence_a_mais_cedo', () async {
      final (a, s) = par();
      await verificar([
        barraS('2026-10-21T10:00:00', 30, 15, 16),
        barraS('2026-10-22T10:00:00', 12, 8.0, 9.5),
      ]);
      expect(metas()[a.id]!.status, 'executada');
      expect(metas()[s.id]!.status, 'cancelada');
    });

    test('TestOCO.test_stop_antes_do_alvo', () async {
      final (a, s) = par();
      await verificar([
        barraS('2026-10-21T10:00:00', 12, 8.0, 9.5),
        barraS('2026-10-22T10:00:00', 30, 15, 16),
      ]);
      expect(metas()[s.id]!.status, 'executada');
      expect(metas()[a.id]!.status, 'cancelada');
    });
  });

  group('TestCorrecoesRevisao', () {
    test(
      'TestCorrecoesRevisao.test_fechar_mes_com_verificacao_falha_e_bloqueado',
      () async {
        base.criar();
        final res = await ver.prepararFechamento(
          base.repo,
          base.cfg,
          '2026-10',
          historicoErro,
          agora: dt('2026-10-31T18:00:00'),
        );
        expect(res.bloqueio, contains('Sem dados'));
        expect(base.cfg.metas[0].status, 'ativa');
      },
    );

    test(
      'TestCorrecoesRevisao.test_fechar_mes_registra_meta_atingida_antes',
      () async {
        base.criar();
        final res = await ver.prepararFechamento(
          base.repo,
          base.cfg,
          '2026-10',
          historicoFixo([barra('2026-10-21T10:00:00', 30)]),
          agora: dt('2026-10-31T18:00:00'),
        );
        expect(res.bloqueio, isNull);
        expect(res.executadas.length, 1);
        expect(base.cfg.metas[0].status, 'executada');
        expect(base.lote().vendas.length, 1);
      },
    );

    test(
      'TestCorrecoesRevisao.test_fechar_mes_sem_metas_nao_consulta',
      () async {
        Future<HistoricoIntradiario> naoChama(String t, DataHora d) =>
            throw StateError('não deveria consultar');
        final res = await ver.prepararFechamento(
          base.repo,
          base.cfg,
          '2026-10',
          naoChama,
        );
        expect(res.bloqueio, isNull);
      },
    );

    test('TestCorrecoesRevisao.test_fechar_mes_com_verificacao_em_andamento_bloqueia', () async {
      base.criar();
      expect(ver.tentarIniciarVerificacao(), isTrue);
      final ver.PreparoFechamento res;
      try {
        res = await ver.prepararFechamento(
          base.repo,
          base.cfg,
          '2026-10',
          historicoFixo([]),
        );
      } finally {
        ver.encerrarVerificacao();
      }
      expect(res.bloqueio, contains('em andamento'));
    });
  });

  group('TestRevisaoOco', () {
    // TestRevisaoOco.setUp: o lote passa a ter 200 ações
    setUp(() {
      final d = base.repo.carregar('2026-10');
      d.lotes[0].qtd = 200;
      base.repo.salvar(d);
    });

    // TestRevisaoOco.registrar_venda
    void registrarVenda(
      Meta meta,
      String data,
      double preco, {
      String hora = '10:00',
      bool oco = true,
    }) {
      final d = base.repo.carregar('2026-10');
      d.lotes[0].vendas.add(
        Venda(id: 'auto-${meta.id}', data: data, qtd: meta.qtd, preco: preco),
      );
      base.repo.salvar(d);
      meta.status = 'executada';
      meta.execucao = {
        'venda_id': 'auto-${meta.id}',
        'data': data,
        'hora': hora,
        'preco_usado': preco,
        'origem': 'teste',
        'barra_ts': 0,
        'motivo': 'teste',
      };
      if (!oco) meta.oco = null;
      base.repo.gravarConfig(base.cfg);
    }

    Map<String, Meta> porId() => {for (final m in base.cfg.metas) m.id: m};

    test(
      'TestRevisaoOco.test_alvo_executado_sem_oco_cancela_o_stop_com_oco',
      () async {
        final (a, s) = par();
        // aparelho antigo perdeu o "oco" do alvo
        registrarVenda(a, '2026-10-21', 21.78, oco: false);
        final rel = await verificar([
          barraS('2026-10-22T10:00:00', 10, 8.5, 9.5),
        ]);
        expect(rel!.executadas, isEmpty);
        expect(porId()[s.id]!.status, 'cancelada');
        expect(porId()[s.id]!.canceladaPor, a.id);
        expect(vendas(), ['auto-${a.id}']);
        expect(rel.mudou, isTrue);
      },
    );

    test(
      'TestRevisaoOco.test_stop_executado_sem_oco_cancela_o_alvo_com_oco',
      () async {
        final (a, s) = par();
        registrarVenda(s, '2026-10-21', 9.0, oco: false);
        final rel = await verificar([barra('2026-10-22T10:00:00', 30.0)]);
        expect(rel!.executadas, isEmpty);
        expect(porId()[a.id]!.status, 'cancelada');
        expect(vendas(), ['auto-${s.id}']);
      },
    );

    test('TestRevisaoOco.test_stop_de_outro_par_nao_e_cancelado', () async {
      // alvo avulso executado; o stop tem como parceiro outro alvo ativo: é
      // outro OCO, não pode ser cancelado
      final avulso = criarMeta(
        base.repo,
        base.cfg,
        'L1',
        100,
        25.0,
        agora: base.criada,
      );
      final d = base.repo.carregar('2026-10');
      d.lotes[0].qtd = 300;
      base.repo.salvar(d);
      final (a2, s2) = par();
      registrarVenda(avulso, '2026-10-21', 25.0);
      await verificar([barraS('2026-10-22T10:00:00', 10, 8.5, 9.5)]);
      expect(porId()[s2.id]!.status, 'executada');
      expect(porId()[a2.id]!.status, 'cancelada');
    });

    test('TestRevisaoOco.test_quantidade_diferente_nao_cancela', () async {
      final a = criarMeta(
        base.repo,
        base.cfg,
        'L1',
        50,
        21.78,
        agora: base.criada,
      );
      final s = criarStop(
        base.repo,
        base.cfg,
        'L1',
        100,
        9.0,
        agora: base.criada,
      );
      s.oco = 'oco-solto';
      registrarVenda(a, '2026-10-21', 21.78, oco: false);
      await verificar([barraS('2026-10-22T10:00:00', 10, 8.5, 9.5)]);
      expect(porId()[s.id]!.status, 'executada');
    });

    test('TestRevisaoOco.test_resolver_oco_mes_fechado_nao_apaga_a_venda', () {
      final (a, s) = par();
      registrarVenda(a, '2026-10-22', 21.78);
      registrarVenda(s, '2026-10-21', 9.0);
      final d = base.repo.carregar('2026-10');
      d.fechado = true;
      final avisos = <String>[];
      final alterados = resolverOco(
        {'2026-10': d},
        base.cfg.metas,
        avisos: avisos,
      );
      expect(alterados, isEmpty);
      expect(
        [for (final v in d.lotes[0].vendas) v.id],
        ['auto-${a.id}', 'auto-${s.id}'],
      );
      expect(d.excluidos.containsKey('auto-${a.id}'), isFalse);
      expect(a.status, 'cancelada');
      expect(a.canceladaDetalhe, contains('fechado'));
      expect(a.canceladaDetalhe, contains('ajuste manual'));
      expect(avisos.length, 1);
      expect(avisos[0], contains(a.ticker));
    });

    test(
      'TestRevisaoOco.test_reconciliacao_com_as_duas_vendas_remove_a_perdedora',
      () async {
        final (a, s) = par();
        final d = base.repo.carregar('2026-10');
        d.lotes[0].vendas.addAll([
          Venda(id: 'auto-${a.id}', data: '2026-10-22', qtd: 100, preco: 21.78),
          Venda(id: 'auto-${s.id}', data: '2026-10-21', qtd: 100, preco: 9.0),
        ]);
        // as duas vendas existem, mas as duas metas ainda estão ativas (queda
        // no meio)
        base.repo.salvar(d);
        final rel = await verificar([barra('2026-10-22T10:00:00', 1.0)]);
        expect(
          (porId()[a.id]!.status, porId()[s.id]!.status),
          ('cancelada', 'executada'),
        );
        expect(vendas(), ['auto-${s.id}']);
        expect(
          base.repo.carregar('2026-10').excluidos.containsKey('auto-${a.id}'),
          isTrue,
        );
        expect(rel!.mudou, isTrue);
      },
    );

    test('TestRevisaoOco.test_reconciliacao_com_as_duas_vendas_em_mes_fechado_avisa', () async {
      final (a, s) = par();
      final d = base.repo.carregar('2026-10');
      d.lotes[0].vendas.addAll([
        Venda(id: 'auto-${a.id}', data: '2026-10-22', qtd: 100, preco: 21.78),
        Venda(id: 'auto-${s.id}', data: '2026-10-21', qtd: 100, preco: 9.0),
      ]);
      d.fechado = true;
      base.repo.salvar(d);
      final rel = await verificar([barra('2026-10-22T10:00:00', 1.0)]);
      expect(vendas().length, 2);
      expect(rel!.avisos.length, 1);
    });
  });

  test(
    'TestRevisaoStopMovel.test_hoje_do_stop_movel_nao_fica_atras_do_relogio',
    () {
      final m = criarStop(
        base.repo,
        base.cfg,
        'L1',
        100,
        4.0,
        movel: true,
        agora: base.criada,
      );
      final barras = [
        for (var i = 0; i < 29; i++)
          BarraDiaria(
            data: somarDias('2026-10-22', -(29 - i)),
            abre: 10.0,
            alta: 11.0,
            baixa: 9.0,
            fech: 10.0,
          ),
        BarraDiaria(
          data: '2026-10-22',
          abre: 19.0,
          alta: 20.0,
          baixa: 19.0,
          fech: 20.0,
        ),
      ];
      // cache de 22/10 lido em 25/10
      final cacheVelho = Diarias(barras: barras, hoje: '2026-10-22');
      final hist = HistoricoIntradiario(
        barras: [barraS('2026-10-23T10:00:00', 30.0, 25.0, 26.0)],
        fonte: 'Yahoo Finance',
        intervalo: '?',
        diarias: cacheVelho,
      );
      ver.aplicar(base.repo, base.cfg, {
        'PETR4': ver.HistoricoOk(hist),
      }, agora: dt('2026-10-25T18:00:00'));
      // o pregão de 22/10 já estava fechado
      expect(m.stopAtual!, greaterThan(12.0));
    },
  );

  test('TestCompatibilidadeStop.test_descricao_do_stop', () {
    final a = criarMeta(
      base.repo,
      base.cfg,
      'L1',
      100,
      12.0,
      agora: base.criada,
    );
    final s = criarStop(
      base.repo,
      base.cfg,
      'L1',
      100,
      9.0,
      movel: true,
      ocoCom: a.id,
      agora: base.criada,
    );
    final d = descricao(s, todas: base.cfg.metas);
    expect(d.titulo, 'PETR4 · 100 un. · stop R\$ 9,00 (móvel)');
    expect(d.detalhe, contains('OCO com alvo R\$ 12,00'));
    expect(
      descricao(a, todas: base.cfg.metas).detalhe,
      contains('OCO com stop R\$ 9,00'),
    );
  });
}
