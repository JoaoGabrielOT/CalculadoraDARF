import 'package:calculadoradarf/nucleo/relatorios/destaques.dart';
import 'package:calculadoradarf/nucleo/relatorios/relatorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/fixture_relatorio.dart';

Especialistas _textos(List<String> recs) => Especialistas(
  itens: [for (final r in recs) ItemEspecialista(recomendacao: r)],
);

AtivoRelatorio _ativo(
  String ticker,
  Leitura leitura, {
  String? consenso,
  Placar? placar,
}) => AtivoRelatorio(
  ticker: ticker,
  leitura: leitura,
  especialistas: Especialistas(consenso: consenso, placar: placar),
);

List<String> _tickers(List<AtivoRelatorio> l) => [for (final a in l) a.ticker];

void main() {
  group('consensoDe', () {
    test('consenso do JSON', () {
      expect(
        consensoDe(const Especialistas(consenso: 'compra')),
        Consenso.compra,
      );
      expect(
        consensoDe(const Especialistas(consenso: 'sem_dados')),
        Consenso.semDados,
      );
    });

    test('consenso desconhecido cai no placar', () {
      expect(
        consensoDe(
          const Especialistas(
            consenso: 'forte compra',
            placar: Placar(compra: 0, neutra: 2, venda: 0),
          ),
        ),
        Consenso.neutra,
      );
    });

    test('placar empatado no topo é dividido', () {
      expect(
        consensoDe(
          const Especialistas(placar: Placar(compra: 2, neutra: 2, venda: 0)),
        ),
        Consenso.dividido,
      );
    });

    test('itens com classificação', () {
      expect(
        consensoDe(
          const Especialistas(
            itens: [
              ItemEspecialista(classificacao: 'compra'),
              ItemEspecialista(classificacao: 'compra'),
              ItemEspecialista(classificacao: 'sem_classificacao'),
            ],
          ),
        ),
        Consenso.compra,
      );
    });

    test('só textos', () {
      final casos = {
        'Compra': Consenso.compra,
        'Outperform': Consenso.compra,
        'Top Picks': Consenso.compra,
        'market perform': Consenso.neutra,
        'Underweight': Consenso.venda,
        'alvos elevados; só um indica compra': Consenso.semDados,
        '37 compra / 18 manutenção / 19 venda': Consenso.compra,
      };
      casos.forEach((t, c) {
        expect(consensoDe(_textos([t])), c, reason: t);
      });
    });
  });

  test('placarDe: o do JSON, senão o contado', () {
    expect(
      placarDe(
        const Especialistas(placar: Placar(compra: 5, neutra: 0, venda: 1)),
      ),
      const Placar(compra: 5, neutra: 0, venda: 1),
    );
    expect(
      placarDe(_textos(['Compra', 'Compra', 'Neutra'])),
      const Placar(compra: 2, neutra: 1, venda: 0),
    );
  });

  test('fixture de 26/11: destaques e ordem', () {
    final ativos = Relatorio.deJson(fixtureRelatorio()).ativos;
    expect(_tickers(ativos.where(emDestaque).toList()).toSet(), {
      'BPAC11',
      'RENT3',
    });
    expect(
      _tickers(ordenarParaExibicao(ativos)).join(','),
      'RENT3,BPAC11,T1TW34,VBBR3,BBDC4,CMIG4,PRIO3,PETR4,EMBJ3,VALE3,GOGL34,'
      'MGLU3,MBRF3,TIMS3,TAEE11,CPFE3,RURA11,CSNA3,BBAS3,LREN3,WEGE3,HAPV3',
    );
  });

  test('fixture de 27/11: destaques e extremos da ordem', () {
    final ativos = Relatorio.deJson(fixtureRelatorio27()).ativos;
    expect(_tickers(ativos.where(emDestaque).toList()).toSet(), {
      'EMBJ3',
      'PRIO3',
    });
    final o = _tickers(ordenarParaExibicao(ativos));
    expect(o.take(5), ['EMBJ3', 'PRIO3', 'TAEE11', 'VBBR3', 'TIMS3']);
    expect(o.skip(o.length - 5), [
      'CSNA3',
      'BBAS3',
      'LREN3',
      'VALE3',
      'NVDC34',
    ]);
  });

  group('desempate entre destaques', () {
    AtivoRelatorio d(String t, int c, int total) => _ativo(
      t,
      Leitura.positiva,
      consenso: 'compra',
      placar: Placar(compra: c, neutra: total - c, venda: 0),
    );

    test('maior fração de compra vem antes', () {
      expect(_tickers(ordenarParaExibicao([d('A', 3, 4), d('B', 2, 2)])), [
        'B',
        'A',
      ]);
    });

    test('mesma fração: mais casas vem antes', () {
      expect(_tickers(ordenarParaExibicao([d('A', 2, 2), d('B', 4, 4)])), [
        'B',
        'A',
      ]);
    });

    test('empate total vale a posição', () {
      expect(_tickers(ordenarParaExibicao([d('A', 2, 2), d('B', 2, 2)])), [
        'A',
        'B',
      ]);
    });
  });

  group('casos extras', () {
    test('textos', () {
      final casos = {
        'Neutra (rebaixada de Compra)': Consenso.neutra,
        'Compra (preferida entre petroleiras)': Consenso.compra,
        'revisão de preço-alvo': Consenso.semDados,
        'comprador': Consenso.semDados,
        '99999999999999999999 compra / 1 manutenção / 1 venda':
            Consenso.semDados,
      };
      casos.forEach((t, c) {
        expect(consensoDe(_textos([t])), c, reason: t);
      });
    });

    test('classificação desconhecida ou sem_classificacao não vota', () {
      for (final c in ['forte', 'sem_classificacao']) {
        final e = Especialistas(
          itens: [ItemEspecialista(classificacao: c, recomendacao: 'Compra')],
        );
        expect(placarDe(e).total, 0, reason: c);
        expect(consensoDe(e), Consenso.semDados, reason: c);
      }
    });

    test('consenso desconhecido sem placar e sem itens', () {
      expect(
        consensoDe(const Especialistas(consenso: 'xyz')),
        Consenso.semDados,
      );
    });

    test('modelo: consenso e placar de tipo errado viram null', () {
      final e = Especialistas.deJson({'consenso': 5, 'placar': 'x'});
      expect((e.consenso, e.placar), (null, null));
    });

    test('placar enorme vira null', () {
      expect(
        Especialistas.deJson({
          'placar': {'compra': 1e30, 'neutra': 0, 'venda': 0},
        }).placar,
        isNull,
      );
    });
  });
}
