import 'package:calculadoradarf/app/componentes/controles.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

const _pc = Size(1366, 768);
const _celular = Size(360, 800);
const _temas = [TemaVisual.terminal, TemaVisual.claro, TemaVisual.moderno];

void main() {
  group('altura', () {
    final casos = <String, (Widget Function(), Type)>{
      'BotaoPrincipal': (
        () =>
            BotaoPrincipal(icone: Icons.add, rotulo: 'Novo', onPressed: () {}),
        BotaoPrincipal,
      ),
      'BotaoSecundario': (
        () => BotaoSecundario(
          icone: Icons.add,
          rotulo: 'Outro',
          onPressed: () {},
        ),
        BotaoSecundario,
      ),
      'Segmentado': (
        () => Segmentado<int>(
          opcoes: const [(1, 'Um'), (2, 'Dois')],
          valor: 1,
          aoMudar: (_) {},
        ),
        Segmentado<int>,
      ),
      'CampoBusca': (
        () => SizedBox(
          width: 240,
          child: CampoBusca(
            controller: TextEditingController(),
            dica: 'Buscar',
          ),
        ),
        CampoBusca,
      ),
      'BotaoMenu': (
        () => BotaoMenu<String>(
          icone: Icons.filter_list,
          rotulo: 'Filtro',
          itens: const [('a', 'A')],
          aoEscolher: (_) {},
        ),
        BotaoMenu<String>,
      ),
      'SeletorCaixa': (
        () => SizedBox(
          width: 200,
          child: SeletorCaixa<String>(
            rotulo: 'Tipo',
            valor: 'a',
            itens: const [('a', 'A'), ('b', 'B')],
            aoMudar: (_) {},
          ),
        ),
        SeletorCaixa<String>,
      ),
    };
    for (final tema in _temas) {
      for (final e in casos.entries) {
        for (final (tamanho, h) in [(_pc, 40.0), (_celular, 48.0)]) {
          testWidgets('${e.key} tem $h px (${tema.chave}, ${tamanho.width})', (
            t,
          ) async {
            await montarComponente(
              t,
              e.value.$1(),
              tema: tema,
              tamanho: tamanho,
            );
            expect(t.getSize(find.byType(e.value.$2)).height, h);
          });
        }
      }
    }
  });

  testWidgets('BotaoIcone expõe tooltip e rótulo semântico', (t) async {
    final h = t.ensureSemantics();
    await montarComponente(
      t,
      BotaoIcone(icone: Icons.delete, tooltip: 'Excluir', onPressed: () {}),
    );
    expect(find.byTooltip('Excluir'), findsOneWidget);
    expect(find.bySemanticsLabel('Excluir'), findsOneWidget);
    h.dispose();
  });

  for (final tema in _temas) {
    testWidgets('BotaoIcone destrutivo usa queda (${tema.chave})', (t) async {
      late Color queda;
      await montarComponente(
        t,
        Builder(
          builder: (context) {
            queda = CoresApp.de(context).queda;
            return BotaoIcone(
              icone: Icons.delete,
              tooltip: 'Excluir',
              destrutivo: true,
              onPressed: () {},
            );
          },
        ),
        tema: tema,
      );
      expect(t.widget<Icon>(find.byIcon(Icons.delete)).color, queda);
    });
  }

  testWidgets('BotaoIcone marcado desenha o ponto', (t) async {
    await montarComponente(
      t,
      BotaoIcone(
        icone: Icons.filter_alt,
        tooltip: 'Filtros',
        marcado: true,
        onPressed: () {},
      ),
    );
    expect(find.byKey(const ValueKey('ponto-marcado')), findsOneWidget);
  });

  group('Segmentado', () {
    testWidgets('chama aoMudar com o valor tocado', (t) async {
      int? v;
      await montarComponente(
        t,
        Segmentado<int>(
          opcoes: const [(1, 'Um'), (2, 'Dois')],
          valor: 1,
          aoMudar: (x) => v = x,
        ),
      );
      await t.tap(find.text('Dois'));
      expect(v, 2);
    });
    testWidgets('compacto não mostra o check; normal mostra', (t) async {
      await montarComponente(
        t,
        Segmentado<int>(
          opcoes: const [(1, 'Um'), (2, 'Dois')],
          valor: 1,
          aoMudar: (_) {},
          compacto: true,
        ),
      );
      expect(find.byIcon(Icons.check), findsNothing);
      await montarComponente(
        t,
        Segmentado<int>(
          opcoes: const [(1, 'Um'), (2, 'Dois')],
          valor: 1,
          aoMudar: (_) {},
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
    testWidgets('chaveOpcao vai no texto', (t) async {
      await montarComponente(
        t,
        Segmentado<int>(
          opcoes: const [(1, 'Um')],
          valor: 1,
          aoMudar: (_) {},
          chaveOpcao: (v) => ValueKey('op$v'),
        ),
      );
      expect(find.byKey(const ValueKey('op1')), findsOneWidget);
    });
  });

  group('BotaoOrdenar', () {
    const campos = [('cad', 'Cadastro'), ('nome', 'Nome')];
    testWidgets('rótulo, trocar campo e inverter', (t) async {
      String? campo;
      var inverteu = false;
      await montarComponente(
        t,
        BotaoOrdenar<String>(
          campos: campos,
          campo: 'cad',
          aoCampo: (c) => campo = c,
          aoInverter: () => inverteu = true,
        ),
      );
      expect(find.text('Cadastro ↑'), findsOneWidget);
      await t.tap(find.text('Cadastro ↑'));
      await t.pumpAndSettle();
      await t.tap(find.text('Nome'));
      await t.pumpAndSettle();
      expect(campo, 'nome');
      await t.tap(find.text('Cadastro ↑'));
      await t.pumpAndSettle();
      await t.tap(find.text('Decrescente ↓'));
      await t.pumpAndSettle();
      expect(inverteu, isTrue);
    });
    testWidgets('desc mostra seta para baixo', (t) async {
      await montarComponente(
        t,
        BotaoOrdenar<String>(
          campos: campos,
          campo: 'cad',
          desc: true,
          aoCampo: (_) {},
          aoInverter: () {},
        ),
      );
      expect(find.text('Cadastro ↓'), findsOneWidget);
    });
    testWidgets('sem aoInverter: só o campo e sem item de inverter', (t) async {
      await montarComponente(
        t,
        BotaoOrdenar<String>(
          campos: const [('minha', 'Minha ordem'), ('nome', 'Nome')],
          campo: 'minha',
          aoCampo: (_) {},
        ),
      );
      expect(find.text('Minha ordem'), findsOneWidget);
      expect(find.textContaining('↑'), findsNothing);
      await t.tap(find.text('Minha ordem'));
      await t.pumpAndSettle();
      expect(find.text('Crescente ↑'), findsNothing);
      expect(find.text('Decrescente ↓'), findsNothing);
    });
    testWidgets('chaveItem e chaveInverter', (t) async {
      await montarComponente(
        t,
        BotaoOrdenar<String>(
          campos: campos,
          campo: 'cad',
          aoCampo: (_) {},
          aoInverter: () {},
          chaveItem: (c) => ValueKey('i-$c'),
          chaveInverter: const ValueKey('inv'),
        ),
      );
      await t.tap(find.text('Cadastro ↑'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('i-nome')), findsOneWidget);
      expect(find.byKey(const ValueKey('inv')), findsOneWidget);
    });
  });

  group('SeletorMes', () {
    Future<void> montar(
      WidgetTester t,
      String mes,
      String maximo,
      List<String> log,
    ) {
      return montarComponente(
        t,
        SeletorMes(
          mes: mes,
          maximo: maximo,
          aoMudar: log.add,
          aoAbrir: () => log.add('abrir'),
        ),
      );
    }

    testWidgets('no máximo, próximo desabilitado; anterior muda', (t) async {
      final log = <String>[];
      await montar(t, '2026-11', '2026-11', log);
      expect(find.text('11/2026'), findsOneWidget);
      final prox = t.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(IconButton),
        ),
      );
      expect(prox.onPressed, isNull);
      await t.tap(find.byTooltip('Mês anterior'));
      expect(log, ['2026-10']);
    });
    testWidgets('janeiro volta para dezembro', (t) async {
      final log = <String>[];
      await montar(t, '2026-01', '2026-11', log);
      await t.tap(find.byTooltip('Mês anterior'));
      expect(log, ['2025-12']);
    });
    testWidgets('próximo avança e dezembro vira janeiro', (t) async {
      final log = <String>[];
      await montar(t, '2025-12', '2026-11', log);
      await t.tap(find.byTooltip('Próximo mês'));
      expect(log, ['2026-01']);
    });
    testWidgets('tocar no centro abre', (t) async {
      final log = <String>[];
      await montar(t, '2026-11', '2026-11', log);
      await t.tap(find.text('11/2026'));
      expect(log, ['abrir']);
    });
  });

  group('CampoBusca', () {
    testWidgets('digitar chama aoMudar e limpar zera', (t) async {
      final c = TextEditingController();
      final log = <String>[];
      await montarComponente(
        t,
        SizedBox(
          width: 240,
          child: CampoBusca(controller: c, dica: 'Buscar', aoMudar: log.add),
        ),
      );
      expect(find.byTooltip('Limpar'), findsNothing);
      await t.enterText(find.byType(TextField), 'abc');
      await t.pump();
      expect(log, ['abc']);
      await t.tap(find.byTooltip('Limpar'));
      await t.pump();
      expect(c.text, '');
      expect(log.last, '');
    });
  });

  group('SeletorCaixa', () {
    testWidgets('aoMudar null fica desabilitado', (t) async {
      await montarComponente(
        t,
        const SizedBox(
          width: 200,
          child: SeletorCaixa<String>(
            rotulo: 'Tipo',
            valor: 'a',
            itens: [('a', 'A'), ('b', 'B')],
          ),
        ),
      );
      expect(
        t
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration
            .enabled,
        isFalse,
      );
    });
    testWidgets('escolher chama aoMudar', (t) async {
      String? v;
      await montarComponente(
        t,
        SizedBox(
          width: 200,
          child: SeletorCaixa<String>(
            rotulo: 'Tipo',
            valor: 'a',
            itens: const [('a', 'A'), ('b', 'B')],
            aoMudar: (x) => v = x,
          ),
        ),
      );
      await t.tap(find.text('A'));
      await t.pumpAndSettle();
      await t.tap(find.text('B'));
      await t.pumpAndSettle();
      expect(v, 'b');
    });
  });

  testWidgets('BotaoMenu escolhe item e marca o atual', (t) async {
    String? v;
    await montarComponente(
      t,
      BotaoMenu<String>(
        icone: Icons.filter_list,
        rotulo: 'Filtro',
        itens: const [('a', 'Alfa'), ('b', 'Beta')],
        marcado: 'a',
        aoEscolher: (x) => v = x,
      ),
    );
    await t.tap(find.text('Filtro'));
    await t.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    expect(find.byIcon(Icons.check), findsOneWidget);
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(v, 'b');
  });

  testWidgets('Selo e LegendaPonto mostram o texto', (t) async {
    await montarComponente(
      t,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Selo(texto: 'Alta', cor: Colors.green, ponto: true),
          LegendaPonto(texto: 'Compra', cor: Colors.blue),
        ],
      ),
    );
    expect(find.text('Alta'), findsOneWidget);
    expect(find.text('Compra'), findsOneWidget);
  });
}
