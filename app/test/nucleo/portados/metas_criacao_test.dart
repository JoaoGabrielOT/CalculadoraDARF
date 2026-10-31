// Porte dos testes de criação, cancelamento, OCO e ida e volta pela planilha de
// tests/test_metas.py. Entradas de texto ("x" como preço ou quantidade) são
// impossíveis com os tipos Dart e saem; os demais valores ficam.

import 'package:calculadoradarf/nucleo/compat/conversao.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/metas/cadeia.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/metas/preco_alvo.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/planilha/reconstrucao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';

final Matcher _erro = throwsA(isA<ErroValidacao>());

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  Map<String, List<List<Object?>>> linhas() =>
      montarLinhas(base.repo.carregarMeses().values.toList(), base.cfg);

  // TestStop.stop
  Meta stop({
    double preco = 9.0,
    int qtd = 100,
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) => criarStop(
    base.repo,
    base.cfg,
    'L1',
    qtd,
    preco,
    movel: movel,
    ocoCom: ocoCom,
    precoAtual: precoAtual,
    agora: base.criada,
    sugestao: sugestao,
  );

  // TestOCO.par
  (Meta, Meta) par({int qtd = 100, double alvo = 21.78, double stop = 9.0}) {
    final a = criarMeta(
      base.repo,
      base.cfg,
      'L1',
      qtd,
      alvo,
      agora: base.criada,
    );
    final s = criarStop(
      base.repo,
      base.cfg,
      'L1',
      qtd,
      stop,
      ocoCom: a.id,
      agora: base.criada,
    );
    return (a, s);
  }

  group('TestCriacao', () {
    test('TestCriacao.test_criacao_valida', () {
      final m = base.criar();
      expect(m.status, 'ativa');
      expect(m.id.startsWith('meta-'), isTrue);
      expect(m.criadaEm.endsWith('-03:00'), isTrue);
      expect(base.repo.lerConfig().metas[0].id, m.id);
    });

    test('TestCriacao.test_quantidade_insuficiente_bloqueada', () {
      expect(
        () => base.criar(qtd: 101),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('disponível'),
          ),
        ),
      );
      expect(base.cfg.metas, isEmpty);
    });

    test('TestCriacao.test_quantidade_reservada_por_outra_meta', () {
      base.criar(qtd: 80);
      expect(() => base.criar(qtd: 30), _erro);
      base.criar(qtd: 20);
    });

    test('TestCriacao.test_preco_e_lote_invalidos', () {
      for (final alvo in [0.0, -1.0]) {
        expect(() => base.criar(alvo: alvo), _erro);
      }
      expect(
        () => criarMeta(base.repo, base.cfg, 'inexistente', 10, 20.0),
        _erro,
      );
    });
  });

  group('TestStop', () {
    test('TestStop.test_criacao', () {
      final m = stop(
        movel: true,
        sugestao: {'modo': 'swing', 'atr14': 1.0, 'atr22': 1.1, 'compra': 10.0},
      );
      expect(
        (m.gatilho, m.stopInicial, m.stopAtual, m.movel),
        ('stop', 9.0, 9.0, true),
      );
      expect(m.niveis![0].stop, 9.0);
      expect(m.toJson().containsKey('preco_alvo'), isFalse);
      expect(gatilho(m), 'stop');
      expect(precoGatilho(m), 9.0);
      expect(base.repo.lerConfig().metas[0].id, m.id);
    });

    test('TestStop.test_meta_sem_gatilho_e_alvo', () {
      final m = base.criar();
      expect(m.toJson().containsKey('gatilho'), isFalse);
      expect(gatilho(m), 'alvo');
      expect(precoGatilho(m), 21.78);
    });

    test('TestStop.test_validacoes', () {
      for (final preco in [0.0, -1.0, double.infinity, double.nan]) {
        expect(() => stop(preco: preco), _erro);
      }
      expect(
        () => stop(preco: 10.0, precoAtual: 10.0),
        _erro,
      ); // stop >= cotação
      expect(() => stop(qtd: 101), _erro);
      stop(preco: 9.99, precoAtual: 10.0);
      expect(base.cfg.metas.length, 1);
    });
  });

  group('TestOCO', () {
    test(
      'TestOCO.test_par_compartilha_o_mesmo_oco_e_a_reserva_conta_uma_vez',
      () {
        final (a, s) = par();
        expect(a.oco!.startsWith('oco-'), isTrue);
        expect(a.oco, s.oco);
        expect(reservado(base.repo, base.cfg, 'L1'), 100);
        expect(
          () =>
              criarMeta(base.repo, base.cfg, 'L1', 1, 30.0, agora: base.criada),
          _erro,
        );
        expect(lotesParaMeta(base.repo, base.cfg), isEmpty);
      },
    );

    test('TestOCO.test_posicoes_abertas_mostra_livre_zero', () {
      par();
      final p = posicoesAbertas(base.repo, base.cfg)[0];
      expect(
        (p.mes, p.restante, p.livre, p.ativas.length),
        ('2026-10', 100, 0, 2),
      );
    });

    test('TestOCO.test_recusas', () {
      final a = criarMeta(
        base.repo,
        base.cfg,
        'L1',
        100,
        21.78,
        agora: base.criada,
      );
      // quantidade diferente
      expect(() => stop(qtd: 50, ocoCom: a.id), _erro);
      // mesmo gatilho
      expect(
        () => criarMeta(
          base.repo,
          base.cfg,
          'L1',
          100,
          25.0,
          ocoCom: a.id,
          agora: base.criada,
        ),
        _erro,
      );
      expect(() => stop(ocoCom: 'meta-inexistente'), _erro);
      final s = stop(ocoCom: a.id);
      // alvo já tem par
      expect(() => stop(preco: 8.0, ocoCom: a.id), _erro);
      expect(base.cfg.metas.length, 2);
      expect(parceiraOco(base.repo, base.cfg, 'L1', 'stop'), isNull);
      cancelarMeta(base.repo, base.cfg, s.id);
      // ficou sem par ativo
      expect(parceiraOco(base.repo, base.cfg, 'L1', 'stop')!.id, a.id);
    });

    test('TestOCO.test_parceira_oco_pelo_gatilho_oposto', () {
      final a = criarMeta(
        base.repo,
        base.cfg,
        'L1',
        100,
        21.78,
        agora: base.criada,
      );
      expect(parceiraOco(base.repo, base.cfg, 'L1', 'stop')!.id, a.id);
      expect(parceiraOco(base.repo, base.cfg, 'L1', 'alvo'), isNull);
    });
  });

  group('TestCorrecoesRevisao', () {
    test('TestCorrecoesRevisao.test_reserva_atravessa_virada_de_mes', () {
      base.criar(qtd: 100);
      fecharMes(base.repo, base.repo.carregar('2026-10'));
      final copia = base.lote(mes: '2026-11', lid: 'L1~2026-11');
      expect(copia.origem, 'L1');
      expect(reservado(base.repo, base.cfg, copia.id), 100);
      expect(lotesParaMeta(base.repo, base.cfg), isEmpty); // 0 livres
      expect(
        () => criarMeta(
          base.repo,
          base.cfg,
          copia.id,
          100,
          25.0,
          agora: base.criada,
        ),
        _erro,
      );
      expect(base.cfg.metas.length, 1);
    });

    test('TestCorrecoesRevisao.test_valores_nao_finitos', () {
      const inf = double.infinity;
      const nan = double.nan;
      for (final (qtd, lucro) in <(double, double)>[
        (inf, 1000),
        (nan, 1000),
        (100, inf),
        (100, nan),
        (100, -inf),
      ]) {
        expect(() => calcularPrecoAlvo(base.lote(), qtd, lucro), _erro);
      }
      for (final (qtd, alvo, lucro) in <(double, double, double?)>[
        (inf, 20, null),
        (nan, 20, null),
        (100, inf, null),
        (100, nan, null),
        (100, 20, inf),
        (100, 20, nan),
      ]) {
        expect(
          () => criarMeta(
            base.repo,
            base.cfg,
            'L1',
            qtd,
            alvo,
            lucroDesejado: lucro,
          ),
          _erro,
        );
      }
      expect(base.cfg.metas, isEmpty);
    });
  });

  test('TestRevisaoMesclagem.test_lotes_abertos_escolhe_a_ultima_copia_antes_de_filtrar', () {
    final d = mesVazio('2026-11');
    d.lotes.add(
      Lote(
        id: 'L1~2026-11',
        origem: 'L1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-10-01',
        qtd: 100,
        preco: 10.0,
        vendas: [Venda(id: 'v1', data: '2026-11-03', qtd: 100, preco: 12.0)],
      ),
    );
    base.repo.salvar(d);
    expect(lotesAbertos(base.repo.carregarMeses()), isEmpty);
  });

  test('TestMesclagem.test_planilha_ida_e_volta', () {
    final m = base.criar();
    m.ultimoErro = 'Sem conexão com a internet.';
    final volta = reconstruirMetas(linhas())[0];
    expect(volta.id, m.id);
    expect(volta.ticker, m.ticker);
    expect(volta.loteId, m.loteId);
    expect(volta.qtd, m.qtd);
    expect(volta.precoAlvo, m.precoAlvo);
    expect(volta.criadaEm, m.criadaEm);
    expect(volta.status, m.status);
    expect(volta.lucroDesejado, m.lucroDesejado);
    expect(volta.ultimoErro, m.ultimoErro);
  });

  group('TestCompatibilidadeStop', () {
    test('TestCompatibilidadeStop.test_planilha_ida_e_volta_do_stop', () {
      final m = criarStop(
        base.repo,
        base.cfg,
        'L1',
        100,
        9.0,
        movel: true,
        agora: base.criada,
        sugestao: {'modo': 'swing', 'atr14': 0.5, 'atr22': 0.6, 'compra': 10.0},
      );
      m.niveis!.add(
        Nivel(desde: '2026-10-22', stop: 9.4, calcEm: '2026-10-21'),
      );
      m.stopAtual = 9.4;
      m.oco = 'oco-x';
      final l = linhas()['Metas']!;
      expect(l[0].length, 14);
      expect(l[0][5], ''); // Preço-alvo vazio no stop
      expect(l[0][12], 'stop');
      final volta = reconstruirMetas({'Metas': l})[0];
      expect(volta.id, m.id);
      expect(volta.ticker, m.ticker);
      expect(volta.loteId, m.loteId);
      expect(volta.qtd, m.qtd);
      expect(volta.gatilho, m.gatilho);
      expect(volta.stopInicial, m.stopInicial);
      expect(volta.stopAtual, m.stopAtual);
      expect(volta.movel, m.movel);
      expect(
        [for (final n in volta.niveis!) n.toJson()],
        [for (final n in m.niveis!) n.toJson()],
      );
      expect(volta.oco, m.oco);
      expect(volta.criadaEm, m.criadaEm);
      expect(volta.status, m.status);
      expect(volta.sugestao, m.sugestao);
      expect(volta.toJson().containsKey('preco_alvo'), isFalse);
    });

    test('TestCompatibilidadeStop.test_detalhes_de_outro_id_sao_ignorados', () {
      criarStop(base.repo, base.cfg, 'L1', 100, 9.0, agora: base.criada);
      var linha = linhas()['Metas']![0];
      linha[0] =
          'meta-outro'; // linha reordenada/colada: detalhes de outra meta
      // stop sem detalhes válidos não vira meta
      expect(
        reconstruirMetas({
          'Metas': [linha],
        }),
        isEmpty,
      );
      cancelarMeta(base.repo, base.cfg, base.cfg.metas[0].id);
      final alvo = base.criar();
      alvo.oco = 'oco-z';
      linha = linhas()['Metas']!.firstWhere((l) => l[0] == alvo.id);
      linha[0] = 'meta-trocada';
      final volta = reconstruirMetas({
        'Metas': [linha],
      })[0];
      expect(volta.oco, isNull);
      expect(volta.precoAlvo, 21.78);
    });

    test('TestCompatibilidadeStop.test_linha_de_12_colunas_e_alvo', () {
      final m = base.criar();
      final linha = linhas()['Metas']![0].sublist(0, 12);
      final volta = reconstruirMetas({
        'Metas': [linha],
      })[0];
      expect((volta.id, volta.precoAlvo), (m.id, 21.78));
      expect(gatilho(volta), 'alvo');
    });

    test(
      'TestCompatibilidadeStop.test_parser_antigo_de_12_colunas_pula_o_stop',
      () {
        criarStop(base.repo, base.cfg, 'L1', 100, 9.0, agora: base.criada);
        final linha = linhas()['Metas']![0].sublist(0, 12);
        // é o que o parser antigo faz com o Preço-alvo vazio: pula a linha
        expect(() => floatPython(linha[5]), throwsFormatException);
      },
    );
  });

  group('TestRevisaoReconstruir', () {
    List<Object?> linhaStop() {
      criarStop(
        base.repo,
        base.cfg,
        'L1',
        100,
        9.0,
        movel: true,
        agora: base.criada,
      );
      return linhas()['Metas']![0];
    }

    test('TestRevisaoReconstruir.test_gatilho_stop_com_detalhes_invalidos_e_preco_valido_vira_alvo', () {
      final linha = linhaStop();
      linha[5] = 12.5;
      linha[13] = '{isto não é json';
      final volta = reconstruirMetas({
        'Metas': [linha],
      });
      expect(volta.length, 1);
      expect((volta[0].precoAlvo, gatilho(volta[0])), (12.5, 'alvo'));
      expect(volta[0].stopAtual, isNull);
    });

    test('TestRevisaoReconstruir.test_detalhes_sem_campos_de_stop_nunca_levantam_keyerror', () {
      final linha = linhaStop();
      linha[13] = '{"id": "${linha[0]}", "gatilho": "stop"}';
      // sem preço-alvo: descartada
      expect(
        reconstruirMetas({
          'Metas': [List<Object?>.of(linha)],
        }),
        isEmpty,
      );
      linha[5] = 12.5;
      final volta = reconstruirMetas({
        'Metas': [linha],
      });
      expect((volta[0].precoAlvo, gatilho(volta[0])), (12.5, 'alvo'));
    });

    test('TestRevisaoReconstruir.test_detalhes_de_niveis_malformados', () {
      final linha = linhaStop();
      linha[13] =
          '{"id": "${linha[0]}", "gatilho": "stop", "stop_inicial": 9, '
          '"stop_atual": 9, "niveis": [{"x": 1}]}';
      expect(
        reconstruirMetas({
          'Metas': [linha],
        }),
        isEmpty,
      );
    });

    test('TestRevisaoReconstruir.test_stop_valido_continua_stop', () {
      final volta = reconstruirMetas({
        'Metas': [linhaStop()],
      })[0];
      expect((gatilho(volta), volta.stopAtual), ('stop', 9.0));
    });
  });
}
