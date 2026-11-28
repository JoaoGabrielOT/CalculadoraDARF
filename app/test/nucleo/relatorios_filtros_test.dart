import 'package:calculadoradarf/nucleo/relatorios/filtros_relatorio.dart';
import 'package:calculadoradarf/nucleo/relatorios/relatorio.dart';
import 'package:calculadoradarf/nucleo/relatorios/selecao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/fixture_relatorio.dart';

List<AtivoRelatorio> _ativos() =>
    Relatorio.deJson(fixtureRelatorioGuia()).ativos;

List<String> _tickers(List<AtivoRelatorio> l) => [for (final a in l) a.ticker];

void main() {
  group('filtrarAtivos', () {
    test('filtro vazio devolve a lista igual', () {
      final a = _ativos();
      expect(const FiltroAtivos().vazio, isTrue);
      expect(filtrarAtivos(a, const FiltroAtivos()), same(a));
      expect(const FiltroAtivos(texto: '  ').vazio, isTrue);
    });

    test('busca sem acento e sem caixa pela empresa', () {
      final r = filtrarAtivos(_ativos(), const FiltroAtivos(texto: 'itau'));
      expect(_tickers(r), ['RURA11']);
      expect(
        _tickers(filtrarAtivos(_ativos(), const FiltroAtivos(texto: 'ITAÚ'))),
        ['RURA11'],
      );
    });

    test('busca pelo ticker e pela descrição', () {
      expect(
        _tickers(filtrarAtivos(_ativos(), const FiltroAtivos(texto: 'bpac'))),
        ['BPAC11'],
      );
      expect(
        _tickers(
          filtrarAtivos(_ativos(), const FiltroAtivos(texto: 'siderurgia')),
        ),
        ['CSNA3'],
      );
    });

    test('tipo bdr traz só BDRs', () {
      final r = filtrarAtivos(_ativos(), const FiltroAtivos(tipos: {'bdr'}));
      expect(_tickers(r), ['T1TW34', 'GOGL34', 'NVDC34']);
    });

    test('leituras são OU', () {
      final r = filtrarAtivos(
        _ativos(),
        const FiltroAtivos(leituras: {Leitura.negativa, Leitura.neutra}),
      );
      expect(r.every((a) => a.leitura != Leitura.positiva), isTrue);
      expect(r.map((a) => a.leitura).toSet(), {
        Leitura.negativa,
        Leitura.neutra,
      });
    });

    test('tipo E leitura', () {
      final r = filtrarAtivos(
        _ativos(),
        const FiltroAtivos(tipos: {'bdr'}, leituras: {Leitura.negativa}),
      );
      expect(_tickers(r), ['NVDC34']);
    });

    test('com análise exclui T1TW34; sem análise inclui', () {
      final com = filtrarAtivos(
        _ativos(),
        const FiltroAtivos(comAnalise: true),
      );
      expect(_tickers(com), isNot(contains('T1TW34')));
      expect(_tickers(com), contains('CSNA3'));
      final sem = filtrarAtivos(
        _ativos(),
        const FiltroAtivos(comAnalise: false),
      );
      expect(_tickers(sem), containsAll(['T1TW34', 'GOGL34', 'RURA11']));
      expect(sem.length + com.length, _ativos().length);
    });

    test('só destaque', () {
      final r = filtrarAtivos(_ativos(), const FiltroAtivos(soDestaque: true));
      expect(r, isNotEmpty);
      expect(r.every((a) => a.leitura == Leitura.positiva), isTrue);
    });

    test('carteira {PETR4} traz só PETR4; sem carteira, nada', () {
      const f = FiltroAtivos(soCarteira: true);
      expect(_tickers(filtrarAtivos(_ativos(), f, carteira: {'PETR4'})), [
        'PETR4',
      ]);
      expect(filtrarAtivos(_ativos(), f), isEmpty);
    });
  });

  group('filtrarPorPeriodo', () {
    final itens = [
      for (final d in ['2026-11-27', '2026-11-20', '2026-11-19', '2026-08-01'])
        ResumoRelatorio(nome: 'relatorio-abertura-$d.json', data: d),
    ];

    List<String> datas(int? dias) => [
      for (final i in filtrarPorPeriodo(itens, dias, '2026-11-27')) i.data,
    ];

    test('7 dias inclui 20/11 e exclui 19/11', () {
      expect(datas(7), ['2026-11-27', '2026-11-20']);
    });

    test('30 e 90 dias; null = todos', () {
      expect(datas(30), ['2026-11-27', '2026-11-20', '2026-11-19']);
      expect(datas(90), hasLength(3));
      expect(datas(null), hasLength(4));
    });
  });
}
