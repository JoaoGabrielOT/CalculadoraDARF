import 'package:calculadoradarf/nucleo/relatorios/guia.dart';
import 'package:calculadoradarf/nucleo/relatorios/relatorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/fixture_relatorio.dart';

void main() {
  test('fixture real: todos os campos, 22 ativos, termômetro somando 22', () {
    final r = Relatorio.deJson(fixtureRelatorio());
    expect((r.schemaVersion, r.tipo, r.data), (1, 'abertura', '2026-11-26'));
    expect(r.dataExtenso, 'Quinta-feira, 26 de novembro de 2026');
    expect(r.titulo, 'Relatório de Abertura de Mercado — 26/11/2026');
    expect(r.geradoEm, '2026-11-26T15:40:00-03:00');
    expect(
      (
        r.origemAtivos!.planilha,
        r.origemAtivos!.aba,
        r.origemAtivos!.quantidade,
      ),
      ('Calculadora DARF', 'Radar', 22),
    );
    expect(
      (r.avisosTopo.length, r.alertas.length, r.indicadores.length),
      (1, 1, 6),
    );
    final i = r.indicadores.first;
    expect(
      (i.nome, i.valor, i.variacao, i.direcao),
      ('Ibovespa', '174.204 pts', '+4,51%', Direcao.alta),
    );
    expect(r.resumo, startsWith('O Ibovespa fechou ontem'));
    expect(r.ativos, hasLength(22));
    expect(r.ativos.map((a) => a.posicao), List.generate(22, (i) => i));
    expect(r.termometro.total, 22);
    expect(
      (
        r.termometro.positiva,
        r.termometro.mista,
        r.termometro.neutra,
        r.termometro.negativa,
      ),
      (7, 7, 3, 5),
    );
    expect(r.termometroDiverge, isFalse);
    final csn = r.ativos.first;
    expect(
      (csn.ticker, csn.leitura, csn.tipoAtivo, csn.explicacao),
      ('CSNA3', Leitura.negativa, 'acao', null),
    );
    expect(
      (
        csn.preco!.texto,
        csn.preco!.valor,
        csn.preco!.data,
        csn.preco!.variacao,
        csn.preco!.direcao,
        csn.preco!.observacao,
      ),
      ('R\$ 3,45', 3.45, '2026-11-25', '+6,48%', Direcao.alta, 'no dia'),
    );
    final ttwo = r.ativos[1];
    expect(ttwo.explicacao, isNotNull);
    expect(
      (
        ttwo.precoExterior!.ticker,
        ttwo.precoExterior!.bolsa,
        ttwo.precoExterior!.texto,
        ttwo.precoExterior!.data,
      ),
      ('TTWO', 'Nasdaq', 'US\$ 216,54', '2026-11-18'),
    );
    expect(
      (ttwo.preco!.texto, ttwo.preco!.valor, ttwo.preco!.data),
      ('Não confirmado', null, null),
    );
    final taee = r.ativos.firstWhere((a) => a.ticker == 'TAEE11');
    final e = taee.especialistas.itens.single;
    expect(
      (e.casa, e.recomendacao, e.precoAlvo, e.data),
      ('BTG Pactual', 'venda', 'R\$ 40,00', '2026-11-11'),
    );
    expect(e.url, startsWith('https://'));
    expect(r.ativos.where((a) => a.explicacao != null).map((a) => a.ticker), [
      'T1TW34',
      'GOGL34',
      'RURA11',
    ]);
    expect(r.educacaoRisco!.titulo, 'Como limitar o risco a 1% do capital');
    expect(r.aviso, startsWith('Este relatório é educacional'));
    expect(r.fontesCenario, hasLength(4));
    expect(r.versaoNova, isFalse);
  });

  test('relatório mínimo não trava', () {
    final r = Relatorio.deJson({}, dataDoArquivo: '2026-11-26');
    expect(r.data, '2026-11-26');
    for (final l in [
      r.ativos,
      r.indicadores,
      r.avisosTopo,
      r.alertas,
      r.fontesCenario,
    ]) {
      expect(l, isEmpty);
    }
    expect(
      (r.titulo, r.resumo, r.educacaoRisco, r.aviso),
      (null, null, null, null),
    );
    expect(r.termometro.total, 0);
  });

  test('campos com tipo errado viram null', () {
    final r = Relatorio.deJson({
      'titulo': 3,
      'ativos': [
        {'ticker': 7, 'preco': 'x', 'especialistas': null, 'fontes': 'y'},
      ],
    });
    expect(r.titulo, isNull);
    final a = r.ativos.single;
    expect(a.ticker, '—');
    expect(a.preco, isNull);
    expect(a.especialistas.itens, isEmpty);
    expect(a.fontes, isEmpty);
  });

  test('enum desconhecido vira neutra', () {
    expect(leituraDe('otima'), Leitura.neutra);
    expect(leituraDe(null), Leitura.neutra);
    expect(direcaoDe('subindo'), Direcao.neutra);
    expect(direcaoDe(null), Direcao.neutra);
    final r = Relatorio.deJson({
      'indicadores': [
        {'nome': 'X', 'valor': '1', 'direcao': 'subindo'},
      ],
      'ativos': [
        {'ticker': 'A', 'leitura': 'otima'},
      ],
    });
    expect(r.indicadores.single.direcao, Direcao.neutra);
    expect(r.ativos.single.leitura, Leitura.neutra);
  });

  test('fontes: nome ausente usa a url; sem url é descartada', () {
    final r = Relatorio.deJson({
      'fontesCenario': [
        {'url': 'https://a'},
        {'nome': 'só nome'},
        {'nome': 'B', 'url': 'https://b'},
        'lixo',
      ],
    });
    expect(r.fontesCenario.map((f) => (f.nome, f.url)), [
      ('https://a', 'https://a'),
      ('B', 'https://b'),
    ]);
  });

  test('campos extras são ignorados', () {
    final base = Relatorio.deJson(fixtureRelatorio());
    final f = fixtureRelatorio();
    f['novo'] = {'a': 1};
    ((f['ativos'] as List).first as Map)['novo'] = {'a': 1};
    final r = Relatorio.deJson(f);
    expect(r.ativos.map((a) => a.ticker), base.ativos.map((a) => a.ticker));
    expect(r.termometro.total, base.termometro.total);
    expect(r.ativos.first.preco!.texto, base.ativos.first.preco!.texto);
  });

  test('schemaVersion 2 renderiza com aviso', () {
    final f = fixtureRelatorio()..['schemaVersion'] = 2;
    final r = Relatorio.deJson(f);
    expect(r.versaoNova, isTrue);
    expect(r.ativos.length, 22);
  });

  test('ativos em ordem de posição', () {
    final r = Relatorio.deJson({
      'ativos': [
        {'ticker': 'C', 'posicao': 2},
        {'ticker': 'A', 'posicao': 0},
        {'ticker': 'N', 'posicao': null},
        {'ticker': 'B', 'posicao': 1},
        {'ticker': 'M'},
      ],
    });
    expect(r.ativos.map((a) => a.ticker), ['A', 'B', 'C', 'N', 'M']);
  });

  test('0, 1 e 60 ativos', () {
    for (final n in [0, 1, 60]) {
      final r = Relatorio.deJson(fixtureComAtivos(n));
      expect(r.ativos.length, n);
      expect(r.termometro.total, n);
    }
  });

  test('termômetro divergente: vale o do JSON', () {
    final f = fixtureRelatorio()
      ..['termometro'] = {
        'positiva': 1,
        'mista': 0,
        'neutra': 0,
        'negativa': 0,
      };
    final r = Relatorio.deJson(f);
    expect(r.termometro.total, 1);
    expect(r.contagemAtivos.total, 22);
    expect(r.termometroDoJson, isTrue);
    expect(r.termometroDiverge, isTrue);
  });

  test('termômetro ausente: contado pelos ativos', () {
    final f = fixtureRelatorio()..remove('termometro');
    final r = Relatorio.deJson(f);
    expect(
      (
        r.termometro.positiva,
        r.termometro.mista,
        r.termometro.neutra,
        r.termometro.negativa,
      ),
      (7, 7, 3, 5),
    );
    expect(r.termometroDoJson, isFalse);
    expect(r.termometroDiverge, isFalse);
  });

  test('data do JSON inválida usa a do arquivo', () {
    expect(
      Relatorio.deJson({
        'data': '26/11/2026',
      }, dataDoArquivo: '2026-11-26').data,
      '2026-11-26',
    );
    expect(
      Relatorio.deJson({
        'data': '2026-02-30',
      }, dataDoArquivo: '2026-11-26').data,
      '2026-11-26',
    );
    expect(
      Relatorio.deJson({
        'data': '2026-11-25',
      }, dataDoArquivo: '2026-11-26').data,
      '2026-11-25',
    );
  });

  test('JSON que não é objeto lança FormatException', () {
    expect(() => Relatorio.deJson([1, 2]), throwsFormatException);
    expect(() => Relatorio.deJson(null), throwsFormatException);
  });

  test('número infinito não trava', () {
    final r = Relatorio.deJson({
      'schemaVersion': double.infinity,
      'ativos': [
        {
          'posicao': double.infinity,
          'ticker': 'A',
          'preco': {'valor': double.infinity},
        },
      ],
      'origemAtivos': {'quantidade': double.infinity},
    });
    expect(r.schemaVersion, 1);
    expect(r.ativos.single.posicao, isNull);
    expect(r.origemAtivos!.quantidade, isNull);
    expect(r.ativos.single.preco!.valor, isNull);
    expect(Relatorio.deJson({'schemaVersion': double.nan}).schemaVersion, 1);
  });

  test('enum ignora maiúsculas e espaços', () {
    expect(leituraDe(' Positiva '), Leitura.positiva);
    expect(direcaoDe('QUEDA'), Direcao.queda);
  });

  test(
    'termômetro: negativos viram 0; sem chaves numéricas conta pelos ativos',
    () {
      final neg = Relatorio.deJson({
        'termometro': {'positiva': -3, 'mista': 2},
      });
      expect((neg.termometro.positiva, neg.termometro.mista), (0, 2));
      for (final t in [
        <String, Object?>{},
        {'positiva': 'x', 'outra': 1},
      ]) {
        final r = Relatorio.deJson({
          'termometro': t,
          'ativos': [
            {'ticker': 'A', 'leitura': 'mista'},
          ],
        });
        expect(r.termometroDoJson, isFalse);
        expect(r.termometro.mista, 1);
        expect(r.termometroDiverge, isFalse);
      }
    },
  );

  test('tipo errado dentro dos sub-objetos', () {
    final r = Relatorio.deJson({
      'termometro': 'x',
      'indicadores': [null, 3],
      'ativos': [
        {
          'ticker': 'A',
          'preco': {'valor': '3,45', 'texto': 'R\$ 3,45'},
        },
      ],
    });
    expect(r.indicadores, isEmpty);
    expect(r.termometroDoJson, isFalse);
    expect(r.ativos.single.preco!.valor, isNull);
    expect(r.ativos.single.preco!.texto, 'R\$ 3,45');
  });

  group('consenso, placar, classificação e potencial', () {
    AtivoRelatorio ativo(Relatorio r, String t) =>
        r.ativos.firstWhere((a) => a.ticker == t);

    test('fixture de 27/11', () {
      final r = Relatorio.deJson(fixtureRelatorio27());
      final e = ativo(r, 'BPAC11').especialistas;
      expect(e.consenso, 'compra');
      expect(e.placar, const Placar(compra: 2, neutra: 1, venda: 0));
      expect(e.placar!.total, 3);
      expect(e.itens[0].classificacao, 'compra');
      expect(
        ativo(r, 'LREN3').especialistas.itens[0].potencial,
        '+39,7% até o alvo, com o preço de 26/11',
      );
    });

    test('placar inválido vira null', () {
      for (final p in [
        {'compra': 1.5, 'neutra': 0, 'venda': 0},
        {'compra': -1, 'neutra': 0, 'venda': 0},
        {'compra': 1},
      ]) {
        expect(Especialistas.deJson({'placar': p}).placar, isNull);
      }
    });

    test('consenso é normalizado; fixture de 26/11 não tem os campos', () {
      expect(
        Especialistas.deJson({'consenso': '  Compra '}).consenso,
        'compra',
      );
      final r = Relatorio.deJson(fixtureRelatorio());
      final e = ativo(r, 'BPAC11').especialistas;
      expect((e.consenso, e.placar), (null, null));
    });
  });

  group('guia dos especialistas', () {
    AtivoRelatorio ativo(Relatorio r, String t) =>
        r.ativos.firstWhere((a) => a.ticker == t);

    test('fixture guia: campos de especialistas e itens', () {
      final r = Relatorio.deJson(fixtureRelatorioGuia());
      final e = ativo(r, 'BPAC11').especialistas;
      expect(e.precoReferencia, 'R\$ 56,90 em 26/11');
      expect(e.alvoMedio, 'R\$ 67,67');
      expect(e.alvoMin, 'R\$ 60,00');
      expect(e.alvoMax, 'R\$ 72,00');
      expect(e.potencialMedio, '+18,9%');
      expect(e.guiaLeigo, startsWith('2 de 3 casas indicam COMPRAR'));
      expect(e.itens[0].motivo, startsWith('Mantém a visão positiva'));
      expect(e.itens[0].fraseGuia, startsWith('O Safra indica COMPRAR'));
      final t = ativo(r, 'TAEE11').especialistas.itens[1];
      expect(t.precoAlvoValor, 43.5);
      expect(t.moedaAlvo, 'BRL');
      expect(t.prazoAlvo, 'fim de 2027');
    });

    test('precoAlvoValor em texto vira null', () {
      expect(
        ItemEspecialista.deJson({'precoAlvoValor': '43,5'})!.precoAlvoValor,
        isNull,
      );
    });

    test('fixture de 26/11 não tem os campos; temGuia', () {
      final r = Relatorio.deJson(fixtureRelatorio());
      final e = ativo(r, 'BPAC11').especialistas;
      expect([
        e.precoReferencia,
        e.alvoMedio,
        e.alvoMin,
        e.alvoMax,
        e.potencialMedio,
        e.guiaLeigo,
        e.itens[0].precoAlvoValor,
        e.itens[0].moedaAlvo,
        e.itens[0].prazoAlvo,
        e.itens[0].motivo,
        e.itens[0].fraseGuia,
      ], everyElement(isNull));
      expect(temGuia(r), isFalse);
      expect(temGuia(Relatorio.deJson(fixtureRelatorio27())), isFalse);
      expect(temGuia(Relatorio.deJson(fixtureRelatorioGuia())), isTrue);
    });

    test('temGuia por cada campo', () {
      Relatorio com(Map<String, Object?> esp) => Relatorio.deJson({
        'schemaVersion': 1,
        'ativos': [
          {'ticker': 'X', 'especialistas': esp},
        ],
      });
      expect(temGuia(com({'guiaLeigo': 'a'})), isTrue);
      expect(temGuia(com({'alvoMedio': 'R\$ 1'})), isTrue);
      expect(
        temGuia(
          com({
            'itens': [
              {'fraseGuia': 'f'},
            ],
          }),
        ),
        isTrue,
      );
      expect(
        temGuia(
          com({
            'itens': [
              {'motivo': 'm'},
            ],
          }),
        ),
        isTrue,
      );
      expect(temGuia(com({'resumo': 'r'})), isFalse);
    });

    test('fraseSemMotivo', () {
      expect(
        fraseSemMotivo('O X indica MANTER. Motivo: acha caro.', 'Acha caro.'),
        'O X indica MANTER.',
      );
      expect(
        fraseSemMotivo('O X indica MANTER. Motivo: acha caro.', ' ACHA CARO '),
        'O X indica MANTER.',
      );
      expect(
        fraseSemMotivo('O X indica MANTER. Motivo: acha caro.', 'Outro.'),
        'O X indica MANTER. Motivo: acha caro.',
      );
      expect(fraseSemMotivo('O X indica MANTER.', null), 'O X indica MANTER.');
    });
  });
}
