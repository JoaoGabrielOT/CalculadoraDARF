import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/posicoes.dart';
import 'package:calculadoradarf/nucleo/sugestoes/cenario.dart';
import 'package:calculadoradarf/nucleo/tick.dart';
import 'package:flutter_test/flutter_test.dart';

const _hoje = '2026-11-09'; // segunda-feira, dia útil
const _avisoQtd =
    'Quantidade grande frente ao volume médio: a saída pode mover o preço';
const _avisoSpread =
    'Spread: indisponível (o Yahoo não fornece livro de ofertas)';

BarraDiaria _b(
  int i, {
  double alta = 10.5,
  double baixa = 9.5,
  double fech = 10.0,
  double? volume = 1000,
}) => BarraDiaria(
  data: somarDias('2026-10-01', i),
  alta: alta,
  baixa: baixa,
  fech: fech,
  volume: volume,
);

/// [n] barras diárias iguais, de 2026-10-01 em diante; [alteracoes] troca a
/// barra do índice dado.
List<BarraDiaria> barras(
  int n, {
  double alta = 10.5,
  double baixa = 9.5,
  double fech = 10.0,
  double? volume = 1000,
  Map<int, BarraDiaria>? alteracoes,
}) => [
  for (var i = 0; i < n; i++)
    alteracoes?[i] ??
        _b(i, alta: alta, baixa: baixa, fech: fech, volume: volume),
];

DataHora _hora(String iso) => DataHora.parse(iso);

CotacaoInfo _cot(double preco) => CotacaoInfo(
  preco: preco,
  hora: _hora('2026-11-09T10:55:00-03:00'),
  fonte: 'Yahoo',
  atual: true,
);

PosicaoAtivo _posicao(int qtd, double custo) => PosicaoAtivo(
  ticker: 'PETR4',
  tipo: 'Ação',
  qtd: qtd,
  custoGerencial: custo,
  compras: const [],
);

void main() {
  group('swing', () {
    test('sem oportunidade por R/R', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.horizonte, Horizonte.swing);
      expect(c.stop, 8.00);
      expect(c.alvo, 10.50);
      expect(c.faixaMin, 10.01);
      expect(c.faixaMax, 10.50);
      expect(c.rr, closeTo(0.25, 1e-9));
      expect(c.oportunidade, isFalse);
      expect(c.motivo, 'relação risco/retorno abaixo de 1,5');
      expect(c.rotuloAlvo, 'resistência de 20 pregões');
      expect(c.rotuloAncora, 'último fechamento');
      expect(c.ancora, 10.0);
    });

    test('alvo ancorado na cotação, não na compra', () {
      final a = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
        pontoEquilibrio: 5.93,
      );
      final b = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
        pontoEquilibrio: 4.00,
      );
      expect(a.alvo, b.alvo);
      expect(a.stop, b.stop);
      expect(a.alvo, isNot(5.93 + 4 * 1.0));
      expect(a.ancora, 10.0);
    });

    test('projeção pela volatilidade acima da máxima', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        cotacao: _cot(11.0),
        qtd: 100,
      );
      expect(c.ancora, 11.0);
      expect(c.rotuloAncora, 'cotação atual');
      expect(c.alvo, pisoTick('PETR4', 11.0 + 2 * 1.0));
      expect(
        c.rotuloAlvo,
        'projeção pela volatilidade (sem resistência recente acima)',
      );
    });

    test('cotação desatualizada não vira âncora', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        cotacao: CotacaoInfo(
          preco: 11.0,
          hora: _hora('2026-11-05T17:00:00-03:00'),
          fonte: 'Yahoo',
          atual: false,
        ),
        qtd: 100,
      );
      expect(c.ancora, 10.0);
      expect(c.rotuloAncora, 'último fechamento');
    });

    test('chandelier acima da âncora não vira stop', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25, alteracoes: {20: _b(20, alta: 30.0)}),
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.stop, isNotNull);
      expect(c.stop! < c.ancora!, isTrue);
      expect(c.risco! > 0, isTrue);
      expect(c.rr, isNotNull);
    });

    test('dados insuficientes', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(20),
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.oportunidade, isFalse);
      expect(c.motivo, 'dados insuficientes');
      expect(c.alvo, isNull);
      expect(c.stop, isNull);
    });

    test('a barra de hoje não conta', () {
      final lista = [
        ...barras(20),
        BarraDiaria(data: _hoje, alta: 10.5, baixa: 9.5, fech: 10.0, volume: 1),
      ];
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: lista,
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.motivo, 'dados insuficientes');
    });

    test('alvo abaixo do ponto de equilíbrio', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25, alteracoes: {24: _b(24, alta: 13.0)}),
        hoje: _hoje,
        qtd: 100,
        pontoEquilibrio: 20.0,
      );
      expect(c.rr! >= 1.5, isTrue);
      expect(c.oportunidade, isFalse);
      expect(c.motivo, 'alvo abaixo do ponto de equilíbrio');
    });

    test('oportunidade quando R/R e equilíbrio passam', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25, alteracoes: {24: _b(24, alta: 13.0)}),
        hoje: _hoje,
        qtd: 100,
        pontoEquilibrio: 9.0,
      );
      expect(c.oportunidade, isTrue);
      expect(c.motivo, isNull);
    });
  });

  group('day trade', () {
    final anterior = [...barras(24), _b(24, fech: 10.2)];

    test('pelos pivôs do pregão anterior', () {
      final c = cenarioDayTrade(
        ticker: 'PETR4',
        barras: anterior,
        hoje: _hoje,
        cotacao: _cot(10.0),
        pregaoAberto: true,
        qtd: 100,
      );
      expect(c.horizonte, Horizonte.dayTrade);
      expect(c.stop, 9.63);
      expect(c.alvo, 10.63);
      expect(c.rr, closeTo(0.63 / 0.37, 1e-9));
      expect(c.oportunidade, isTrue);
    });

    test('sem cotação atual não simula', () {
      final c = cenarioDayTrade(
        ticker: 'PETR4',
        barras: anterior,
        hoje: _hoje,
        cotacao: null,
        pregaoAberto: true,
        qtd: 100,
      );
      expect(c.oportunidade, isFalse);
      expect(c.motivo, 'Análise intradiária indisponível: sem cotação atual');
      expect(c.alvo, isNull);
      expect(c.stop, isNull);
    });

    test('pregão fechado não simula', () {
      final c = cenarioDayTrade(
        ticker: 'PETR4',
        barras: anterior,
        hoje: _hoje,
        cotacao: _cot(10.0),
        pregaoAberto: false,
        qtd: 100,
      );
      expect(c.motivo, 'Análise intradiária indisponível: sem cotação atual');
      expect(c.alvo, isNull);
    });
  });

  group('liquidez', () {
    test('VFM e aviso de quantidade', () {
      // VFM = 10 * 1000 = 10.000; limite de 5% = 500; 100 * 10 = 1.000.
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.vfm, closeTo(10000, 1e-9));
      expect(c.avisos, contains(_avisoQtd));
      expect(c.avisos, contains(_avisoSpread));
    });

    test('quantidade pequena não gera aviso de quantidade', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 10,
      );
      expect(c.avisos, isNot(contains(_avisoQtd)));
      expect(c.avisos, contains(_avisoSpread));
    });

    test('barra sem volume: liquidez indisponível', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25, alteracoes: {22: _b(22, volume: null)}),
        hoje: _hoje,
        qtd: 100,
      );
      expect(c.vfm, isNull);
      expect(c.avisos, contains('Liquidez indisponível'));
      expect(c.avisos, isNot(contains(_avisoQtd)));
      expect(c.avisos, contains(_avisoSpread));
    });
  });

  group('meta financeira', () {
    const avisoMeta = 'Meta acima do cenário de mercado para o horizonte';

    test('fórmula com tick para cima', () {
      expect(metaFinanceira('PETR4', 100, 10.00, 100), 11.01);
    });

    test('acima do cenário vira aviso e não muda a oportunidade', () {
      final sem = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
      );
      final com = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
        meta: 11.01,
      );
      expect(com.avisos, contains(avisoMeta));
      expect(sem.avisos, isNot(contains(avisoMeta)));
      expect(com.oportunidade, sem.oportunidade);
    });

    test('meta abaixo do alvo não gera aviso', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
        meta: 10.20,
      );
      expect(c.avisos, isNot(contains(avisoMeta)));
    });
  });

  group('consolidado', () {
    test('preço médio ponderado por quantidade', () {
      // 100 a 10,00 e 300 a 6,00: 2.800 / 400 = 7,00 (a média simples dá 8).
      final p = _posicao(400, 100 * 10.0 + 300 * 6.0);
      expect(p.precoMedio, 7.00);
    });

    test('cenários 25%, 50%, 100% e quantidade digitada', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
      );
      final r = consolidar(
        _posicao(100, 700.0),
        c,
        meta: 11.01,
        qtdDigitada: 30,
      );
      expect(r.ticker, 'PETR4');
      expect(r.qtd, 100);
      expect(r.custo, 700.0);
      expect(r.precoMedio, 7.0);
      final noAlvo = [
        for (final s in r.cenarios)
          if (s.preco == 10.5) s,
      ];
      expect(noAlvo.map((s) => s.qtd), [25, 50, 100, 30]);
      // 100 a 10,50: venda 1.050, taxas (700 + 1.050) * 0,0003 = 0,525 ->
      // líquido 349,475; IR de 15% sobre o ganho.
      final cem = noAlvo.firstWhere((s) => s.qtd == 100);
      expect(cem.resultado, closeTo(349.475 - 349.475 * 0.15, 1e-9));
      expect(cem.resultadoPct, closeTo(cem.resultado / 700.0 * 100, 1e-9));
      expect(r.cenarios.any((s) => s.preco == 8.0), isTrue);
      expect(r.cenarios.any((s) => s.preco == 11.01), isTrue);
    });

    test('perda no stop não paga imposto', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 100,
      );
      final r = consolidar(_posicao(100, 1000.0), c);
      final stop = r.cenarios.firstWhere((s) => s.preco == 8.0 && s.qtd == 100);
      // venda 800, taxas (1.000 + 800) * 0,0003 = 0,54: -200,54, sem IR.
      expect(stop.resultado, closeTo(-200.54, 1e-9));
    });

    test('sem cenário de mercado só a meta aparece', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(20),
        hoje: _hoje,
        qtd: 100,
      );
      final r = consolidar(_posicao(100, 700.0), c, meta: 11.01);
      expect(r.cenarios.every((s) => s.preco == 11.01), isTrue);
      expect(r.cenarios.length, 3);
    });

    test('posição zerada: preço médio e equilíbrio indisponíveis', () {
      final c = cenarioSwing(
        ticker: 'PETR4',
        barras: barras(25),
        hoje: _hoje,
        qtd: 0,
      );
      final r = consolidar(_posicao(0, 0.0), c);
      expect(r.precoMedio, isNull);
      expect(r.pontoEquilibrio, isNull);
      expect(r.cenarios, isEmpty);
    });
  });

  group('cotação atual', () {
    final agora = _hora('2026-11-09T11:00:00-03:00'); // segunda, em pregão

    CotacaoInfo info(String hora, DataHora ag) =>
        cotacaoInfo(10.0, _hora(hora), 'Yahoo', ag);

    test('5 min durante o pregão é atual', () {
      final i = info('2026-11-09T10:55:00-03:00', agora);
      expect(i.atual, isTrue);
      expect(i.preco, 10.0);
      expect(i.fonte, 'Yahoo');
    });

    test('25 min durante o pregão não é atual', () {
      expect(info('2026-11-09T10:35:00-03:00', agora).atual, isFalse);
    });

    test('dois pregões atrás não é atual', () {
      expect(info('2026-11-05T17:00:00-03:00', agora).atual, isFalse);
    });

    test('fora do pregão vale a do último pregão', () {
      final noite = _hora('2026-11-09T20:00:00-03:00');
      expect(info('2026-11-09T17:50:00-03:00', noite).atual, isTrue);
      final domingo = _hora('2026-11-08T12:00:00-03:00');
      expect(info('2026-11-06T17:50:00-03:00', domingo).atual, isTrue);
      expect(info('2026-11-05T17:50:00-03:00', domingo).atual, isFalse);
    });

    test('pregaoAbertoEm', () {
      expect(pregaoAbertoEm(agora), isTrue);
      expect(pregaoAbertoEm(_hora('2026-11-09T09:30:00-03:00')), isFalse);
      expect(pregaoAbertoEm(_hora('2026-11-09T18:30:00-03:00')), isFalse);
      expect(pregaoAbertoEm(_hora('2026-11-08T12:00:00-03:00')), isFalse);
    });
  });

  group('barras desatualizadas', () {
    test('última barra anterior ao último pregão fechado', () {
      // hoje é segunda 09/11: o último pregão fechado esperado é sexta 06/11.
      BarraDiaria dia(String d) =>
          BarraDiaria(data: d, alta: 1, baixa: 1, fech: 1);
      expect(barrasDesatualizadas([dia('2026-11-06')], _hoje), isFalse);
      expect(barrasDesatualizadas([dia('2026-11-05')], _hoje), isTrue);
      expect(barrasDesatualizadas(const [], _hoje), isTrue);
    });
  });
}
