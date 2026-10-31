// Porte de tests/test_venda_retroativa.py.

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

/// `assertAlmostEqual` do unittest (7 casas).
Matcher _quase(double esperado) => closeTo(esperado, 5e-8);

void main() {
  late Repositorio repo;
  late Mes d;

  setUp(() {
    ambiente = Ambiente.fixo();
    repo = Repositorio(ArmazenamentoMemoria());
    d = mesVazio('2026-10');
    d.lotes.add(
      Lote(
        id: 'L1',
        ticker: 'T1TW34',
        tipo: 'BDR',
        dataCompra: '2026-05-05',
        qtd: 58,
        preco: 9.0,
      ),
    );
    repo.salvar(d);
  });

  tearDown(() => ambiente = Ambiente.sistema());

  ({String data, int qtd, double preco}) venda(
    String data,
    int qtd,
    double preco,
  ) => (data: data, qtd: qtd, preco: preco);

  test('TestVendaRetroativa.test_meses_livres_e_bloqueados', () {
    expect(mesAceitaVendaRetroativa(repo, '2026-07', '2026-10'), isTrue);
    // mês atual: fluxo normal
    expect(mesAceitaVendaRetroativa(repo, '2026-10', '2026-10'), isFalse);
    // mês normal com compra levada
    final set = Mes(mes: '2026-09', fechado: true);
    set.lotes.add(
      Lote(
        id: 'S1',
        ticker: 'X',
        tipo: 'Ação',
        dataCompra: '2026-09-01',
        qtd: 5,
        preco: 1.0,
      ),
    );
    repo.salvar(set);
    expect(mesAceitaVendaRetroativa(repo, '2026-09', '2026-10'), isFalse);
    // mês aberto
    repo.salvar(mesVazio('2026-08'));
    expect(mesAceitaVendaRetroativa(repo, '2026-08', '2026-10'), isFalse);
  });

  test('TestVendaRetroativa.test_mes_retroativo_vale_sem_a_marcacao', () {
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 20, 10.0));
    final jul = repo.carregar('2026-07');
    // a planilha não guarda essa marcação
    jul.retroativo = false;
    repo.salvar(jul);
    expect(mesAceitaVendaRetroativa(repo, '2026-07', '2026-10'), isTrue);
  });

  test(
    'TestVendaRetroativa.test_grava_no_mes_da_venda_e_reduz_compra_atual',
    () {
      final mes = registrarVendaRetroativa(
        repo,
        d,
        'L1',
        venda('2026-07-15', 20, 10.0),
      );
      expect(mes, '2026-07');
      final jul = repo.carregar('2026-07');
      expect(jul.fechado, isTrue);
      expect(jul.retroativo, isTrue);
      expect(jul.lotes.length, 1);
      final l = jul.lotes[0];
      expect(
        (l.ticker, l.dataCompra, l.qtd, l.preco),
        ('T1TW34', '2026-05-05', 20, 9.0),
      );
      expect(
        [for (final v in l.vendas) (v.data, v.qtd, v.preco)],
        [('2026-07-15', 20, 10.0)],
      );
      expect(jul.resumo!.darf, _quase(apurar(jul).darf));
      expect(repo.carregar('2026-10').lotes[0].qtd, 38);
      // outra venda de julho continua possível
      expect(mesAceitaVendaRetroativa(repo, '2026-07', '2026-10'), isTrue);
      expect(repo.mesInicial(), '2026-10');
    },
  );

  test('TestVendaRetroativa.test_venda_total_remove_compra_do_mes_atual', () {
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 58, 10.0));
    expect(repo.carregar('2026-10').lotes, isEmpty);
  });

  test('TestVendaRetroativa.test_segunda_venda_no_mesmo_mes', () {
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 20, 10.0));
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-20', 8, 11.0));
    final jul = repo.carregar('2026-07');
    expect(jul.lotes.fold(0, (s, l) => s + l.qtd), 28);
    expect(repo.carregar('2026-10').lotes[0].qtd, 30);
  });

  test('TestVendaRetroativa.test_recusa_compra_com_venda_no_mes_atual', () {
    // reduzir a quantidade mudaria a corretagem (e a DARF) da venda já feita
    // no mês atual
    d.lotes[0].vendas.add(
      Venda(id: 'V1', data: '2026-10-10', qtd: 10, preco: 10.0),
    );
    expect(
      () => registrarVendaRetroativa(
        repo,
        d,
        'L1',
        venda('2026-07-15', 20, 10.0),
      ),
      throwsA(isA<ErroValidacao>()),
    );
    expect(repo.existeMes('2026-07'), isFalse);
    expect(d.lotes[0].qtd, 58);
  });

  test('TestVendaRetroativa.test_darf_pequena_vai_para_o_mes_aberto', () {
    // lucro pequeno: DARF de julho < R$ 10 entra como darf_anterior de outubro
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 10, 10.0));
    final darfJul = repo.carregar('2026-07').resumo!.darf;
    expect(darfJul > 0 && darfJul < darfMinimo, isTrue);
    expect(repo.carregar('2026-10').darfAnterior, _quase(darfJul));
    // segunda venda em julho: DARF passa de R$ 10, sai de outubro e fica em
    // julho
    registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-20', 30, 12.0));
    expect(
      repo.carregar('2026-07').resumo!.darf,
      greaterThanOrEqualTo(darfMinimo),
    );
    expect(repo.carregar('2026-10').darfAnterior, _quase(0.0));
  });

  test('TestVendaRetroativa.test_lote_levado_nao_gera_novo_debito', () {
    d.lotes[0].origem = 'L0';
    repo.salvar(d);
    // TODO Tarefa 10: `lancamentosCaixa` ainda não existe. Corpo do Python:
    //   antes = soma dos lancamentosCaixa(repo) com tipo 'Compra' (valor)
    //   registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 20, 10.0))
    //   depois = a mesma soma
    //   expect(antes, _quase(depois))
  }, skip: 'Tarefa 10');

  test('TestVendaRetroativa.test_caixa_nao_duplica_compra', () {
    // TODO Tarefa 10: `lancamentosCaixa` ainda não existe. Corpo do Python:
    //   antes = soma dos lancamentosCaixa(repo) com tipo 'Compra' (valor)
    //   registrarVendaRetroativa(repo, d, 'L1', venda('2026-07-15', 20, 10.0))
    //   depois = a mesma soma
    //   expect(antes, _quase(depois))
  }, skip: 'Tarefa 10');
}
