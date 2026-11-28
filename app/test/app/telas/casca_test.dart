import 'dart:async';

import 'package:calculadoradarf/app/componentes/controles.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/amigos/tela_amigos.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/app/telas/caixa/tela_caixa.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/telas/conta/tela_conta.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:calculadoradarf/app/telas/noticias/tela_noticias.dart';
import 'package:calculadoradarf/app/telas/radar/tela_radar.dart';
import 'package:calculadoradarf/app/telas/relatorios/tela_relatorios.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/dados_exemplo.dart';
import '../apoio/montar.dart';
import '../apoio/servicos_falsos.dart';

const _pequeno = Size(360, 800);

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(Casca)), listen: false);

Finder _naBarra(String texto) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(texto));

Finder _naLateral(String texto) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(texto),
);

/// Tela de teste com estado próprio, para provar que ele sobrevive.
class _Contador extends StatefulWidget {
  const _Contador(this.aba);

  final Aba aba;

  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int toques = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => toques++),
      child: Text('${widget.aba.name}: $toques'),
    ),
  );
}

/// O seletor de dados do cabeçalho do PC (texto com o ícone de grupo).
Finder get _seletorPc => find.widgetWithIcon(BotaoLeve, Icons.group);

Finder _noMenu(String texto) => find.descendant(
  of: find.byWidgetPredicate((w) => w is PopupMenuItem),
  matching: find.text(texto),
);

/// Casca com abas vazias: o teste olha só o cabeçalho.
Future<void> _montarCabecalho(
  WidgetTester t,
  ServicosFalsos s, {
  Size tamanho = const Size(1366, 768),
}) async {
  await montarApp(
    t,
    servicos: s,
    tamanho: tamanho,
    tela: Casca(telaDaAba: (_) => const SizedBox()),
  );
  await t.pumpAndSettle();
}

/// Apuração com valores redondos, para ver o Atualizar trazer dados novos.
VisaoMes _visaoComValores({String? amigo}) => VisaoMes(
  mes: '2026-10',
  dados: mesAbertoExemplo(),
  amigo: amigo,
  apuracao: Apuracao(
    ops: [],
    vendasAcoesSt: 15000,
    isento: true,
    bruto: 1234.56,
    custos: 12.34,
    impSt: 0,
    impDt: 20.5,
    impostoTotal: 20.5,
    irrf: 1.5,
    lucroLiquido: 1200,
    darfMes: 25,
    darfAnterior: 5,
    darf: 30,
  ),
);

void main() {
  testWidgets('1366 de largura mostra barra lateral e cabeçalho', (t) async {
    await montarApp(t);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Calculadora DARF'), findsOneWidget);
    expect(find.text('Ações e BDRs · apuração mensal de IR'), findsOneWidget);
    expect(find.textContaining('Saldo: '), findsOneWidget);
    expect(find.text('○ Google não conectado'), findsOneWidget);
    expect(find.text('Meta de lucro'), findsOneWidget);
    expect(find.text('Meus dados'), findsOneWidget);
    expect(find.text('Amigos'), findsNothing);
    expect(
      find.widgetWithText(BotaoSecundario, 'Conectar Google'),
      findsOneWidget,
    );
    expect(_naLateral('Apuração / DARF'), findsOneWidget);
  });

  testWidgets("o botão 'Meta de lucro' do cabeçalho abre as metas", (t) async {
    await montarApp(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Meta de lucro'));
    await t.pumpAndSettle();
    expect(find.text('Meta de lucro / Preço-alvo'), findsOneWidget);
    expect(find.text('METAS'), findsOneWidget);
  });

  testWidgets('o cartão de metas do celular abre as metas em tela cheia', (
    t,
  ) async {
    await montarApp(t, tamanho: _pequeno);
    await t.pumpAndSettle();
    await t.tap(find.text('Meta de lucro / Preço-alvo'));
    await t.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Calculadora'), findsOneWidget);
  });

  group('cabeçalho do PC', () {
    testWidgets('1366: seletor, saldo, Meta · N e avatar, sem Amigos', (
      t,
    ) async {
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 2
        ..estadoConta = const EstadoConta(
          email: 'joana@gmail.com',
          status: StatusSync.ok,
        );
      await montarApp(t, servicos: s);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: _seletorPc, matching: find.text('Meus dados')),
        findsOneWidget,
      );
      expect(find.textContaining('Saldo: '), findsOneWidget);
      expect(find.text('Meta de lucro · 2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CircleAvatar),
          matching: find.text('J'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('joana@gmail.com'), findsOneWidget);
      expect(find.text('Amigos'), findsNothing);
      expect(find.text('● Sincronizado'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a conta aberta mostra o amigo no subtítulo', (t) async {
      final s = ServicosFalsos();
      await montarApp(t, servicos: s);
      s.eventosFalsos.add(
        const EventoConta(EstadoConta(email: 'eu@gmail.com')),
      );
      await t.pump();
      await _estado(t).trocarVisao('bia@gmail.com');
      await t.pump();
      expect(
        find.text('Dados de bia@gmail.com · somente leitura'),
        findsOneWidget,
      );
    });

    testWidgets('o avatar fica desabilitado durante o login', (t) async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(
          email: 'joana@gmail.com',
          status: StatusSync.login,
        );
      await montarApp(t, servicos: s);
      final avatar = find.ancestor(
        of: find.byType(CircleAvatar),
        matching: find.byType(IconButton),
      );
      expect(t.widget<IconButton>(avatar).onPressed, isNull);
    });

    testWidgets('sem conta, Conectar Google é o botão secundário', (t) async {
      await _montarCabecalho(t, ServicosFalsos());
      expect(
        find.widgetWithText(BotaoSecundario, 'Conectar Google'),
        findsOneWidget,
      );
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('840: Meta e seletor só com ícone; status só com o ponto', (
      t,
    ) async {
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 2
        ..estadoConta = const EstadoConta(
          email: 'joana@gmail.com',
          status: StatusSync.ok,
        );
      await _montarCabecalho(t, s, tamanho: const Size(840, 768));
      expect(t.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Meta de lucro · 2'), findsNothing);
      expect(find.byTooltip('Meta de lucro · 2'), findsOneWidget);
      expect(find.text('Meus dados'), findsNothing);
      expect(find.byTooltip('Meus dados'), findsOneWidget);
      expect(find.text('● Sincronizado'), findsNothing);
      expect(find.byTooltip('● Sincronizado'), findsOneWidget);
      expect(find.textContaining('Saldo: '), findsOneWidget);
      expect(find.byTooltip('joana@gmail.com'), findsOneWidget);
    });

    testWidgets('840 com amigo aberto e conta longa não estoura', (t) async {
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 2
        ..estadoConta = const EstadoConta(
          email: 'outro.nome.bem.comprido.demais@gmail.com',
          status: StatusSync.offline,
        );
      await _montarCabecalho(t, s, tamanho: const Size(840, 768));
      await _estado(t).trocarVisao('nome.bem.comprido.de.verdade@exemplo.com');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byTooltip('Atualizar dados do amigo'), findsOneWidget);
    });

    // logo acima do corte: a barra lateral e o padding também comem largura
    for (final largura in [1200.0, 1260.0]) {
      testWidgets('$largura com amigo, saldo grande e hora não estoura', (
        t,
      ) async {
        const longo = 'nome.bem.comprido.de.verdade@exemplo.com';
        final s = ServicosFalsos()
          ..metasAtivasFalsas = 12
          ..estadoConta = const EstadoConta(
            email: 'outro.nome.bem.comprido.demais@gmail.com',
            status: StatusSync.ok,
            ultimaSync: 1700000000,
          );
        await _montarCabecalho(t, s, tamanho: Size(largura, 768));
        _estado(t).textoSaldo = 'Saldo: -R\$ 1.234.567,89';
        await _estado(t).trocarVisao(longo);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Saldo: -R\$ 1.234.567,89'), findsOneWidget);
        expect(find.byTooltip('Atualizar dados do amigo'), findsOneWidget);
        expect(find.textContaining('Sincronizado às'), findsOneWidget);
      });
    }

    testWidgets('e-mails de 40 caracteres a 1366 não estouram', (t) async {
      const longo = 'nome.bem.comprido.de.verdade@exemplo.com';
      expect(longo.length, 40);
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 2
        ..estadoConta = const EstadoConta(
          email: 'outro.nome.bem.comprido.demais@gmail.com',
          status: StatusSync.offline,
        );
      await _montarCabecalho(t, s);
      await _estado(t).trocarVisao(longo);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Dados de $longo · somente leitura'), findsOneWidget);
      expect(
        find.descendant(of: _seletorPc, matching: find.text(longo)),
        findsOneWidget,
      );
    });
  });

  group('seletor de dados', () {
    ServicosFalsos comAmigos() => ServicosFalsos()
      ..estadoConta = const EstadoConta(
        email: 'eu@gmail.com',
        linkPlanilha: 'https://docs.google.com/spreadsheets/d/x',
      )
      ..listaAmigos = [Amigo(email: 'ana@exemplo.com', desde: '2026-10-01')];

    testWidgets('o menu lista Meus dados e os amigos e troca a visão', (
      t,
    ) async {
      final s = comAmigos();
      await montarApp(t, servicos: s);
      await t.pumpAndSettle();
      await t.tap(_seletorPc);
      await t.pumpAndSettle();
      expect(_noMenu('Meus dados'), findsOneWidget);
      expect(_noMenu('Gerenciar amigos…'), findsOneWidget);
      await t.tap(_noMenu('ana@exemplo.com'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('carregarAmigo(ana@exemplo.com)'));
      expect(_estado(t).amigo, 'ana@exemplo.com');
      expect(
        find.text('Dados de ana@exemplo.com · somente leitura'),
        findsOneWidget,
      );
    });

    testWidgets('Gerenciar amigos… abre Amigos', (t) async {
      await montarApp(t, servicos: comAmigos());
      await t.pumpAndSettle();
      await t.tap(_seletorPc);
      await t.pumpAndSettle();
      await t.tap(_noMenu('Gerenciar amigos…'));
      await t.pumpAndSettle();
      expect(find.byType(TelaAmigos), findsOneWidget);
    });

    testWidgets('com amigo aberto: e-mail na cor aviso e Atualizar', (t) async {
      final s = comAmigos();
      await montarApp(t, servicos: s);
      await t.pumpAndSettle();
      expect(find.byTooltip('Atualizar dados do amigo'), findsNothing);
      await _estado(t).trocarVisao('ana@exemplo.com');
      await t.pumpAndSettle();
      final botao = t.widget<BotaoLeve>(_seletorPc);
      expect(botao.rotulo, 'ana@exemplo.com');
      expect(botao.cor, CoresApp.de(t.element(_seletorPc)).aviso);
      expect(find.widgetWithIcon(BotaoIcone, Icons.refresh), findsOneWidget);
      int carregas() =>
          s.chamadas.where((c) => c.startsWith('carregarAmigo')).length;
      final antes = carregas();
      s.visoes['2026-10'] = _visaoComValores(amigo: 'ana@exemplo.com');
      expect(find.text('R\$ 1.234,56'), findsNothing);
      await t.tap(find.byTooltip('Atualizar dados do amigo'));
      await t.pumpAndSettle();
      expect(carregas(), antes + 1);
      expect(find.text('R\$ 1.234,56'), findsOneWidget);
    });

    testWidgets('desabilitado enquanto os dados do amigo carregam', (t) async {
      final s = _AmigoLento()
        ..estadoConta = const EstadoConta(email: 'eu@gmail.com');
      await montarApp(t, servicos: s);
      await t.pumpAndSettle();
      unawaited(_estado(t).trocarVisao('ana@exemplo.com'));
      await t.pump();
      expect(_estado(t).carregandoAmigo, isTrue);
      expect(t.widget<BotaoLeve>(_seletorPc).onPressed, isNull);
      s.liberar.complete();
      await t.pumpAndSettle();
      expect(t.widget<BotaoLeve>(_seletorPc).onPressed, isNotNull);
    });

    testWidgets('sem a lista de amigos sobram Meus dados e o aberto', (
      t,
    ) async {
      final s = comAmigos()..erros['amigos'] = Offline();
      await montarApp(t, servicos: s);
      await t.pumpAndSettle();
      await _estado(t).trocarVisao('bia@exemplo.com');
      await t.pumpAndSettle();
      await t.tap(_seletorPc);
      await t.pumpAndSettle();
      expect(_noMenu('Meus dados'), findsOneWidget);
      expect(_noMenu('bia@exemplo.com'), findsOneWidget);
      expect(_noMenu('ana@exemplo.com'), findsNothing);
    });

    group('celular (360)', () {
      Finder noAppBar(Finder f) =>
          find.descendant(of: find.byType(AppBar), matching: f);

      testWidgets('ícone Meus dados no AppBar com o mesmo menu', (t) async {
        final s = comAmigos();
        await montarApp(t, servicos: s, tamanho: _pequeno);
        await t.pumpAndSettle();
        final icone = noAppBar(find.byTooltip('Meus dados'));
        expect(icone, findsOneWidget);
        expect(
          noAppBar(find.widgetWithIcon(BotaoIcone, Icons.group)),
          findsOneWidget,
        );
        expect(find.text('Voltar aos meus'), findsNothing);
        await t.tap(icone);
        await t.pumpAndSettle();
        expect(_noMenu('Meus dados'), findsOneWidget);
        expect(_noMenu('Gerenciar amigos…'), findsOneWidget);
        await t.tap(_noMenu('ana@exemplo.com'));
        await t.pumpAndSettle();
        expect(_estado(t).amigo, 'ana@exemplo.com');
      });

      testWidgets('faixa do amigo com Atualizar e Voltar aos meus', (t) async {
        final s = comAmigos();
        await montarApp(t, servicos: s, tamanho: _pequeno);
        await t.pumpAndSettle();
        expect(find.byTooltip('Atualizar dados do amigo'), findsNothing);
        await _estado(t).trocarVisao('ana@exemplo.com');
        await t.pumpAndSettle();
        expect(
          find.text('Dados de ana@exemplo.com · somente leitura'),
          findsOneWidget,
        );
        expect(find.byTooltip('Atualizar dados do amigo'), findsOneWidget);
        s.visoes['2026-10'] = _visaoComValores(amigo: 'ana@exemplo.com');
        await t.tap(find.byTooltip('Atualizar dados do amigo'));
        await t.pumpAndSettle();
        expect(find.text('R\$ 1.234,56'), findsOneWidget);
        await t.tap(find.text('Voltar aos meus'));
        await t.pumpAndSettle();
        expect(_estado(t).amigo, isNull);
        expect(find.text('Voltar aos meus'), findsNothing);
        expect(t.takeException(), isNull);
      });
    });
  });

  testWidgets('360 de largura mostra barra inferior e AppBar', (t) async {
    await montarApp(t, tamanho: _pequeno);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Calculadora DARF'),
      ),
      findsOneWidget,
    );
    for (final r in ['Apuração', 'Caixa', 'Radar', 'Notícias', 'Conta']) {
      expect(_naBarra(r), findsOneWidget);
    }
  });

  group('seis abas, Relatórios entre Notícias e Conta', () {
    const ordem = ['Apuração', 'Caixa', 'Radar', 'Notícias', 'Relatórios'];

    List<String> rotulos(WidgetTester t, Type barra) => [
      for (final e
          in find
              .descendant(of: find.byType(barra), matching: find.byType(Text))
              .evaluate())
        ?(e.widget as Text).data,
    ];

    testWidgets('no celular (360 px), na barra inferior, sem corte', (t) async {
      await montarApp(t, tamanho: _pequeno);
      await t.pumpAndSettle();
      expect(rotulos(t, NavigationBar), [...ordem, 'Conta']);
      expect(t.takeException(), isNull);
      final texto = find
          .descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Relatórios'),
          )
          .evaluate()
          .single;
      final paragrafo = texto.findRenderObject()! as RenderParagraph;
      expect(paragrafo.didExceedMaxLines, isFalse);
      // nem cortado na largura do destino (360 / 6 = 60 px)
      expect(paragrafo.size.width, lessThanOrEqualTo(60));
      expect(
        paragrafo.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragrafo.size.width + .01),
      );
    });

    testWidgets('no PC (1366 px), na barra lateral', (t) async {
      await montarApp(t, tamanho: const Size(1366, 768));
      await t.pumpAndSettle();
      expect(rotulos(t, NavigationRail), [
        'Apuração / DARF',
        ...ordem.skip(1),
        'Conta',
      ]);
      expect(Aba.values.map((a) => a.name), [
        'apuracao',
        'caixa',
        'radar',
        'noticias',
        'relatorios',
        'conta',
      ]);
    });

    testWidgets('tocar em Relatórios mostra a tela de Relatórios', (t) async {
      await montarApp(t, tamanho: _pequeno);
      await t.tap(_naBarra('Relatórios'));
      await t.pumpAndSettle();
      expect(_estado(t).aba, Aba.relatorios);
      expect(find.byType(TelaRelatorios), findsOneWidget);
    });
  });

  testWidgets('a aba Apuração mostra a tela de Apuração, não o espaço', (
    t,
  ) async {
    await montarApp(t);
    await t.pumpAndSettle();
    expect(find.byType(TelaApuracao), findsOneWidget);
    expect(find.text('Apuração (em construção)'), findsNothing);
    expect(find.text('Lucro bruto'), findsOneWidget);
    expect(find.text('Ativos comprados'), findsOneWidget);
  });

  testWidgets('a aba Conta mostra a tela de Conta, não o espaço', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.tap(_naBarra('Conta'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.conta);
    expect(find.byType(TelaConta), findsOneWidget);
    expect(find.text('Conta (em construção)'), findsNothing);
  });

  group('atualização do app', () {
    const info = InfoAtualizacao(
      versao: '9.9.9',
      notas: 'Novo.',
      url: 'https://exemplo.com/a.exe',
      tamanho: 10,
      sha256: '',
    );

    testWidgets('verifica 3 s depois de abrir e oferece uma vez', (t) async {
      final s = ServicosFalsos()..infoAtualizacao = info;
      await montarApp(t, servicos: s, verificarAtualizacao: true);
      await t.pump(const Duration(seconds: 2));
      expect(s.chamadas, isNot(contains('verificarAtualizacao()')));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        s.chamadas.where((c) => c == 'verificarAtualizacao()'),
        hasLength(1),
      );
      expect(find.text('Nova versão disponível'), findsOneWidget);
      await t.tap(find.text('Depois'));
      await t.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsNothing);
      expect(_estado(t).atualizacao, isNull);
    });

    testWidgets('fora do executável final não verifica sozinho', (t) async {
      // atualizador.py:26-28 (pode_atualizar): só o exe empacotado verifica
      final s = ServicosFalsos()..infoAtualizacao = info;
      await montarApp(t, servicos: s);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(s.chamadas, isNot(contains('verificarAtualizacao()')));
      expect(find.text('Nova versão disponível'), findsNothing);
    });

    testWidgets('sem versão nova ou com erro não mostra nada', (t) async {
      final s = ServicosFalsos()..erros['verificarAtualizacao'] = Offline();
      await montarApp(t, servicos: s, verificarAtualizacao: true);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('verificarAtualizacao()'));
      expect(find.text('Nova versão disponível'), findsNothing);
      expect(find.textContaining('Não foi possível verificar'), findsNothing);
    });
  });

  testWidgets('tocar nas abas troca a tela', (t) async {
    await montarApp(t, tamanho: _pequeno);
    expect(_estado(t).aba, Aba.apuracao);
    await t.tap(_naBarra('Radar'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.radar);
    expect(find.byType(TelaRadar), findsOneWidget);
    expect(find.text('Radar (em construção)'), findsNothing);
    await t.tap(_naBarra('Notícias'));
    await t.pumpAndSettle();
    expect(find.byType(TelaNoticias), findsOneWidget);
    expect(find.text('Notícias (em construção)'), findsNothing);
  });

  testWidgets('tocar na barra lateral troca a tela', (t) async {
    await montarApp(t);
    await t.tap(_naLateral('Caixa'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
    expect(find.byType(TelaCaixa), findsOneWidget);
    expect(find.text('Caixa (em construção)'), findsNothing);
  });

  testWidgets('o botão de saldo leva ao Caixa', (t) async {
    await montarApp(t);
    await t.tap(find.textContaining('Saldo: '));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
  });

  testWidgets('o ícone de sincronização leva à Conta no celular', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.tap(find.byTooltip('○ Google não conectado'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.conta);
  });

  testWidgets('deslizar troca de aba no celular', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
    expect(find.byType(TelaCaixa), findsOneWidget);
    expect(find.text('Caixa (em construção)'), findsNothing);
  });

  testWidgets('no PC deslizar não troca de aba', (t) async {
    await montarApp(t);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.apuracao);
  });

  testWidgets('selo de não lidas some na aba Notícias', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s, tamanho: _pequeno);
    s.eventosFalsos.add(
      EventoNoticias(
        const VisaoNoticias(
          itens: [],
          detalhes: {},
          naoLidas: 4,
          hora: 0,
          lidasAte: 0,
          erros: {},
          rodando: false,
          radar: [],
        ),
        const [],
      ),
    );
    await t.pump();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('4')),
      findsOneWidget,
    );
    await t.tap(_naBarra('Notícias'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('4')),
      findsNothing,
    );
  });

  testWidgets('selo de relatório novo conta e some na aba Relatórios', (
    t,
  ) async {
    final s = ServicosFalsos()
      ..estadoConta = const EstadoConta(email: 'a@b.com')
      ..visaoRelatorios = VisaoRelatorios(
        itens: const [],
        hoje: '2026-11-26',
        novos: const [
          ResumoRelatorio(
            nome: 'relatorio-abertura-2026-11-26.json',
            data: '2026-11-26',
          ),
          ResumoRelatorio(
            nome: 'relatorio-abertura-2026-11-25.json',
            data: '2026-11-25',
          ),
        ],
      );
    await montarApp(
      t,
      servicos: s,
      tamanho: _pequeno,
      conferirRelatorios: true,
    );
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('2')),
      findsOneWidget,
    );
    await t.tap(_naBarra('Relatórios'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('2')),
      findsNothing,
    );
  });

  testWidgets('aviso de config ilegível na casca', (t) async {
    final s = ServicosFalsos()
      ..estadoInicial = const EstadoInicial(
        mesInicial: '2026-10',
        mesesComDados: ['2026-10'],
        preferencias: Preferencias(),
        erroConfig: 'O arquivo config.json está ilegível; nada foi alterado.',
      );
    await montarApp(t, servicos: s);
    expect(
      find.textContaining('O arquivo config.json está ilegível'),
      findsOneWidget,
    );
    expect(find.textContaining('vazio ou corrompido'), findsOneWidget);
    expect(find.textContaining('nenhuma alteração é gravada'), findsOneWidget);
  });

  testWidgets('aviso vira diálogo no PC', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s);
    s.eventosFalsos.add(const EventoAviso('Erro inesperado', 'algo falhou'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('algo falhou'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_estado(t).avisos, isEmpty);
  });

  testWidgets('aviso vira SnackBar no celular', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s, tamanho: _pequeno);
    s.eventosFalsos.add(const EventoAviso('Erro inesperado', 'algo falhou'));
    await t.pump();
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('algo falhou'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'redimensionar atravessando 840 mantém a aba e o estado da tela',
    (t) async {
      await montarApp(t, tela: Casca(telaDaAba: _Contador.new));
      await t.tap(_naLateral('Radar'));
      await t.pumpAndSettle();
      await t.tap(find.text('radar: 0'));
      await t.pump();
      expect(find.text('radar: 1'), findsOneWidget);

      t.view.physicalSize = _pequeno;
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(_estado(t).aba, Aba.radar);
      expect(find.text('radar: 1'), findsOneWidget);

      t.view.physicalSize = const Size(1366, 768);
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(_estado(t).aba, Aba.radar);
      expect(find.text('radar: 1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('morte do isolate mostra a faixa de serviços encerrados', (
    t,
  ) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s);
    expect(find.textContaining('foram encerrados'), findsNothing);
    await s.eventosFalsos.close();
    await t.pump();
    await t.pump();
    expect(
      find.text(
        'Os serviços do app foram encerrados. Feche e abra o app de novo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mostra o carregamento até o estado inicial chegar', (t) async {
    final s = _Lento();
    await montarApp(t, servicos: s, tema: TemaVisual.terminal);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    s.liberar.complete();
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('falha ao iniciar mostra o motivo e Tentar de novo', (t) async {
    final s = ServicosFalsos()..erros['iniciar'] = StateError('quebrou');
    await montarApp(t, servicos: s);
    expect(find.textContaining('quebrou'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    s.erros.remove('iniciar');
    await t.tap(find.text('Tentar de novo'));
    await t.pump();
    await t.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}

/// `carregarAmigo` só termina quando o teste liberar.
class _AmigoLento extends ServicosFalsos {
  final Completer<void> liberar = Completer<void>();

  @override
  Future<ResumoAmigo> carregarAmigo(String email) async {
    await liberar.future;
    return super.carregarAmigo(email);
  }
}

/// `iniciar` só termina quando o teste liberar.
class _Lento extends ServicosFalsos {
  final Completer<void> liberar = Completer<void>();

  @override
  Future<EstadoInicial> iniciar() async {
    await liberar.future;
    return super.iniciar();
  }
}
