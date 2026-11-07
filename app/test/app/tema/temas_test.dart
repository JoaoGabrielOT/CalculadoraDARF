import 'dart:async';

import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/app/tema/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'o ✓ do chip selecionado usa o texto do chip ativo, em todos os temas',
    () {
      for (final v in [
        TemaVisual.terminal,
        TemaVisual.claro,
        TemaVisual.moderno,
      ]) {
        final th = temaDe(v);
        expect(
          th.chipTheme.checkmarkColor,
          th.extension<CoresApp>()!.chipAtivoTexto,
          reason: v.name,
        );
      }
    },
  );

  test('cores do spec e dos mockups', () {
    final t = temaDe(TemaVisual.terminal).extension<CoresApp>()!;
    expect(t.fundo, const Color(0xFF0D1117));
    expect(t.alta, const Color(0xFF3FB950));
    expect(t.queda, const Color(0xFFF85149));
    final c = temaDe(TemaVisual.claro).extension<CoresApp>()!;
    expect(c.fundo, const Color(0xFFF6F7FB));
    expect(c.cartao, const Color(0xFFFFFFFF));
    expect(
      (c.alta, c.seloAltaFundo),
      (const Color(0xFF14833B), const Color(0xFFE3F6EA)),
    );
    expect(
      (c.queda, c.seloQuedaFundo),
      (const Color(0xFFC62828), const Color(0xFFFDE8E8)),
    );
    final m = temaDe(TemaVisual.moderno).extension<CoresApp>()!;
    expect((m.fundoGradiente as LinearGradient).colors, [
      const Color(0xFF151A2E),
      const Color(0xFF0B0E1A),
    ]);
    expect((m.destaqueGradiente as LinearGradient).colors, [
      const Color(0xFF6C5CE7),
      const Color(0xFF00B894),
    ]);
    expect(
      (m.alta, m.queda),
      (const Color(0xFF55EFC4), const Color(0xFFFF7675)),
    );
  });

  test('demais cores e medidas dos mockups', () {
    final t = temaDe(TemaVisual.terminal).extension<CoresApp>()!;
    expect(t.cartao, const Color(0xFF161B22));
    expect(t.cartaoBorda, const Color(0xFF30363D));
    expect(t.linha, const Color(0xFF21262D));
    expect(t.texto, const Color(0xFFE6EDF3));
    expect(t.textoSuave, const Color(0xFF8B949E));
    expect(t.chipAtivoBorda, const Color(0xFF2EA043));
    expect(t.chipAtivoTexto, const Color(0xFF3FB950));
    expect(t.destaque, const Color(0xFF2EA043));
    expect(t.aviso, const Color(0xFFD29922));
    expect(t.raioCartao, 6);
    expect(t.sombraCartao, isEmpty);
    expect(t.seloAltaFundo.a, 0);
    expect(t.seloQuedaFundo.a, 0);
    expect(t.densa, isTrue);
    final c = temaDe(TemaVisual.claro).extension<CoresApp>()!;
    expect(c.texto, const Color(0xFF1B1F2A));
    expect(c.chipAtivoFundo, const Color(0xFF1B1F2A));
    expect(c.chipAtivoTexto, const Color(0xFFFFFFFF));
    expect(c.raioCartao, 16);
    expect(c.sombraCartao, hasLength(1));
    expect(c.densa, isFalse);
    final m = temaDe(TemaVisual.moderno).extension<CoresApp>()!;
    expect(m.texto, const Color(0xFFF1F3FB));
    expect(m.navAtivo, const Color(0xFFA29BFE));
    expect(m.aviso, const Color(0xFFFDCB6E));
    expect(m.raioCartao, 18);
    expect(m.destaque, const Color(0xFF6C5CE7));
  });

  test('densidade compacta só no Terminal, Material 3 e Roboto', () {
    expect(temaDe(TemaVisual.terminal).visualDensity, VisualDensity.compact);
    expect(
      temaDe(TemaVisual.claro).visualDensity,
      isNot(VisualDensity.compact),
    );
    expect(temaDe(TemaVisual.moderno).useMaterial3, isTrue);
    expect(temaDe(TemaVisual.claro).textTheme.bodyMedium?.fontFamily, 'Roboto');
  });

  test('automático segue o sistema', () {
    expect(
      resolverTema(TemaVisual.automatico, Brightness.light),
      TemaVisual.claro,
    );
    expect(
      resolverTema(TemaVisual.automatico, Brightness.dark),
      TemaVisual.moderno,
    );
    expect(
      resolverTema(TemaVisual.terminal, Brightness.light),
      TemaVisual.terminal,
    );
  });

  test('chave desconhecida vira automático', () {
    expect(TemaVisual.daChave(null), TemaVisual.automatico);
    expect(TemaVisual.daChave('Dark'), TemaVisual.automatico);
    expect(TemaVisual.daChave('moderno'), TemaVisual.moderno);
    expect(TemaVisual.moderno.rotulo, 'Moderno');
    expect(TemaVisual.automatico.rotulo, 'Automático');
    expect(TemaVisual.terminal.chave, 'terminal');
  });

  testWidgets('corVariacao: alta, queda e neutro', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDe(TemaVisual.claro),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final cores = CoresApp.de(ctx);
    expect(corVariacao(ctx, 1.5), cores.alta);
    expect(corVariacao(ctx, -0.1), cores.queda);
    expect(corVariacao(ctx, 0), cores.textoSuave);
    expect(corVariacao(ctx, null), cores.textoSuave);
  });

  test('temaDe(automatico) cai no Claro sem assert', () {
    final t = temaDe(TemaVisual.automatico).extension<CoresApp>()!;
    expect(t.fundo, const Color(0xFFF6F7FB));
  });

  group('contraste WCAG AA (4,5:1 em texto normal)', () {
    double razao(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final claro = la > lb ? la : lb;
      final escuro = la > lb ? lb : la;
      return (claro + 0.05) / (escuro + 0.05);
    }

    for (final tema in [
      TemaVisual.terminal,
      TemaVisual.claro,
      TemaVisual.moderno,
    ]) {
      test(tema.rotulo, () {
        final th = temaDe(tema);
        final c = th.extension<CoresApp>()!;
        // Fundos em que o texto aparece: fundo, cartão sobre o fundo e, no
        // Moderno, o cartão sobre o ponto mais claro do gradiente.
        final base = <Color>[c.fundo];
        final grad = c.fundoGradiente;
        if (grad is LinearGradient) base.addAll(grad.colors);
        final fundos = [
          for (final b in base) ...[b, Color.alphaBlend(c.cartao, b)],
          th.colorScheme.surface,
          th.colorScheme.surfaceContainerLowest,
          th.colorScheme.surfaceContainerLow,
          th.colorScheme.surfaceContainer,
          th.colorScheme.surfaceContainerHigh,
          th.colorScheme.surfaceContainerHighest,
        ];
        final pares = <String, Color>{
          'texto': c.texto,
          'textoSuave': c.textoSuave,
          'aviso': c.aviso,
          'alta': c.alta,
          'queda': c.queda,
        };
        for (final f in fundos) {
          pares.forEach((nome, cor) {
            expect(
              razao(cor, f),
              greaterThanOrEqualTo(4.5),
              reason: '$nome sobre $f',
            );
          });
        }
        final chip = Color.alphaBlend(c.chipFundo, c.fundo);
        expect(razao(c.chipTexto, chip), greaterThanOrEqualTo(4.5));
        expect(
          razao(c.navAtivo, th.colorScheme.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          razao(th.colorScheme.onPrimary, c.destaque),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          razao(c.chipAtivoTexto, c.chipAtivoFundo),
          greaterThanOrEqualTo(4.5),
        );
        // Borda de campo/controle: 3:1 sobre todas as superfícies (WCAG 1.4.11).
        for (final f in fundos) {
          expect(
            razao(c.bordaCampo, f),
            greaterThanOrEqualTo(3),
            reason: 'borda sobre $f',
          );
        }
        expect(th.inputDecorationTheme.enabledBorder, isNotNull);
        expect(
          (th.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
              .borderSide
              .color,
          c.bordaCampo,
        );
        expect(th.colorScheme.outline, c.bordaCampo);
        // Indicador do item selecionado da navegação: visível e com texto legível.
        final ind = th.navigationBarTheme.indicatorColor!;
        expect(ind.a, greaterThan(0));
        expect(
          razao(
            c.navAtivo,
            Color.alphaBlend(ind, th.colorScheme.surfaceContainerLow),
          ),
          greaterThanOrEqualTo(4.5),
        );
        // Fixados no spec e fora desta checagem: selo de alta do Claro
        // (#14833b sobre #e3f6ea, 4,3:1). O degradê destaqueGradiente do Moderno
        // não está em uso nos componentes do tema (branco sobre #00b894 não passa).
        if (tema != TemaVisual.claro) {
          expect(
            razao(c.alta, Color.alphaBlend(c.seloAltaFundo, c.fundo)),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          razao(c.queda, Color.alphaBlend(c.seloQuedaFundo, c.fundo)),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('componentes usam as cores do tema', () {
    for (final tema in [
      TemaVisual.terminal,
      TemaVisual.claro,
      TemaVisual.moderno,
    ]) {
      testWidgets(tema.rotulo, (tester) async {
        final th = temaDe(tema);
        final c = th.extension<CoresApp>()!;
        await tester.pumpWidget(
          MaterialApp(
            theme: th,
            home: Scaffold(
              body: Column(
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Nome'),
                  ),
                  NavigationBar(
                    selectedIndex: 0,
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.home), label: 'A'),
                      NavigationDestination(icon: Icon(Icons.list), label: 'B'),
                    ],
                  ),
                  SizedBox(
                    height: 200,
                    child: NavigationRail(
                      selectedIndex: 0,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home),
                          label: Text('A'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.list),
                          label: Text('B'),
                        ),
                      ],
                    ),
                  ),
                  DataTable(
                    columns: const [DataColumn(label: Text('Col'))],
                    rows: const [
                      DataRow(cells: [DataCell(Text('Valor'))]),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        Color? corDoTexto(String t) =>
            DefaultTextStyle.of(tester.element(find.text(t))).style.color;
        expect(corDoTexto('Col'), c.textoSuave);
        expect(corDoTexto('Valor'), c.texto);
        final barra = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(NavigationBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(barra.color, th.colorScheme.surfaceContainerLow);
        expect(barra.color!.a, 1);
        final rail = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(NavigationRail),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(rail.color, th.colorScheme.surfaceContainerLow);

        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(Scaffold)),
            builder: (_) => const AlertDialog(title: Text('Titulo')),
          ),
        );
        await tester.pumpAndSettle();
        final dialogo = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(dialogo.color, th.colorScheme.surfaceContainerHigh);
        expect(dialogo.color!.a, 1);
        expect(th.colorScheme.surface.a, 1);
        expect(th.colorScheme.surfaceTint, Colors.transparent);
      });
    }
  });
}
