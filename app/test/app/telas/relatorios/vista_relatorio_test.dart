import 'package:calculadoradarf/app/componentes/cartao.dart' hide Selo;
import 'package:calculadoradarf/app/componentes/controles.dart' show Selo;
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/app/telas/relatorios/cartao_ativo.dart';
import 'package:calculadoradarf/app/telas/relatorios/paleta_relatorio.dart';
import 'package:calculadoradarf/app/telas/relatorios/vista_relatorio.dart';
import 'package:calculadoradarf/nucleo/relatorios/destaques.dart';
import 'package:calculadoradarf/nucleo/relatorios/relatorio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../nucleo/apoio/fixture_relatorio.dart';
import '../../apoio/montar_componente.dart';

const _pc = Size(1366, 900);

/// Janela alta: os cartões preguiçosos ficam todos construídos.
const _pcAlto = Size(1366, 20000);
const _celular = Size(360, 800);
const _vazio = <String, Object?>{};

final _links = <Uri>[];

Widget _vista(Relatorio r) =>
    VistaRelatorio(relatorio: r, aoAbrirLink: _links.add);

Relatorio _fixture() => Relatorio.deJson(fixtureRelatorio());

Color? _fundo(WidgetTester t, Finder f) =>
    (t.widget<DecoratedBox>(f).decoration as BoxDecoration).color;

/// Cor do `Selo` chapado de [f] (o próprio ou um descendente).
Color _corSeloLeitura(WidgetTester t, Finder f) {
  final selo = find.descendant(
    of: f,
    matching: find.byType(Selo),
    matchRoot: true,
  );
  expect(selo, findsOneWidget);
  return t.widget<Selo>(selo).cor;
}

Finder _vertical() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

void main() {
  setUp(_links.clear);

  group('funções', () {
    test('rótulo de cada leitura', () {
      expect(Leitura.values.map(rotuloLeitura), [
        'Positiva',
        'Mista',
        'Neutra',
        'Negativa',
      ]);
    });

    test('texto do termômetro, com singular', () {
      expect(
        textoTermometro(
          const Termometro(positiva: 7, mista: 7, neutra: 3, negativa: 5),
        ),
        '7 positivas · 7 mistas · 3 neutras · 5 negativas',
      );
      expect(
        textoTermometro(
          const Termometro(positiva: 1, mista: 1, neutra: 1, negativa: 1),
        ),
        '1 positiva · 1 mista · 1 neutra · 1 negativa',
      );
    });

    test('link seguro: só http e https com host', () {
      expect(linkSeguro('https://a.com/x'), Uri.parse('https://a.com/x'));
      expect(linkSeguro('HTTP://a.com'), isNotNull);
      for (final u in [
        null,
        '',
        '   ',
        'javascript:alert(1)',
        'file:///c:/x',
        'mailto:a@b.com',
        'https://',
        'a.com/x',
      ]) {
        expect(linkSeguro(u), isNull, reason: '$u');
      }
    });

    test('cores: leitura e direção pela paleta', () {
      expect(PaletaRelatorio.coresLeitura(Leitura.positiva), (
        const Color(0xFF1B7F3B),
        const Color(0xFFE6F4EA),
      ));
      expect(PaletaRelatorio.coresLeitura(Leitura.negativa), (
        const Color(0xFFB3261E),
        const Color(0xFFFCE8E6),
      ));
      expect(PaletaRelatorio.coresLeitura(Leitura.mista), (
        const Color(0xFFB06000),
        const Color(0xFFFEF7E0),
      ));
      expect(PaletaRelatorio.coresLeitura(Leitura.neutra), (
        const Color(0xFF5F6368),
        const Color(0xFFF1F3F4),
      ));
      expect(
        PaletaRelatorio.coresDirecao(Direcao.alta),
        PaletaRelatorio.coresLeitura(Leitura.positiva),
      );
      expect(
        PaletaRelatorio.coresDirecao(Direcao.queda),
        PaletaRelatorio.coresLeitura(Leitura.negativa),
      );
      expect(
        PaletaRelatorio.coresDirecao(Direcao.neutra),
        PaletaRelatorio.coresLeitura(Leitura.neutra),
      );
    });
  });

  testWidgets('seções na ordem a–k', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    double y(String l) => t.getTopLeft(find.byKey(Key('secao-$l'))).dy;
    final letras = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'];
    for (var i = 1; i < letras.length; i++) {
      expect(y(letras[i]), greaterThan(y(letras[i - 1])), reason: letras[i]);
    }
  });

  testWidgets('cabeçalho, avisos, legenda e textos fixos', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    expect(find.text('Quinta-feira, 26 de novembro de 2026'), findsOneWidget);
    expect(find.text('22 ativos do Radar'), findsOneWidget);
    expect(find.textContaining('Edição gerada às 15h40'), findsOneWidget);
    expect(find.textContaining('Bolsas dos EUA fechadas hoje'), findsOneWidget);
    for (final s in [
      'Positiva: notícias e números do dia favoráveis à empresa.',
      'Mista: sinais favoráveis e desfavoráveis ao mesmo tempo.',
      'Neutra: nada relevante para o preço no dia.',
      'Negativa: notícias e números do dia desfavoráveis à empresa.',
      'A leitura resume as notícias e os dados do dia. Não é previsão de '
          'preço nem recomendação de compra ou venda.',
      'Termômetro',
      'Ativo',
      'Último preço',
      'Leitura',
      'Fontes do cenário',
    ]) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    expect(find.textContaining('Como limitar o risco'), findsOneWidget);
    expect(find.textContaining('Este relatório é educacional'), findsOneWidget);
    expect(find.byKey(const Key('versao-nova')), findsNothing);
  });

  testWidgets('cabeçalho: 1 ativo, lista reserva e sem quantidade', (t) async {
    Future<void> com(Object? origem) async {
      await montarComponente(
        t,
        _vista(
          Relatorio.deJson({...fixtureRelatorio(), 'origemAtivos': origem}),
        ),
        tamanho: _pc,
      );
    }

    await com({'aba': 'Radar', 'quantidade': 1});
    expect(find.text('1 ativo do Radar'), findsOneWidget);
    await com({'aba': 'reserva', 'quantidade': 22});
    expect(find.text('22 ativos da lista reserva'), findsOneWidget);
    await com({'aba': 'Radar'});
    expect(find.textContaining('do Radar'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'termômetro: positivas, mistas, neutras, negativas e a contagem do JSON',
    (t) async {
      final r = _fixture();
      await montarComponente(t, _vista(r), tamanho: _pcAlto);
      final selos = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('selo-termometro-'),
      );
      expect(selos, findsNWidgets(22));
      final posicoes =
          [
            for (final e in selos.evaluate())
              (
                (e.widget.key! as ValueKey<String>).value.substring(16),
                t.getTopLeft(find.byKey(e.widget.key!)),
              ),
          ]..sort((a, b) {
            final dy = a.$2.dy.compareTo(b.$2.dy);
            return dy != 0 ? dy : a.$2.dx.compareTo(b.$2.dx);
          });
      final ordem = [for (final p in posicoes) p.$1];
      final exibicao = ordenarParaExibicao(r.ativos);
      expect(ordem, [for (final a in exibicao) a.ticker]);
      // Grupos fixos da fixture: 7 positivas, 7 mistas, 3 neutras, 5 negativas.
      final leitura = {for (final a in r.ativos) a.ticker: a.leitura};
      for (final (ini, fim, l) in [
        (0, 7, Leitura.positiva),
        (7, 14, Leitura.mista),
        (14, 17, Leitura.neutra),
        (17, 22, Leitura.negativa),
      ]) {
        expect(
          ordem.sublist(ini, fim).map((tk) => leitura[tk]),
          everyElement(l),
          reason: l.name,
        );
      }
      expect(ordem.first, 'RENT3');
      expect(ordem.last, 'HAPV3');
      expect(
        find.text('7 positivas · 7 mistas · 3 neutras · 5 negativas'),
        findsOneWidget,
      );
    },
  );

  testWidgets('termômetro divergente mostra o texto do JSON', (t) async {
    final json = fixtureRelatorio()
      ..['termometro'] = {
        'positiva': 1,
        'mista': 0,
        'neutra': 0,
        'negativa': 0,
      };
    await montarComponente(t, _vista(Relatorio.deJson(json)), tamanho: _pcAlto);
    expect(
      find.text('1 positiva · 0 mistas · 0 neutras · 0 negativas'),
      findsOneWidget,
    );
  });

  testWidgets('tabela: preço com data e especialistas', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    final tabela = find.byKey(const Key('secao-g'));
    expect(
      find.descendant(of: tabela, matching: find.text('R\$ 3,45 · 25/11/2026')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabela, matching: find.text('Não confirmado')),
      findsWidgets,
    );
    expect(
      find.descendant(of: tabela, matching: find.text('Especialistas')),
      findsOneWidget,
    );
  });

  testWidgets('cartões na ordem de leitura, com explicação só nos 3', (
    t,
  ) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    expect(
      t.getTopLeft(find.byKey(const Key('cartao-T1TW34'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('cartao-CSNA3'))).dy),
    );
    for (final tk in ['T1TW34', 'GOGL34', 'RURA11']) {
      expect(find.byKey(Key('explicacao-$tk')), findsOneWidget, reason: tk);
    }
    expect(find.byKey(const Key('explicacao-CSNA3')), findsNothing);
    final explicacoes = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('explicacao-'),
    );
    expect(explicacoes, findsNWidgets(3));
    expect(
      _fundo(t, find.byKey(const Key('explicacao-T1TW34'))),
      const Color(0xFFE8F0FE),
    );
  });

  testWidgets('cartão: rótulos, especialista, preço no exterior', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    final taee = find.byKey(const Key('cartao-TAEE11'));
    for (final s in [
      'Quem é dono',
      'Preço',
      'Notícias',
      'Especialistas',
      'Riscos',
      'Fontes',
    ]) {
      expect(
        find.descendant(of: taee, matching: find.text(s)),
        findsOneWidget,
        reason: s,
      );
    }
    expect(
      find.descendant(
        of: taee,
        matching: find.text(
          'BTG Pactual · venda · alvo R\$ 40,00 · 11/11/2026',
        ),
      ),
      findsOneWidget,
    );
    // Data AAAA-MM vira MM/AAAA; partes ausentes somem.
    expect(
      find.descendant(
        of: find.byKey(const Key('cartao-VBBR3')),
        matching: find.text('Ativa Investimentos · neutra · 11/2026'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('cartao-T1TW34')),
        matching: find.text('TTWO (Nasdaq): US\$ 216,54 · 18/11/2026'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('direção: ▲ na alta, ▼ na queda, neutra sem seta', (t) async {
    final json = fixtureRelatorio();
    (json['indicadores'] as List).add({
      'nome': 'Estável',
      'valor': '1',
      'variacao': '0,00%',
      'direcao': 'neutra',
    });
    await montarComponente(t, _vista(Relatorio.deJson(json)), tamanho: _pcAlto);
    final d = find.byKey(const Key('secao-d'));
    expect(
      find.descendant(of: d, matching: find.text('▲ +4,51%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: d, matching: find.text('▼ -1,78%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: d, matching: find.text('0,00%')),
      findsOneWidget,
    );
    final alta = find.ancestor(
      of: find.text('▲ +4,51%'),
      matching: find.byType(Selo),
    );
    expect(t.widget<Selo>(alta.first).cor, PaletaRelatorio.positivaTexto);
  });

  testWidgets('selo Positiva com a cor da paleta', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    final selo = find.ancestor(
      of: find.text('Positiva').first,
      matching: find.byType(Selo),
    );
    expect(t.widget<Selo>(selo.first).cor, PaletaRelatorio.positivaTexto);
  });

  for (final tema in [
    TemaVisual.terminal,
    TemaVisual.claro,
    TemaVisual.moderno,
  ]) {
    testWidgets('tema ${tema.chave}: selos mantêm a paleta', (t) async {
      await montarComponente(
        t,
        _vista(_fixture()),
        tamanho: _pcAlto,
        tema: tema,
      );
      // claro: o texto escuro da paleta; escuros: as cores do tema
      final cores = CoresApp.de(t.element(find.byType(VistaRelatorio)));
      final claro = tema == TemaVisual.claro;
      expect(
        _corSeloLeitura(t, find.byKey(const Key('selo-termometro-T1TW34'))),
        claro ? PaletaRelatorio.positivaTexto : cores.alta,
      );
      expect(
        _corSeloLeitura(t, find.byKey(const Key('selo-termometro-HAPV3'))),
        claro ? PaletaRelatorio.negativaTexto : cores.queda,
      );
    });
  }

  testWidgets('tocar uma fonte do cenário abre a URL', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pc);
    final fonte = find.descendant(
      of: find.byKey(const Key('secao-k')),
      matching: find.text('InfoMoney'),
    );
    await t.scrollUntilVisible(fonte, 600, scrollable: _vertical());
    await t.ensureVisible(fonte);
    await t.pumpAndSettle();
    await t.tap(fonte);
    expect(_links, [
      Uri.parse(
        'https://www.infomoney.com.br/mercados/'
        'ibovespa-hoje-bolsa-de-valores-ao-vivo-26112026/',
      ),
    ]);
  });

  testWidgets('tocar uma fonte do cartão abre a URL dela', (t) async {
    final r = _fixture();
    await montarComponente(t, _vista(r), tamanho: _pc);
    final fonte = find.descendant(
      of: find.byKey(const Key('cartao-CSNA3')),
      matching: find.text('InfoMoney'),
    );
    await t.scrollUntilVisible(fonte, 300, scrollable: _vertical());
    await t.ensureVisible(fonte);
    await t.pumpAndSettle();
    await t.tap(fonte);
    expect(_links, [Uri.parse(r.ativos.first.fontes.first.url)]);
  });

  testWidgets('fonte sem http(s) aparece como texto e não abre', (t) async {
    final r = Relatorio(
      schemaVersion: 1,
      data: '2026-11-26',
      termometro: const Termometro(),
      termometroDoJson: false,
      ativos: const [
        AtivoRelatorio(
          ticker: 'XPTO3',
          fontes: [Fonte(nome: 'Vazia', url: '')],
        ),
      ],
      fontesCenario: const [Fonte(nome: 'Script', url: 'javascript:alert(1)')],
    );
    await montarComponente(t, _vista(r), tamanho: _pcAlto);
    for (final nome in ['Vazia', 'Script']) {
      expect(find.text(nome), findsOneWidget);
      await t.tap(find.text(nome));
    }
    expect(_links, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('relatório mínimo monta e mostra que não há ativos', (t) async {
    await montarComponente(
      t,
      _vista(Relatorio.deJson({}, dataDoArquivo: '2026-11-26')),
      tamanho: _pc,
    );
    expect(t.takeException(), isNull);
    expect(find.text('Nenhum ativo neste relatório.'), findsOneWidget);
    expect(find.text('Ativo'), findsNothing);
  });

  testWidgets('ativo sem nenhum campo além do ticker não trava', (t) async {
    await montarComponente(
      t,
      _vista(
        Relatorio.deJson({
          'ativos': [
            {'ticker': 'ABCD3'},
            {'ticker': 'ABCD3', 'preco': _vazio, 'precoExterior': _vazio},
            _vazio,
            _vazio,
          ],
          'educacaoRisco': _vazio,
        }),
      ),
      tamanho: _celular,
    );
    expect(t.takeException(), isNull);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('schemaVersion 2 mostra o aviso de versão nova', (t) async {
    await montarComponente(
      t,
      _vista(Relatorio.deJson({...fixtureRelatorio(), 'schemaVersion': 2})),
      tamanho: _pc,
    );
    expect(find.byKey(const Key('versao-nova')), findsOneWidget);
    expect(
      find.text(
        'Este relatório usa um formato mais novo que esta versão do app; '
        'algumas partes podem não aparecer.',
      ),
      findsOneWidget,
    );
  });

  for (final n in [0, 1, 60]) {
    testWidgets('$n ativos no celular sem overflow', (t) async {
      await montarComponente(
        t,
        _vista(Relatorio.deJson(fixtureComAtivos(n))),
        tamanho: _celular,
      );
      expect(t.takeException(), isNull);
      if (n == 0) {
        await t.scrollUntilVisible(
          find.text('Nenhum ativo neste relatório.'),
          400,
          scrollable: _vertical(),
        );
      }
      // Rola até o fim: cada cartão construído passa pelo layout.
      await t.scrollUntilVisible(
        find.byKey(const Key('secao-k')),
        400,
        scrollable: _vertical(),
        maxScrolls: 2000,
      );
      expect(t.takeException(), isNull);
      if (n == 60) {
        await t.drag(_vertical(), const Offset(0, 3000));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(const Key('cartao-ATV59')),
          400,
          scrollable: _vertical(),
          maxScrolls: 2000,
        );
        expect(find.byKey(const Key('cartao-ATV59')), findsOneWidget);
      }
    });
  }

  testWidgets('fixture no celular sem overflow', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _celular);
    await t.scrollUntilVisible(
      find.byKey(const Key('secao-k')),
      400,
      scrollable: _vertical(),
      maxScrolls: 2000,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'vista estreita no PC: tabela rola e indicadores ocupam a largura',
    (t) async {
      await montarComponente(
        t,
        SizedBox(width: 310, child: _vista(_fixture())),
        tamanho: _pc,
      );
      final ibov = find.ancestor(
        of: find.text('Ibovespa'),
        matching: find.byType(Cartao),
      );
      expect(t.getSize(ibov).width, 310 - 2 * 24);
      final g = find.byKey(const Key('secao-g'));
      await t.scrollUntilVisible(g, 400, scrollable: _vertical());
      expect(
        find.descendant(
          of: g,
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('vista larga no PC: tabela sem rolagem e indicadores de 240', (
    t,
  ) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    final ibov = find.ancestor(
      of: find.text('Ibovespa'),
      matching: find.byType(Cartao),
    );
    expect(t.getSize(ibov).width, 240);
    expect(
      find.descendant(
        of: find.byKey(const Key('secao-g')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
  });

  testWidgets('títulos das seções, dentro de cada uma', (t) async {
    await montarComponente(t, _vista(_fixture()), tamanho: _pcAlto);
    for (final (l, titulo) in [
      ('d', 'Indicadores'),
      ('e', 'Resumo'),
      ('f', 'Termômetro'),
      ('g', 'Resumo por ativo'),
      ('h', 'Ativos'),
      ('i', 'Como limitar o risco a 1% do capital'),
      ('k', 'Fontes do cenário'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('secao-$l')),
          matching: find.text(titulo),
        ),
        findsOneWidget,
        reason: titulo,
      );
    }
  });

  testWidgets('seção vazia não mostra título', (t) async {
    await montarComponente(
      t,
      _vista(Relatorio.deJson({}, dataDoArquivo: '2026-11-26')),
      tamanho: _pcAlto,
    );
    for (final s in [
      'Indicadores',
      'Resumo',
      'Resumo por ativo',
      'Ativos',
      'Fontes do cenário',
    ]) {
      expect(find.text(s), findsNothing, reason: s);
    }
  });

  testWidgets('especialista só com url mostra a url como link', (t) async {
    const url = 'https://exemplo.com/analise';
    final r = Relatorio(
      schemaVersion: 1,
      data: '2026-11-26',
      termometro: const Termometro(),
      termometroDoJson: false,
      ativos: const [
        AtivoRelatorio(
          ticker: 'XPTO3',
          especialistas: Especialistas(
            itens: [
              ItemEspecialista(url: url),
              ItemEspecialista(),
            ],
          ),
        ),
      ],
    );
    await montarComponente(t, _vista(r), tamanho: _pcAlto);
    await t.tap(find.text(url));
    expect(_links, [Uri.parse(url)]);
  });

  group('destaques e placar', () {
    Relatorio r27() => Relatorio.deJson(fixtureRelatorio27());
    double y(WidgetTester t, String k) => t.getTopLeft(find.byKey(Key(k))).dy;
    Finder textoEm(String k, String s) =>
        find.descendant(of: find.byKey(Key(k)), matching: find.text(s));

    testWidgets('seção de destaques entre o termômetro e a tabela', (t) async {
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      final sec = find.byKey(const Key('secao-destaques'));
      expect(sec, findsOneWidget);
      expect(
        find.descendant(of: sec, matching: find.text('Sinais mais favoráveis')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sec,
          matching: find.text(
            'Leitura positiva e especialistas indicando compra. Não é '
            'previsão nem recomendação.',
          ),
        ),
        findsOneWidget,
      );
      expect(y(t, 'destaque-EMBJ3'), lessThan(y(t, 'destaque-PRIO3')));
      expect(y(t, 'secao-destaques'), greaterThan(y(t, 'secao-f')));
      expect(y(t, 'secao-destaques'), lessThan(y(t, 'secao-g')));
      expect(find.text('★ EMBJ3'), findsOneWidget);
    });

    testWidgets('linha do destaque: resumo; sem preço, "—"', (t) async {
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      final a = r27().ativos.firstWhere((a) => a.ticker == 'EMBJ3');
      expect(
        textoEm('destaque-EMBJ3', a.especialistas.resumo!),
        findsOneWidget,
      );
      final json = fixtureRelatorio27();
      for (final x in json['ativos'] as List) {
        if ((x as Map)['ticker'] == 'EMBJ3') x.remove('preco');
      }
      await montarComponente(
        t,
        _vista(Relatorio.deJson(json)),
        tamanho: _pcAlto,
      );
      expect(textoEm('destaque-EMBJ3', '—'), findsOneWidget);
    });

    testWidgets('sem destaque, a seção some', (t) async {
      final json = fixtureRelatorio27();
      for (final a in json['ativos'] as List) {
        (a as Map)['leitura'] = 'negativa';
      }
      await montarComponente(t, _vista(Relatorio.deJson(json)), tamanho: _pc);
      expect(find.byKey(const Key('secao-destaques')), findsNothing);
      expect(find.text('Sinais mais favoráveis'), findsNothing);
    });

    testWidgets('cartões ordenados e selo de destaque', (t) async {
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      expect(y(t, 'cartao-EMBJ3'), lessThan(y(t, 'cartao-TAEE11')));
      expect(y(t, 'cartao-TAEE11'), lessThan(y(t, 'cartao-T1TW34')));
      for (final tk in ['CSNA3', 'BBAS3', 'LREN3', 'VALE3']) {
        expect(y(t, 'cartao-$tk'), lessThan(y(t, 'cartao-NVDC34')));
      }
      expect(textoEm('selo-destaque-EMBJ3', '★ Destaque'), findsOneWidget);
      expect(find.byKey(const Key('selo-destaque-WEGE3')), findsNothing);
      Finder borda(String k) => find.descendant(
        of: find.byKey(Key(k)),
        matching: find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          final b = d is BoxDecoration ? d.border : null;
          return b is Border &&
              b.top.width == 2 &&
              b.top.color == PaletaRelatorio.positivaTexto;
        }),
      );
      expect(borda('cartao-EMBJ3'), findsOneWidget);
      expect(borda('cartao-TAEE11'), findsNothing);
    });

    testWidgets('estrela na tabela só nos destaques', (t) async {
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      expect(find.byKey(const Key('estrela-tabela-PRIO3')), findsOneWidget);
      expect(find.byKey(const Key('estrela-tabela-RENT3')), findsNothing);
    });

    testWidgets('placar e potencial no cartão', (t) async {
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      expect(textoEm('placar-GOGL34', '3 compra'), findsOneWidget);
      expect(textoEm('placar-GOGL34', '1 neutra'), findsOneWidget);
      expect(textoEm('placar-GOGL34', '0 venda'), findsOneWidget);
      expect(find.byKey(const Key('placar-RURA11')), findsNothing);
      expect(
        textoEm('cartao-LREN3', '+79,6% até o alvo, com o preço de 26/11'),
        findsOneWidget,
      );
      final selo = find
          .descendant(
            of: find.byKey(const Key('placar-GOGL34')),
            matching: find.byType(Selo),
          )
          .first;
      expect(t.widget<Selo>(selo).cor, PaletaRelatorio.positivaTexto);
    });

    testWidgets('fixture de 26/11: destaques e placar contado', (t) async {
      final r = _fixture();
      expect(
        [
          for (final a in ordenarParaExibicao(r.ativos).where(emDestaque))
            a.ticker,
        ],
        ['RENT3', 'BPAC11'],
      );
      await montarComponente(t, _vista(r), tamanho: _pcAlto);
      expect(y(t, 'destaque-RENT3'), lessThan(y(t, 'destaque-BPAC11')));
      expect(textoEm('placar-RENT3', '1 compra'), findsOneWidget);
    });

    testWidgets('tema escuro: ★ e fundo do destaque mais claros', (t) async {
      Color? estrela(WidgetTester t) => t
          .widget<Text>(find.byKey(const Key('estrela-tabela-PRIO3')))
          .style
          ?.color;
      await montarComponente(
        t,
        _vista(r27()),
        tamanho: _pcAlto,
        tema: TemaVisual.terminal,
      );
      expect(estrela(t), const Color(0xFF81C995));
      expect(
        t.widget<Text>(find.text('★ PRIO3')).style?.color,
        const Color(0xFF81C995),
      );
      await montarComponente(t, _vista(r27()), tamanho: _pcAlto);
      await t.pumpAndSettle(); // o tema anima a troca
      expect(estrela(t), PaletaRelatorio.positivaTexto);
    });

    testWidgets('potencial aparece sem casa, alvo nem url', (t) async {
      final r = Relatorio.deJson({
        'ativos': [
          {
            'ticker': 'POTE3',
            'especialistas': {
              'itens': [
                {'potencial': '+10,0% até o alvo, com o preço de 26/11'},
              ],
            },
          },
        ],
      });
      await montarComponente(t, _vista(r), tamanho: _pcAlto);
      expect(
        textoEm('cartao-POTE3', '+10,0% até o alvo, com o preço de 26/11'),
        findsOneWidget,
      );
    });

    testWidgets('ticker repetido em destaque não quebra', (t) async {
      final item = {
        'ticker': 'DUPL3',
        'leitura': 'positiva',
        'especialistas': {
          'consenso': 'compra',
          'placar': {'compra': 2, 'neutra': 0, 'venda': 0},
        },
      };
      await montarComponente(
        t,
        _vista(
          Relatorio.deJson({
            'ativos': [item, item],
          }),
        ),
        tamanho: _pcAlto,
      );
      expect(t.takeException(), isNull);
      expect(find.text('★ DUPL3'), findsNWidgets(2));
    });
  });

  testWidgets('cores: aviso, faixas, alerta e direções', (t) async {
    final json = fixtureRelatorio();
    (json['indicadores'] as List).add({
      'nome': 'Estável',
      'valor': '1',
      'variacao': '0,00%',
      'direcao': 'neutra',
    });
    await montarComponente(
      t,
      _vista(Relatorio.deJson(json)),
      tamanho: _pcAlto,
      tema: TemaVisual.terminal,
    );
    expect(
      _fundo(t, find.byKey(const Key('secao-j'))),
      const Color(0xFFFFF4E5),
    );
    final faixas = find.descendant(
      of: find.byKey(const Key('secao-b')),
      matching: find.byType(DecoratedBox),
    );
    expect(faixas, findsNWidgets(2));
    for (final e in faixas.evaluate()) {
      expect(
        ((e.widget as DecoratedBox).decoration as BoxDecoration).color,
        const Color(0xFFFEF7E0),
      );
    }
    expect(
      t.widget<Text>(find.textContaining('Se o preço abrir')).style?.color,
      const Color(0xFFB3261E),
    );
    Finder selo(String s) =>
        find.ancestor(of: find.text(s), matching: find.byType(Selo));
    expect(find.byType(Pilula), findsNothing);
    // terminal é escuro: as cores do tema
    final c = CoresApp.de(t.element(find.byType(VistaRelatorio)));
    expect(t.widget<Selo>(selo('▼ -1,78%')).cor, c.queda);
    expect(t.widget<Selo>(selo('0,00%')).cor, c.textoSuave);
  });

  testWidgets('variação no tema escuro: selo com as cores do tema', (t) async {
    await montarComponente(
      t,
      const Column(
        children: [
          PilulaDirecao('+1%', Direcao.alta),
          PilulaDirecao('-1%', Direcao.queda),
          PilulaDirecao('0%', Direcao.neutra),
        ],
      ),
      tema: TemaVisual.moderno,
    );
    final c = CoresApp.de(t.element(find.byType(Column).first));
    final cores = [
      for (final w in t.widgetList<Selo>(find.byType(Selo))) w.cor,
    ];
    expect(cores, [c.alta, c.queda, c.textoSuave]);
    expect(find.byType(Pilula), findsNothing);
  });

  testWidgets('os selos de leitura são Selo chapado, sem borda', (t) async {
    await montarComponente(
      t,
      const Column(
        children: [
          SeloLeitura(Leitura.positiva),
          SeloLeitura(Leitura.mista),
          SeloLeitura(Leitura.neutra),
          SeloLeitura(Leitura.negativa, texto: 'Venda'),
        ],
      ),
    );
    expect(find.byType(Selo), findsNWidgets(4));
    expect(find.byType(Pilula), findsNothing);
    final cores = [
      for (final w in t.widgetList<Selo>(find.byType(Selo))) w.cor,
    ];
    expect(cores, [
      PaletaRelatorio.positivaTexto,
      PaletaRelatorio.mistaTexto,
      PaletaRelatorio.neutraTexto,
      PaletaRelatorio.negativaTexto,
    ]);
    final caixa = t.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(Selo).first,
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((caixa.decoration as BoxDecoration).border, isNull);
  });

  group('guia dos especialistas', () {
    Relatorio guia() => Relatorio.deJson(fixtureRelatorioGuia());
    double y(WidgetTester t, String k) => t.getTopLeft(find.byKey(Key(k))).dy;
    Finder em(String k, String s) =>
        find.descendant(of: find.byKey(Key(k)), matching: find.text(s));
    Finder emContendo(String k, String s) => find.descendant(
      of: find.byKey(Key(k)),
      matching: find.textContaining(s),
    );
    Finder pilulaDe(Finder texto) =>
        find.ancestor(of: texto, matching: find.byType(Selo));
    const explicacao =
        'Preço-alvo é quanto a casa acha que a ação vai valer no prazo '
        'indicado (em geral 12 meses). Não é preço para comprar nem para '
        'vender.';

    /// Um ativo só, com os especialistas montados no teste.
    Relatorio um(Map<String, Object?> esp, {Object? preco}) =>
        Relatorio.deJson({
          'schemaVersion': 1,
          'ativos': [
            {'ticker': 'ZZZ3', 'preco': ?preco, 'especialistas': esp},
          ],
        });

    testWidgets('explicação no topo, entre o cabeçalho e a legenda', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      expect(em('explicacao-preco-alvo', explicacao), findsOneWidget);
      expect(
        _fundo(t, find.byKey(const Key('explicacao-preco-alvo'))),
        PaletaRelatorio.azulFundo,
      );
      expect(y(t, 'explicacao-preco-alvo'), greaterThan(y(t, 'secao-a')));
      expect(y(t, 'explicacao-preco-alvo'), lessThan(y(t, 'secao-f')));
    });

    testWidgets('guiaLeigo no cartão, em caixa azul', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      final e = guia().ativos.firstWhere((a) => a.ticker == 'BPAC11');
      expect(em('guia-BPAC11', e.especialistas.guiaLeigo!), findsOneWidget);
      expect(
        _fundo(t, find.byKey(const Key('guia-BPAC11'))),
        PaletaRelatorio.azulFundo,
      );
      expect(find.byKey(const Key('guia-CSNA3')), findsOneWidget);
      expect(find.byKey(const Key('placar-BPAC11')), findsOneWidget);
    });

    testWidgets('comparação do BPAC11', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      for (final s in [
        'Último preço',
        'R\$ 56,90 em 26/11',
        'Alvo médio',
        'R\$ 67,67',
        '+18,9%',
        'Faixa dos alvos: R\$ 60,00 a R\$ 72,00',
      ]) {
        expect(em('comparacao-BPAC11', s), findsOneWidget, reason: s);
      }
      expect(
        t.widget<Selo>(pilulaDe(em('comparacao-BPAC11', '+18,9%'))).cor,
        PaletaRelatorio.positivaTexto,
      );
    });

    testWidgets('faixa com min igual a max; sem alvo médio, sem comparação', (
      t,
    ) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      expect(
        em('comparacao-TAEE11', 'Faixa dos alvos: R\$ 43,50'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comparacao-CSNA3')), findsNothing);
    });

    testWidgets('comparação: potencial, faixa e último preço (mapas)', (
      t,
    ) async {
      Future<void> monta(Map<String, Object?> esp, {Object? preco}) =>
          montarComponente(t, _vista(um(esp, preco: preco)), tamanho: _pcAlto);
      const k = 'comparacao-ZZZ3';
      await monta({'alvoMedio': 'R\$ 9', 'potencialMedio': '-4,0%'});
      expect(
        t.widget<Selo>(pilulaDe(em(k, '-4,0%'))).cor,
        PaletaRelatorio.negativaTexto,
      );
      await monta({'alvoMedio': 'R\$ 9', 'potencialMedio': '−4,0%'});
      expect(
        t.widget<Selo>(pilulaDe(em(k, '−4,0%'))).cor,
        PaletaRelatorio.negativaTexto,
      );
      await monta({'alvoMedio': 'R\$ 9', 'potencialMedio': 'n/d'});
      expect(
        t.widget<Selo>(pilulaDe(em(k, 'n/d'))).cor,
        PaletaRelatorio.neutraTexto,
      );
      // sem min ou max, a faixa some; sem referência, o preço do ativo
      await monta(
        {'alvoMedio': 'R\$ 9', 'alvoMin': 'R\$ 8'},
        preco: {'texto': 'R\$ 7,00', 'data': '2026-11-26'},
      );
      expect(emContendo(k, 'Faixa dos alvos'), findsNothing);
      expect(em(k, 'R\$ 7,00 · 26/11/2026'), findsOneWidget);
      await monta({
        'alvoMedio': 'R\$ 9',
        'alvoMin': 'R\$ 8',
        'alvoMax': 'R\$ 10',
      });
      expect(em(k, 'Faixa dos alvos: R\$ 8 a R\$ 10'), findsOneWidget);
      expect(em(k, '—'), findsOneWidget);
    });

    testWidgets('sub-cartão da casa do BPAC11', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      const k = 'casa-BPAC11-0';
      expect(em(k, 'Compra'), findsOneWidget);
      expect(em(k, 'Safra'), findsOneWidget);
      expect(em(k, '12/11/2026'), findsOneWidget);
      const motivo =
          'Motivo: Mantém a visão positiva, embora tenha achado as despesas '
          'do trimestre um pouco negativas.';
      expect(em(k, motivo), findsOneWidget);
      expect(emContendo(k, 'Motivo:'), findsOneWidget);
      expect(t.widget<Text>(em(k, motivo)).style?.fontStyle, FontStyle.italic);
      expect(
        emContendo(k, 'O Safra indica COMPRAR. Alvo: R\$ 71,00'),
        findsOneWidget,
      );
      expect(em('casa-BPAC11-1', 'Manter'), findsOneWidget);
      final url = guia().ativos
          .firstWhere((a) => a.ticker == 'BPAC11')
          .especialistas
          .itens[0]
          .url!;
      await t.tap(
        find.descendant(
          of: find.byKey(const Key(k)),
          matching: find.byType(LinkRelatorio),
        ),
      );
      expect(_links, [Uri.parse(url)]);
    });

    testWidgets('sub-cartão: selo pelo texto, sem selo, motivo diferente e '
        'link inseguro (mapas)', (t) async {
      await montarComponente(
        t,
        _vista(
          um({
            'itens': [
              {
                'casa': 'A',
                'recomendacao': 'Venda forte',
                'fraseGuia': 'O A indica VENDER.',
                'url': 'javascript:x',
              },
              {'casa': 'B', 'motivo': 'só motivo'},
              {
                'casa': 'C',
                'classificacao': 'sem_classificacao',
                'fraseGuia': 'O C ficou fora. Motivo: outro texto.',
                'motivo': 'texto diferente',
              },
              {'casa': 'D', 'recomendacao': 'Compra', 'data': '2026-11-01'},
            ],
          }),
        ),
        tamanho: _pcAlto,
      );
      expect(em('casa-ZZZ3-0', 'Venda'), findsOneWidget);
      expect(em('casa-ZZZ3-0', 'O A indica VENDER.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('casa-ZZZ3-0')),
          matching: find.byType(LinkRelatorio),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('casa-ZZZ3-1')),
          matching: find.byType(Selo),
        ),
        findsNothing,
      );
      expect(em('casa-ZZZ3-1', 'Motivo: só motivo'), findsOneWidget);
      expect(em('casa-ZZZ3-2', 'Sem classificação'), findsOneWidget);
      expect(
        em('casa-ZZZ3-2', 'O C ficou fora. Motivo: outro texto.'),
        findsOneWidget,
      );
      expect(em('casa-ZZZ3-2', 'Motivo: texto diferente'), findsOneWidget);
      // sem frase nem motivo: a linha da 2.8.0, sem sub-cartão
      expect(find.byKey(const Key('casa-ZZZ3-3')), findsNothing);
      expect(find.textContaining('D · Compra · 01/11/2026'), findsOneWidget);
    });

    testWidgets('sub-cartão só com motivo mostra recomendação, alvo e '
        'potencial; frase igual ao motivo não vira Text vazio', (t) async {
      await montarComponente(
        t,
        _vista(
          um({
            'itens': [
              {'casa': 'A', 'fraseGuia': 'Motivo: m.', 'motivo': 'M'},
              {
                'casa': 'B',
                'recomendacao': 'Neutro',
                'precoAlvo': 'R\$ 10,00',
                'potencial': '+5,0%',
                'motivo': 'só motivo',
              },
            ],
          }),
        ),
        tamanho: _pcAlto,
      );
      expect(
        em('casa-ZZZ3-1', 'Neutro · alvo R\$ 10,00 · +5,0%'),
        findsOneWidget,
      );
      expect(em('casa-ZZZ3-1', 'Motivo: só motivo'), findsOneWidget);
      expect(em('casa-ZZZ3-0', ''), findsNothing);
      expect(em('casa-ZZZ3-0', 'Motivo: M'), findsOneWidget);
    });

    testWidgets('sem os campos, nada do guia aparece', (t) async {
      for (final f in [fixtureRelatorio(), fixtureRelatorio27()]) {
        await montarComponente(
          t,
          _vista(Relatorio.deJson(f)),
          tamanho: _pcAlto,
        );
        for (final k in [
          'explicacao-preco-alvo',
          'guia-',
          'comparacao-',
          'casa-',
        ]) {
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(k),
            ),
            findsNothing,
            reason: k,
          );
        }
        expect(find.text(explicacao), findsNothing);
      }
    });
  });

  group('resumo por ativo no celular', () {
    const celularAlto = Size(360, 20000);
    Relatorio guia() => Relatorio.deJson(fixtureRelatorioGuia());
    Finder em(String k, String s) =>
        find.descendant(of: find.byKey(Key(k)), matching: find.text(s));
    final rolagemHorizontal = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );

    testWidgets('celular: linhas empilhadas, sem rolagem horizontal', (
      t,
    ) async {
      final r = guia();
      await montarComponente(t, _vista(r), tamanho: celularAlto);
      final g = find.byKey(const Key('secao-g'));
      expect(find.descendant(of: g, matching: rolagemHorizontal), findsNothing);
      expect(
        find.descendant(of: g, matching: find.byType(Table)),
        findsNothing,
      );
      final a = r.ativos.firstWhere((a) => a.ticker == 'BPAC11');
      expect(em('linha-resumo-BPAC11', 'BPAC11'), findsOneWidget);
      expect(em('linha-resumo-BPAC11', textoPreco(a.preco)), findsOneWidget);
      expect(
        em('linha-resumo-BPAC11', a.especialistas.resumo!),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('linha-resumo-BPAC11')),
          matching: find.byType(SeloLeitura),
        ),
        findsOneWidget,
      );
      for (final x in r.ativos) {
        expect(
          find.byKey(Key('linha-resumo-${x.ticker}')),
          findsOneWidget,
          reason: x.ticker,
        );
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('celular: destaque ganha estrela na linha', (t) async {
      await montarComponente(
        t,
        _vista(Relatorio.deJson(fixtureRelatorio27())),
        tamanho: celularAlto,
      );
      expect(find.byKey(const Key('estrela-tabela-PRIO3')), findsOneWidget);
      expect(find.byKey(const Key('estrela-tabela-RENT3')), findsNothing);
    });

    testWidgets('PC: a tabela continua', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      final g = find.byKey(const Key('secao-g'));
      expect(
        find.descendant(of: g, matching: find.byType(Table)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('linha-resumo-BPAC11')), findsNothing);
    });
  });

  group('filtros e pesquisa', () {
    const celularAlto = Size(360, 20000);
    Relatorio guia() => Relatorio.deJson(fixtureRelatorioGuia());
    final campo = find.byKey(const Key('filtro-busca'));
    Finder cartao(String tk) => find.byKey(Key('cartao-$tk'));
    Finder linha(String tk) => find.byKey(Key('linha-resumo-$tk'));

    /// No celular os chips começam recolhidos atrás do botão "Filtros (N)".
    Future<void> abrir(WidgetTester t) async {
      await t.tap(find.byKey(const Key('filtros-alternar')));
      await t.pumpAndSettle();
    }

    testWidgets('digitar filtra tabela e cartões', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      expect(find.text('23 de 23 ativos'), findsOneWidget);
      await t.enterText(campo, 'itau');
      await t.pumpAndSettle();
      for (final f in [linha, cartao]) {
        expect(f('RURA11'), findsOneWidget);
        expect(f('PETR4'), findsNothing);
      }
      // o termômetro continua com todos
      expect(find.byKey(const Key('selo-termometro-PETR4')), findsOneWidget);
      expect(find.text('1 de 23 ativos'), findsOneWidget);
      expect(find.text('Limpar filtros'), findsOneWidget);
    });

    testWidgets('chips: tipo E leitura; carteira; Limpar filtros', (t) async {
      await montarComponente(
        t,
        VistaRelatorio(
          relatorio: guia(),
          aoAbrirLink: _links.add,
          carteira: const {'PETR4', 'VALE3'},
        ),
        tamanho: celularAlto,
      );
      await abrir(t);
      await t.tap(find.byKey(const Key('chip-tipo-bdr')));
      await t.pump();
      await t.tap(find.byKey(const Key('chip-leitura-negativa')));
      await t.pumpAndSettle();
      expect(cartao('NVDC34'), findsOneWidget);
      expect(cartao('GOGL34'), findsNothing);
      expect(find.text('1 de 23 ativos'), findsOneWidget);
      await t.tap(find.text('Limpar filtros'));
      await t.pumpAndSettle();
      expect(find.text('23 de 23 ativos'), findsOneWidget);
      await t.tap(find.byKey(const Key('chip-carteira')));
      await t.pumpAndSettle();
      expect(find.text('2 de 23 ativos'), findsOneWidget);
      expect(cartao('PETR4'), findsOneWidget);
      expect(cartao('VALE3'), findsOneWidget);
      await t.tap(find.byKey(const Key('chip-com-analise')));
      await t.pump();
      await t.tap(find.byKey(const Key('chip-sem-analise')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('filtro-vazio')), findsOneWidget);
    });

    testWidgets('sem posições carregadas o chip da carteira some', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      await abrir(t);
      expect(find.byKey(const Key('chip-carteira')), findsNothing);
      expect(find.byKey(const Key('chip-destaque')), findsOneWidget);
    });

    testWidgets('nada passa: mensagem, sem tabela nem cartões', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      await t.enterText(campo, 'zzzz');
      await t.pumpAndSettle();
      expect(find.text('Nenhum ativo com esses filtros'), findsOneWidget);
      expect(find.byKey(const Key('secao-g')), findsNothing);
      expect(find.byType(CartaoAtivo), findsNothing);
      expect(find.text('0 de 23 ativos'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('barra entre os destaques e o resumo por ativo', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      double y(String k) => t.getTopLeft(find.byKey(Key(k))).dy;
      expect(y('secao-destaques'), lessThan(y('filtros-ativos')));
      expect(y('filtros-ativos'), lessThan(y('secao-g')));
      expect(
        find.descendant(
          of: find.byKey(const Key('secao-h')),
          matching: find.byKey(const Key('filtros-ativos')),
        ),
        findsNothing,
      );
    });

    testWidgets('celular: chips recolhidos, botão com a contagem', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      expect(campo, findsOneWidget);
      expect(find.text('Filtros (0)'), findsOneWidget);
      expect(find.byKey(const Key('chip-destaque')), findsNothing);
      await abrir(t);
      expect(find.byKey(const Key('chip-destaque')), findsOneWidget);
      await t.tap(find.byKey(const Key('chip-destaque')));
      await t.pump();
      await t.tap(find.byKey(const Key('chip-leitura-mista')));
      await t.pumpAndSettle();
      expect(find.text('Filtros (2)'), findsOneWidget);
      await abrir(t);
      expect(find.byKey(const Key('chip-destaque')), findsNothing);
    });

    testWidgets('PC: chips sempre à vista, sem botão', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: _pcAlto);
      expect(find.byKey(const Key('filtros-alternar')), findsNothing);
      expect(find.byKey(const Key('chip-destaque')), findsOneWidget);
    });

    testWidgets('resultado vazio mantém a barra à vista', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      await t.enterText(campo, 'zzzz');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('filtros-ativos')), findsOneWidget);
      expect(campo, findsOneWidget);
    });

    testWidgets('Com análise e Sem análise', (t) async {
      await montarComponente(t, _vista(guia()), tamanho: celularAlto);
      await abrir(t);
      await t.tap(find.byKey(const Key('chip-com-analise')));
      await t.pumpAndSettle();
      expect(cartao('T1TW34'), findsNothing);
      expect(cartao('GOGL34'), findsNothing);
      expect(cartao('RURA11'), findsNothing);
      expect(cartao('CSNA3'), findsOneWidget);
      await t.tap(find.byKey(const Key('chip-sem-analise')));
      await t.pumpAndSettle();
      expect(cartao('T1TW34'), findsOneWidget);
      expect(cartao('GOGL34'), findsOneWidget);
      expect(cartao('CSNA3'), findsNothing);
      expect(find.text('3 de 23 ativos'), findsOneWidget);
    });

    testWidgets('carteira que passa a falhar desliga o filtro', (t) async {
      final carteira = ValueNotifier<Set<String>?>({'PETR4'});
      addTearDown(carteira.dispose);
      await montarComponente(
        t,
        ValueListenableBuilder<Set<String>?>(
          valueListenable: carteira,
          builder: (_, c, _) => VistaRelatorio(
            relatorio: guia(),
            aoAbrirLink: _links.add,
            carteira: c,
          ),
        ),
        tamanho: celularAlto,
      );
      await abrir(t);
      await t.tap(find.byKey(const Key('chip-carteira')));
      await t.pumpAndSettle();
      expect(find.text('1 de 23 ativos'), findsOneWidget);
      carteira.value = null;
      await t.pumpAndSettle();
      expect(find.text('23 de 23 ativos'), findsOneWidget);
      expect(find.byKey(const Key('chip-carteira')), findsNothing);
    });

    testWidgets('chip de tipo com texto longo não estoura em 360 px', (
      t,
    ) async {
      final j = fixtureRelatorioGuia();
      ((j['ativos'] as List).first as Map)['tipoAtivo'] =
          'um tipo de ativo com um nome muito mas muito longo mesmo';
      await montarComponente(
        t,
        _vista(Relatorio.deJson(j)),
        tamanho: celularAlto,
      );
      await abrir(t);
      expect(t.takeException(), isNull);
      expect(find.byType(CartaoAtivo), findsWidgets);
    });

    for (final tema in [TemaVisual.terminal, TemaVisual.moderno]) {
      testWidgets('360 px sem overflow, tema ${tema.chave}', (t) async {
        await montarComponente(
          t,
          VistaRelatorio(
            relatorio: guia(),
            aoAbrirLink: _links.add,
            carteira: const {'PETR4'},
          ),
          tamanho: celularAlto,
          tema: tema,
        );
        await abrir(t);
        await t.enterText(campo, 'a');
        await t.tap(find.byKey(const Key('chip-leitura-mista')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(CartaoAtivo), findsWidgets);
      });
    }
  });
}
