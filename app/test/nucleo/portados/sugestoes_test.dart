// Porte de tests/test_sugestoes.py: TestSugestoes, TestAvaliacaoERisco,
// TestStopAcimaDaCompra, TestPatrimonio e TestTextos (os de indicadores estão
// em indicadores_test.dart e metas_preco_alvo_test.dart).

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/caixa.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/metas/preco_alvo.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:calculadoradarf/nucleo/sugestoes/patrimonio.dart';
import 'package:calculadoradarf/nucleo/sugestoes/sugestoes.dart';
import 'package:calculadoradarf/nucleo/sugestoes/textos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/barras.dart';

/// `assertAlmostEqual` do unittest (7 casas).
Matcher _quase(double esperado) => closeTo(esperado, 5e-8);

/// `lote(...)` de tests/test_sugestoes.py.
Lote lote({
  double preco = 10.0,
  String data = '2026-10-01',
  int qtd = 100,
  String id = 'L1',
  String? origem,
}) => Lote(
  id: id,
  origem: origem,
  ticker: 'PETR4',
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: preco,
);

const _hoje = '2026-10-28';

/// `expect(() => f(), throwsA(isA<SemSugestao>()))`.
void _semSugestao(void Function() f) => expect(f, throwsA(isA<SemSugestao>()));

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  {
    test('TestSugestoes.test_swing', () {
      final s = sugestaoSwing(10.0, barrasPlanas());
      expect(s.stopInicial, _quase(6.0));
      expect(s.chandelier, _quase(5.0));
      expect(s.stop, 6.0);
      expect(s.alvo, 18.0);
      expect(s.modo, 'swing');
    });

    test('TestSugestoes.test_swing_chandelier_maior_vence', () {
      final b = barrasPlanas();
      final alteradas = [
        for (final (i, x) in b.indexed)
          i >= b.length - 5
              ? BarraDiaria(
                  data: x.data,
                  abre: x.abre,
                  alta: 20.0,
                  baixa: x.baixa,
                  fech: x.fech,
                )
              : x,
      ];
      final s = sugestaoSwing(10.0, alteradas);
      expect(s.chandelier! > s.stopInicial!, isTrue);
      expect(s.stop, pisoCentavo(s.chandelier!));
      // alvo pelo stop inicial
      expect(s.alvo, tetoCentavo(10.0 + 2 * (10.0 - s.stopInicial!)));
    });

    test('TestSugestoes.test_swing_historico_curto_sem_movel', () {
      final s = sugestaoSwing(10.0, barrasPlanas(n: 18));
      expect(s.chandelier, isNull);
      expect(s.movelDisponivel, isFalse);
      expect(s.stop, 6.0);
    });

    test('TestSugestoes.test_day_trade', () {
      final dia = BarraDiaria(
        data: '2026-10-28',
        alta: 12.0,
        baixa: 9.0,
        fech: 10.5,
      );
      var s = sugestaoDayTrade(10.0, dia, 2.0);
      expect((s.stop, s.alvo), (9.0, 12.0));
      s = sugestaoDayTrade(11.5, dia, 2.0);
      expect((s.stop, s.alvo), (9.5, 15.5));
      s = sugestaoDayTrade(8.5, dia, 2.0);
      expect((s.stop, s.alvo), (6.5, 12.0));
      expect(s.r1, _quase(12.0));
    });

    test('TestSugestoes.test_volatilidade_zero', () {
      final planas = barrasPlanas(alta: 10.0, baixa: 10.0, fech: 10.0);
      _semSugestao(() => sugestaoSwing(10.0, planas));
      _semSugestao(() => sugestaoDayTrade(10.0, planas.last, 0.0));
    });

    test('TestSugestoes.test_sugerir_usa_so_pregoes_fechados', () {
      final b = barrasPlanas(n: 30); // termina em 28/10
      final sug = sugerir(lote(), b, _hoje, 10.5);
      // a barra de hoje é parcial e fica de fora
      expect(sug.baseData, '2026-10-27');
      expect(sug.modo, 'swing');
    });

    test('TestSugestoes.test_sugerir_day_trade_quando_comprou_hoje', () {
      final sug = sugerir(
        lote(data: '2026-10-28'),
        barrasPlanas(n: 30),
        _hoje,
        10.0,
      );
      expect(sug.modo, 'day_trade');
      expect(sug.avisos.any((a) => a.contains('swing')), isTrue);
    });

    test('TestSugestoes.test_sem_dados_ou_historico_curto', () {
      _semSugestao(() => sugerir(lote(), [], _hoje, 10.0));
      _semSugestao(
        () => sugerir(
          lote(),
          barrasPlanas(n: 14, fim: '2026-10-27'),
          _hoje,
          10.0,
        ),
      );
      // 15 barras fechadas bastam
      sugerir(lote(), barrasPlanas(n: 15, fim: '2026-10-27'), _hoje, 10.0);
    });

    test('TestSugestoes.test_desdobramento_ou_grupamento', () {
      // compra > 3x a cotação
      _semSugestao(
        () => sugerir(lote(preco: 40.0), barrasPlanas(), _hoje, 10.0),
      );
      // compra < 1/3 da cotação
      _semSugestao(
        () => sugerir(lote(preco: 3.0), barrasPlanas(), _hoje, 10.0),
      );
    });

    test('TestSugestoes.test_avisos_stop_e_alvo', () {
      // cotação abaixo do stop 6,00
      var sug = sugerir(lote(), barrasPlanas(), _hoje, 5.0);
      expect(sug.stopValido, isFalse);
      expect(sug.alvoImediato, isFalse);
      // cotação acima do alvo 18,00
      sug = sugerir(lote(), barrasPlanas(), _hoje, 20.0);
      expect(sug.stopValido, isTrue);
      expect(sug.alvoImediato, isTrue);
    });
  }

  {
    test('TestAvaliacaoERisco.test_stop_swing_liquido', () {
      final sug = sugestaoSwing(10.0, barrasPlanas());
      final av = avaliar(lote(), 100, sug, 10.0, false);
      expect(av.perdaStop, closeTo(-400.48, 0.005));
      expect(av.projStop.imposto, 0);
      expect(av.projAlvo.venda, 1800.0);
      expect(av.rrPreco, _quase(2.0));
      expect(av.lucroAlvo > 0, isTrue);
      expect(av.distStopPct, _quase(-40.0));
    });

    test('TestAvaliacaoERisco.test_alerta_de_2_porcento', () {
      // limite 220
      expect(alertaRisco(-400.48, 11000).excede, isTrue);
      // limite 600
      expect(alertaRisco(-400.48, 30000).excede, isFalse);
      expect(alertaRisco(-400.48, 11000).limite, _quase(220.0));
      expect(alertaRisco(-1, 0).excede, isTrue);
    });
  }

  {
    Diarias diarias() => Diarias(
      barras: barrasPlanas(alta: 20.0, baixa: 18.0, fech: 19.0),
      hoje: '2026-10-28',
      preco: 19.0,
      fonte: 'Yahoo Finance',
    );

    test('TestStopAcimaDaCompra.test_avaliar_usa_o_lucro_apos_imposto', () {
      final sug = sugestaoSwing(
        10.0,
        barrasPlanas(alta: 20.0, baixa: 18.0, fech: 19.0),
      );
      expect(sug.stop > 10.0, isTrue);
      final av = avaliar(lote(), 100, sug, 19.0, false);
      final ps = av.projStop;
      expect(ps.imposto > 0, isTrue);
      expect(av.perdaStop, _quase(ps.lucroAposImposto));
      expect(av.perdaStop < ps.liquido, isTrue);
    });

    test(
      'TestStopAcimaDaCompra.test_sem_alerta_e_com_rotulo_de_lucro_protegido',
      () {
        final item = montarItem(
          lote(),
          100,
          diarias(),
          valorPatrimonio: 1000.0,
          hoje: '2026-10-28',
        );
        expect(item.alerta!.excede, isFalse);
        final rotulos = [for (final l in linhasCard(item)) l.$1];
        expect(rotulos, isNot(contains('Alerta de risco')));
        expect(rotulos, isNot(contains('Risco do stop')));
        expect(rotulos, contains('Lucro protegido no stop'));
        final stop = linhasCard(item)
            .firstWhere((l) => l.$1 == 'Stop sugerido');
        expect(stop.$2, isNot(contains('perda')));
      },
    );

    test('TestStopAcimaDaCompra.test_stop_abaixo_da_compra_continua_alertando_a_perda', () {
      final item = montarItem(
        lote(),
        100,
        Diarias(
          barras: barrasPlanas(),
          hoje: '2026-10-28',
          preco: 10.0,
          fonte: 'Yahoo Finance',
        ),
        valorPatrimonio: 11000.0,
        hoje: '2026-10-28',
      );
      expect(item.alerta!.excede, isTrue);
      final rotulos = [for (final l in linhasCard(item)) l.$1];
      expect(rotulos, contains('Alerta de risco'));
      expect(rotulos, isNot(contains('Lucro protegido no stop')));
    });

    test('TestStopAcimaDaCompra.test_alerta_so_para_resultado_negativo', () {
      expect(alertaRisco(400.0, 1000).excede, isFalse);
      expect(alertaRisco(0.0, 0).excede, isFalse);
      expect(alertaRisco(-400.0, 1000).excede, isTrue);
    });
  }

  {
    // TestPatrimonio: o setUp só prepara repo e cfg, que os outros não usam.
    late Repositorio repo;
    late Config cfg;

    setUp(() {
      repo = Repositorio(ArmazenamentoMemoria());
      cfg = repo.lerConfig();
      final d = mesVazio('2026-10');
      d.lotes.add(lote());
      repo.salvar(d);
    });

    test('TestPatrimonio.test_caixa_mais_posicoes', () {
      definirSaldo(cfg, 10000.0, hoje: _hoje);
      var p = patrimonio(
        cfg,
        {'PETR4': 10.0},
        repo.carregarMeses(),
        hoje: _hoje,
      );
      expect(p.caixaDefinido, isTrue);
      expect(p.posicoes, _quase(1000.0));
      // a compra de 01/10 já liquidou: não entra no projetado
      expect(p.valor, _quase(11000.0));
      expect(alertaRisco(-400.48, p.valor).excede, isTrue);
      definirSaldo(cfg, 30000.0, hoje: _hoje);
      p = patrimonio(cfg, {'PETR4': 10.0}, repo.carregarMeses(), hoje: _hoje);
      expect(p.valor, _quase(31000.0));
      expect(alertaRisco(-400.48, p.valor).excede, isFalse);
    });

    test('TestPatrimonio.test_caixa_nao_definido_so_posicoes', () {
      final p = patrimonio(
        cfg,
        {'PETR4': 10.0},
        repo.carregarMeses(),
        hoje: _hoje,
      );
      expect(p.caixaDefinido, isFalse);
      expect(p.caixa, 0.0);
      expect(p.valor, _quase(1000.0));
    });

    test('TestPatrimonio.test_sem_cotacao_fica_de_fora', () {
      final p = patrimonio(cfg, {}, repo.carregarMeses(), hoje: _hoje);
      expect(p.semCotacao, ['PETR4']);
      expect(p.posicoes, 0.0);
    });

    test('TestPatrimonio.test_cadeia_de_copias_conta_uma_vez', () {
      final d = mesVazio('2026-11');
      d.lotes.add(lote(id: 'L1~2026-11', origem: 'L1'));
      // as duas ficam abertas: só a cópia (mês mais recente) conta
      repo.salvar(d);
      final p = patrimonio(
        cfg,
        {'PETR4': 10.0},
        repo.carregarMeses(),
        hoje: _hoje,
      );
      expect(p.posicoes, _quase(1000.0));
    });

    test('TestPatrimonio.test_resultado_do_mes', () {
      final d = repo.carregar('2026-10');
      d.lotes[0].vendas.add(
        Venda(id: 'v1', data: '2026-10-10', qtd: 100, preco: 12.0),
      );
      final r = resultadoMes({'2026-10': d}, '2026-10');
      expect(
        r,
        _quase(calcularVenda(d.lotes[0], d.lotes[0].vendas[0]).liquido),
      );
      expect(resultadoMes({}, '2026-10'), 0);
    });
  }

  {
    Diarias diarias({double preco = 10.0, int n = 30}) => Diarias(
      barras: barrasPlanas(n: n),
      hoje: '2026-10-28',
      preco: preco,
      fonte: 'Yahoo Finance',
    );

    test('TestTextos.test_item_e_linhas', () {
      final item = montarItem(
        lote(),
        100,
        diarias(),
        valorPatrimonio: 11000.0,
        hoje: '2026-10-28',
      );
      expect(item.erro, isNull);
      final linhas = linhasCard(item);
      final rotulos = [for (final l in linhas) l.$1];
      for (final r in [
        'Alvo sugerido',
        'Stop inicial',
        'Stop móvel',
        'Stop sugerido',
        'Risco/retorno',
        'Alerta de risco',
      ]) {
        expect(rotulos, contains(r));
      }
    });

    test('TestTextos.test_sem_dados_vira_mensagem', () {
      var item = montarItem(
        lote(),
        100,
        SemDados('Sem dados para PETR4 no Yahoo Finance.'),
      );
      expect(item.erro, contains('Sem dados'));
      expect(linhasCard(item)[0].$1, 'Sugestão');
      item = montarItem(lote(), 100, diarias(n: 5), hoje: '2026-10-28');
      expect(item.erro, contains('insuficiente'));
    });

    test('TestTextos.test_rodape', () {
      final pat = Patrimonio(
        valor: 11000.0,
        caixa: 10000.0,
        posicoes: 1000.0,
        caixaDefinido: true,
        semCotacao: [],
      );
      final linhas = linhasRodape(pat, -800.0);
      // perda do mês acima de 6% (660)
      expect(linhas.last.$3, 'danger');
      expect(linhasRodape(pat, -100.0).last.$3, isNull);
    });
  }
}
