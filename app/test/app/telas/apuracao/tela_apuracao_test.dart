import 'dart:async';

import 'package:calculadoradarf/app/componentes/campo_data.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 768);
const _celular = Size(360, 800);

/// Apuração com valores redondos para conferir os textos.
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

Future<ServicosFalsos> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  VoidCallback? aoAbrirMetas,
}) async {
  final s = servicos ?? ServicosFalsos();
  await montarApp(
    t,
    servicos: s,
    tamanho: tamanho,
    tela: TelaApuracao(aoAbrirMetas: aoAbrirMetas),
  );
  await t.pumpAndSettle();
  return s;
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaApuracao)), listen: false);

Finder get _botaoFechar => find.widgetWithText(FilledButton, 'Fechar mês');

bool _habilitado(Finder f, WidgetTester t) {
  final w = t.widget(f);
  if (w is FilledButton) return w.onPressed != null;
  if (w is OutlinedButton) return w.onPressed != null;
  throw StateError('botão inesperado: $w');
}

Finder _noDialogo(String texto) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(texto));

int _chamadasA(ServicosFalsos s, String prefixo) =>
    s.chamadas.where((c) => c.startsWith(prefixo)).length;

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets('mostra KPIs e detalhamento com os textos do Python', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = _visaoComValores();
    await _montar(t, servicos: s);

    expect(find.text('Lucro bruto'), findsOneWidget);
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
    expect(find.text('0 vendas no mês'), findsOneWidget);
    expect(find.text('Lucro líquido'), findsOneWidget);
    expect(find.text('R\$ 1.200,00'), findsOneWidget);
    expect(find.text('após taxas e impostos'), findsOneWidget);
    expect(find.text('R\$ 20,50'), findsWidgets);
    expect(find.text('IRRF já retido: R\$ 1,50'), findsOneWidget);
    expect(find.text('Total da DARF'), findsOneWidget);
    expect(
      find.text('Código 6015 · vence no último dia útil de 11/2026'),
      findsNWidgets(2),
    );

    expect(find.text('Detalhamento'), findsOneWidget);
    expect(find.text('LIMITE DE ISENÇÃO (AÇÕES · SWING)'), findsOneWidget);
    expect(find.text('R\$ 15.000,00  de  R\$ 20.000,00'), findsOneWidget);
    expect(find.text('Isento de IR em swing trade de ações'), findsOneWidget);
    expect(find.text('Taxas B3 + corretagem'), findsOneWidget);
    expect(find.text('R\$ 12,34'), findsOneWidget);
    expect(find.text('Imposto swing trade (15%)'), findsOneWidget);
    expect(find.text('Imposto day trade (20%)'), findsOneWidget);
    expect(find.text('IRRF retido (dedo-duro)'), findsOneWidget);
    expect(find.text('- R\$ 1,50'), findsOneWidget);
    expect(find.text('DARF de meses anteriores'), findsOneWidget);
    expect(find.text('R\$ 5,00'), findsOneWidget);
    expect(find.text('Total a pagar'), findsOneWidget);
    expect(find.text('R\$ 30,00'), findsNWidgets(2));
    expect(
      find.text(
        'Código da DARF: 6015\n'
        'Vencimento: último dia útil do mês seguinte\n'
        'Taxas B3: 0,030% swing · 0,023% day trade',
      ),
      findsOneWidget,
    );
  });

  group('custo médio', () {
    VisaoMes visao({List<String> inconsistentes = const []}) => VisaoMes(
      mes: '2026-10',
      dados: mesAbertoExemplo()..metodo = metodoCustoMedio,
      apuracao: Apuracao(
        ops: [],
        vendasAcoesSt: 0,
        isento: true,
        bruto: 0,
        custos: 12.34,
        impSt: 0,
        impDt: 0,
        impostoTotal: 0,
        irrf: 0,
        lucroLiquido: 0,
        darfMes: 0,
        darfAnterior: 0,
        darf: 0,
        metodo: metodoCustoMedio,
        inconsistentes: inconsistentes,
      ),
    );

    testWidgets('inconsistência bloqueia o fechamento e aparece na tela', (
      t,
    ) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visao(inconsistentes: ['PETR4', 'VALE3']);
      await _montar(t, servicos: s);
      expect(
        find.text(
          'Saldo inconsistente em PETR4: confira as vendas\n'
          'Saldo inconsistente em VALE3: confira as vendas',
        ),
        findsOneWidget,
      );
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(find.text('Não foi possível fechar o mês'), findsOneWidget);
      expect(
        _noDialogo(
          'O mês não pode ser fechado com saldo inconsistente.\n\n'
          'Saldo inconsistente em PETR4: confira as vendas\n'
          'Saldo inconsistente em VALE3: confira as vendas',
        ),
        findsOneWidget,
      );
      expect(find.text('Fechar 10/2026'), findsNothing);
      expect(_chamadasA(s, 'prepararFechamento'), 0);
      expect(_chamadasA(s, 'fecharMes'), 0);
    });

    testWidgets('rótulo das taxas sem as compras da posição', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visao();
      await _montar(t, servicos: s);
      expect(find.text('Taxas B3 + corretagem'), findsNothing);
      expect(
        find.text('Taxas B3 + corretagem (vendas e day trade)'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'No custo médio, as taxas e a corretagem das compras que ficam na '
          'posição entram no custo médio.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Saldo inconsistente'), findsNothing);
    });
  });

  testWidgets('acima do limite e sem IRRF: textos de aviso e R\$ 0,00', (
    t,
  ) async {
    final s = ServicosFalsos();
    final base = _visaoComValores();
    s.visoes['2026-10'] = VisaoMes(
      mes: base.mes,
      dados: base.dados,
      apuracao: Apuracao(
        ops: [],
        vendasAcoesSt: 25000,
        isento: false,
        bruto: 0,
        custos: 0,
        impSt: 0,
        impDt: 0,
        impostoTotal: 0,
        irrf: 0,
        lucroLiquido: 0,
        darfMes: 0,
        darfAnterior: 0,
        darf: 0,
      ),
    );
    await _montar(t, servicos: s);
    expect(
      find.text('Acima do limite · lucro tributado em 15%'),
      findsOneWidget,
    );
    expect(find.text('Nada a pagar neste mês'), findsNWidgets(2));
    expect(find.text('- R\$ 0,00'), findsNothing);
  });

  testWidgets('selo e botões por estado: aberto, fechado, amigo', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s);
    expect(find.text('● Aberto'), findsOneWidget);
    expect(find.text('10/2026  ▾'), findsOneWidget);
    expect(_habilitado(_botaoFechar, t), isTrue);
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, 'Atualizar'), t),
      isFalse,
    );
  });

  testWidgets('selo e botões: mês fechado', (t) async {
    await _montar(t, servicos: ServicosFalsos()..mesAberto = '2026-09');
    expect(find.text('Fechado'), findsOneWidget);
    expect(_habilitado(_botaoFechar, t), isFalse);
  });

  testWidgets('selo e botões: visão de amigo', (t) async {
    final amigo = ServicosFalsos();
    await _montar(t, servicos: amigo);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(find.text('Somente leitura'), findsOneWidget);
    expect(_habilitado(_botaoFechar, t), isFalse);
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, 'Atualizar'), t),
      isTrue,
    );
    expect(amigo.chamadas, contains('carregarMes(2026-10, ana@exemplo.com)'));
  });

  testWidgets('trocar o mês pelo seletor recarrega; Mês atual volta', (
    t,
  ) async {
    final s = await _montar(t);
    await t.tap(find.text('10/2026  ▾'));
    await t.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('carregarMes(2026-09, null)'));
    expect(find.text('09/2026  ▾'), findsOneWidget);
    expect(find.text('Fechado'), findsOneWidget);

    await t.tap(find.text('09/2026  ▾'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mês atual'));
    await t.pumpAndSettle();
    expect(find.text('10/2026  ▾'), findsOneWidget);
    expect(find.text('● Aberto'), findsOneWidget);
  });

  group('Fechar mês', () {
    Meta meta(String id, String ticker, {String? erro, double? preco}) => Meta(
      id: id,
      ticker: ticker,
      loteId: 'L1',
      qtd: 60,
      precoAlvo: 40,
      criadaEm: '2026-10-21T11:00:00-03:00',
      ultimoErro: erro,
      execucao: preco == null ? null : {'preco_usado': preco},
    );

    testWidgets('lê as metas ativas na hora, não o valor em cache', (t) async {
      final s = ServicosFalsos();
      await _montar(t, servicos: s);
      expect(_estado(t).metasAtivas, 0);
      s.metasAtivasFalsas = 1; // outro aparelho criou uma meta
      s.preparo = PreparoFechamento()..bloqueio = 'Yahoo fora do ar.';
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(_chamadasA(s, 'prepararFechamento'), 1);
      expect(find.text('Yahoo fora do ar.'), findsOneWidget);
    });

    testWidgets('falha ao ler as metas bloqueia o fechamento', (t) async {
      final s = ServicosFalsos();
      await _montar(t, servicos: s);
      s.erros['metas'] = ErroValidacao('config ilegível.');
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(find.text('Não foi possível fechar o mês'), findsOneWidget);
      expect(
        find.text(
          'Falha ao verificar as metas antes de fechar: config ilegível.',
        ),
        findsOneWidget,
      );
      expect(find.text('Fechar 10/2026'), findsNothing);
    });

    testWidgets(
      'recarregar falhando depois das metas executadas mostra o erro',
      (t) async {
        final s = ServicosFalsos()
          ..metasAtivasFalsas = 1
          ..preparo = (PreparoFechamento()
            ..executadas.add(meta('M1', 'PETR4')));
        await _montar(t, servicos: s);
        s.carregarMesFn = (mes, amigo) =>
            Future.error(ErroValidacao('Mês ilegível depois da meta.'));
        await t.tap(_botaoFechar);
        await t.pumpAndSettle();
        expect(find.text('Não foi possível carregar'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Mês ilegível depois da meta.'),
          ),
          findsOneWidget,
        );
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(find.text('Fechar 10/2026'), findsNothing);
        expect(_chamadasA(s, 'fecharMes'), 0);
      },
    );

    testWidgets(
      'durante a verificação mostra o aviso e o progresso, e um segundo toque '
      'não repete a chamada',
      (t) async {
        final pendente = Completer<PreparoFechamento>();
        final s = ServicosFalsos()
          ..metasAtivasFalsas = 1
          ..preparoFn = (_) => pendente.future;
        await _montar(t, servicos: s);
        expect(find.byKey(const ValueKey('progresso-tela')), findsNothing);
        await t.tap(_botaoFechar);
        await t.pump();
        expect(
          find.text('Verificando as metas antes de fechar…'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('progresso-tela')), findsOneWidget);
        expect(_habilitado(_botaoFechar, t), isFalse);
        // o controle também recusa chamadas repetidas, sem depender do botão
        final contexto = t.element(find.text('Lucro bruto'));
        final controle = Provider.of<ControleApuracao>(contexto, listen: false);
        await controle.fecharMes(contexto); // recusada na hora
        await controle.fecharMes(contexto);
        await t.pump();
        expect(_chamadasA(s, 'prepararFechamento'), 1);
        pendente.complete(PreparoFechamento()..bloqueio = 'Fim.');
        await t.pumpAndSettle();
        expect(
          find.text('Verificando as metas antes de fechar…'),
          findsNothing,
        );
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('progresso-tela')), findsNothing);
      },
    );

    testWidgets('compacto: aviso e progresso durante a verificação', (t) async {
      final pendente = Completer<PreparoFechamento>();
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 1
        ..preparoFn = (_) => pendente.future;
      await _montar(t, servicos: s, tamanho: _celular);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Fechar mês'));
      await t.pump();
      expect(
        find.text('Verificando as metas antes de fechar…'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('progresso-tela')), findsOneWidget);
      pendente.complete(PreparoFechamento()..bloqueio = 'Fim.');
      await t.pumpAndSettle();
    });

    testWidgets('sem metas ativas vai direto à confirmação e fecha', (t) async {
      final s = await _montar(t);
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(_chamadasA(s, 'prepararFechamento'), 0);
      expect(find.text('Fechar 10/2026'), findsOneWidget);
      expect(
        find.textContaining(
          'Depois de fechado, o mês não pode ser alterado.\n\n'
          'Total da DARF: ',
        ),
        findsOneWidget,
      );
      await t.tap(_noDialogo('Fechar mês'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('fecharMes(2026-10)'));
      expect(find.text('Mês fechado'), findsOneWidget);
      expect(find.text('Não há DARF a pagar.'), findsOneWidget);
    });

    group('pela venda, com o mês aberto já terminado', () {
      Future<ServicosFalsos> abrirVenda(
        WidgetTester t, {
        ServicosFalsos? servicos,
      }) async {
        ambiente = Ambiente.fixo(hoje: '2026-11-08');
        final s = servicos ?? ServicosFalsos();
        s.visoes['2026-11'] = visaoExemplo(
          Mes(
            mes: '2026-11',
            lotes: [
              Lote(
                id: 'L1~2026-11',
                origem: 'L1',
                ticker: 'PETR4',
                tipo: 'Ação',
                dataCompra: '2026-10-05',
                qtd: 60,
                preco: 32.5,
              ),
            ],
          ),
        );
        await montarApp(
          t,
          servicos: s,
          tamanho: _pc,
          tela: const TelaApuracao(
            conteudo: listasApuracao,
            sliversCompactos: listasSliversApuracao,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(OutlinedButton, 'Registrar venda'));
        await t.pumpAndSettle();
        await t.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('PETR4'),
          ),
        );
        await t.pump();
        await t.tap(find.text('Fechar outubro/2026'));
        await t.pumpAndSettle();
        return s;
      }

      String? maximoDaData(WidgetTester t) =>
          t.widget<CampoData>(find.byType(CampoData)).maximo;

      testWidgets('mesma confirmação do Fechar mês; depois o formulário usa '
          'o novo mês aberto', (t) async {
        final s = await abrirVenda(t);
        expect(find.text('Fechar 10/2026'), findsOneWidget);
        s.mesAberto = '2026-11'; // o fechamento abre novembro
        await t.tap(_noDialogo('Fechar mês'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('fecharMes(2026-10)'));
        expect(find.text('Mês fechado'), findsOneWidget);
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(find.text('Registrar venda'), findsWidgets);
        expect(find.text('Mês 11/2026'), findsOneWidget);
        expect(maximoDaData(t), '2026-11-08');
      });

      testWidgets('se o mês inicial falhar depois de fechar, o formulário '
          'segue para o mês seguinte', (t) async {
        final s = await abrirVenda(t);
        s.erros['mesInicial'] = ErroValidacao('Sem disco.');
        await t.tap(_noDialogo('Fechar mês'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('fecharMes(2026-10)'));
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('carregarMes(2026-11, null)'));
        expect(find.text('Mês 11/2026'), findsOneWidget);
      });

      testWidgets('vendas das metas antes de fechar: cancelar a confirmação '
          'recarrega a visão do formulário', (t) async {
        final s = ServicosFalsos()
          ..metasAtivasFalsas = 1
          ..preparo = (PreparoFechamento()
            ..executadas.add(meta('M1', 'PETR4', preco: 40)));
        await abrirVenda(t, servicos: s);
        expect(find.text('Metas verificadas antes de fechar'), findsOneWidget);
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        final antes = _chamadasA(s, 'carregarMes(2026-10');
        await t.tap(_noDialogo('Cancelar'));
        await t.pumpAndSettle();
        expect(_chamadasA(s, 'fecharMes'), 0);
        expect(_chamadasA(s, 'carregarMes(2026-10'), antes + 1);
      });

      testWidgets('cancelar a confirmação não fecha nem muda o formulário', (
        t,
      ) async {
        final s = await abrirVenda(t);
        await t.tap(_noDialogo('Cancelar'));
        await t.pumpAndSettle();
        expect(_chamadasA(s, 'fecharMes'), 0);
        expect(find.text('Mês 10/2026'), findsOneWidget);
        expect(maximoDaData(t), '2026-10-31');
        expect(
          find.text('Para vender em novembro/2026, feche outubro/2026.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('cancelar a confirmação não fecha', (t) async {
      final s = await _montar(t);
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(_chamadasA(s, 'fecharMes'), 0);
    });

    testWidgets('bloqueio mostra Não foi possível fechar o mês', (t) async {
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 1
        ..preparo = (PreparoFechamento()..bloqueio = 'Yahoo fora do ar.');
      await _montar(t, servicos: s);
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(find.text('Não foi possível fechar o mês'), findsOneWidget);
      expect(find.text('Yahoo fora do ar.'), findsOneWidget);
      expect(find.text('Fechar 10/2026'), findsNothing);
      expect(_chamadasA(s, 'fecharMes'), 0);
    });

    testWidgets(
      'executadas e inválidas mostram Metas verificadas antes de fechar e '
      'depois pedem a confirmação, que fecha',
      (t) async {
        final s = ServicosFalsos()
          ..metasAtivasFalsas = 2
          ..preparo = (PreparoFechamento()
            ..executadas.add(meta('M1', 'PETR4', preco: 40))
            ..invalidas.add(meta('M2', 'VALE3', erro: 'Sem histórico.')));
        await _montar(t, servicos: s);
        await t.tap(_botaoFechar);
        await t.pumpAndSettle();
        expect(find.text('Metas verificadas antes de fechar'), findsOneWidget);
        expect(
          find.text(
            'PETR4: venda de 60 registrada pela meta a R\$ 40,00.\n'
            'VALE3: meta inválida. Sem histórico.',
          ),
          findsOneWidget,
        );
        // a tela foi recarregada para mostrar o que a meta vendeu
        expect(_chamadasA(s, 'carregarMes'), greaterThan(1));
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(find.text('Fechar 10/2026'), findsOneWidget);
        await t.tap(_noDialogo('Fechar mês'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('fecharMes(2026-10)'));
        expect(find.text('Mês fechado'), findsOneWidget);
      },
    );

    testWidgets('falha do preparo mostra o motivo e não fecha', (t) async {
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 1
        ..erros['prepararFechamento'] = ErroValidacao('Sem rede.');
      await _montar(t, servicos: s);
      await t.tap(_botaoFechar);
      await t.pumpAndSettle();
      expect(find.text('Não foi possível fechar o mês'), findsOneWidget);
      expect(
        find.text('Falha ao verificar as metas antes de fechar: Sem rede.'),
        findsOneWidget,
      );
      expect(find.text('Fechar 10/2026'), findsNothing);
    });

    testWidgets('trocar de mês durante a verificação descarta o resultado', (
      t,
    ) async {
      final pendente = Completer<PreparoFechamento>();
      final s = ServicosFalsos()
        ..metasAtivasFalsas = 1
        ..preparoFn = (_) => pendente.future;
      await _montar(t, servicos: s);
      await t.tap(_botaoFechar);
      await t.pump();
      // a tela segue viva durante a verificação
      _estado(t).trocarMes('2026-09');
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      pendente.complete(PreparoFechamento()..bloqueio = 'Tarde demais.');
      await t.pumpAndSettle();
      expect(find.text('Tarde demais.'), findsNothing);
      expect(find.text('Fechar 10/2026'), findsNothing);
    });
  });

  testWidgets('Visualizando amigo: subtítulo e Atualizar habilitado', (
    t,
  ) async {
    final s = ServicosFalsos();
    await montarApp(
      t,
      servicos: s,
      tela: Casca(
        telaDaAba: (a) =>
            a == Aba.apuracao ? const TelaApuracao() : const SizedBox(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Ações e BDRs · apuração mensal de IR'), findsOneWidget);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(
      find.text('Dados de ana@exemplo.com · somente leitura'),
      findsOneWidget,
    );
    final atualizar = find.widgetWithText(OutlinedButton, 'Atualizar');
    expect(_habilitado(atualizar, t), isTrue);
    final antes = _chamadasA(s, 'carregarAmigo');
    await t.tap(atualizar);
    await t.pumpAndSettle();
    expect(_chamadasA(s, 'carregarAmigo'), antes + 1);
  });

  testWidgets('Atualizar do amigo mostra os dados novos na tela', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(find.text('R\$ 1.234,56'), findsNothing);
    s.visoes['2026-10'] = _visaoComValores(amigo: 'ana@exemplo.com');
    await t.tap(find.widgetWithText(OutlinedButton, 'Atualizar'));
    await t.pumpAndSettle();
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
  });

  testWidgets('compacto: Atualizar só aparece com amigo e atualiza', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s, tamanho: _celular);
    expect(find.byTooltip('Atualizar'), findsNothing);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(find.byTooltip('Atualizar'), findsOneWidget);
    s.visoes['2026-10'] = _visaoComValores(amigo: 'ana@exemplo.com');
    await t.tap(find.byTooltip('Atualizar'));
    await t.pumpAndSettle();
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
  });

  testWidgets('o seletor Visualizando lista Meus dados e os amigos', (t) async {
    final s = ServicosFalsos()
      ..listaAmigos = [Amigo(email: 'ana@exemplo.com', desde: '2026-10-01')];
    await _montar(t, servicos: s);
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    expect(find.text('ana@exemplo.com'), findsOneWidget);
    await t.tap(find.text('ana@exemplo.com'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('carregarAmigo(ana@exemplo.com)'));
    expect(_estado(t).amigo, 'ana@exemplo.com');
  });

  testWidgets('mês ilegível mostra aviso e permite trocar de mês', (t) async {
    final s = ServicosFalsos();
    s.visoes['2026-10'] = visaoExemplo(
      mesVazio('2026-10'),
      erroLeitura: 'O mês 10/2026 está ilegível: quantidade inválida.',
    );
    await _montar(t, servicos: s);
    expect(
      find.text('O mês 10/2026 está ilegível: quantidade inválida.'),
      findsOneWidget,
    );
    expect(_habilitado(_botaoFechar, t), isFalse);
    await t.tap(find.text('10/2026  ▾'));
    await t.pumpAndSettle();
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(
      find.text('O mês 10/2026 está ilegível: quantidade inválida.'),
      findsNothing,
    );
    expect(find.text('Fechado'), findsOneWidget);
  });

  testWidgets('erro ao carregar o mês aparece e o seletor continua', (t) async {
    final s = ServicosFalsos()
      ..erros['carregarMes'] = ErroValidacao('Arquivo ilegível.');
    await _montar(t, servicos: s);
    expect(find.text('Arquivo ilegível.'), findsOneWidget);
    s.erros.clear();
    await t.tap(find.text('10/2026  ▾'));
    await t.pumpAndSettle();
    await t.tap(find.text('Set'));
    await t.pumpAndSettle();
    expect(find.text('Arquivo ilegível.'), findsNothing);
    expect(find.text('Fechado'), findsOneWidget);
  });

  testWidgets('versaoDados mudando recarrega a tela', (t) async {
    final s = await _montar(t);
    final antes = _chamadasA(s, 'carregarMes');
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(_chamadasA(s, 'carregarMes'), antes + 1);
  });

  testWidgets('resposta antiga de um recarregamento é descartada', (t) async {
    final s = await _montar(t);
    final respostas = <Completer<VisaoMes>>[];
    s.carregarMesFn = (mes, amigo) {
      final c = Completer<VisaoMes>();
      respostas.add(c);
      return c.future;
    };
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pump();
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pump();
    expect(respostas, hasLength(2));
    respostas[1].complete(_visaoComValores());
    await t.pump();
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
    respostas[0].complete(visaoExemplo(mesAbertoExemplo()));
    await t.pump();
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
  });

  testWidgets('compacto: a lista rola enquanto o mês carrega', (t) async {
    final s = ServicosFalsos();
    await _montar(t, servicos: s, tamanho: const Size(360, 500));
    final barreiras = find.byType(ModalBarrier).evaluate().length;
    final pendente = Completer<VisaoMes>();
    s.carregarMesFn = (mes, amigo) => pendente.future;
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('progresso-tela')), findsOneWidget);
    // nada cobre a tela durante a carga
    expect(find.byType(ModalBarrier).evaluate().length, barreiras);
    // a lista rola de verdade com o carregamento pendente
    final rolagem = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(rolagem.position.pixels, 0);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await t.pump();
    expect(rolagem.position.pixels, greaterThan(0));
    pendente.complete(_visaoComValores());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('progresso-tela')), findsNothing);
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
  });

  group('compacto', () {
    testWidgets(
      'regimes swing/day trade em cartões e FAB Nova compra só quando '
      'editável',
      (t) async {
        final s = ServicosFalsos();
        s.visoes['2026-10'] = _visaoComValores();
        await _montar(t, servicos: s, tamanho: _celular);
        expect(find.text('Swing trade'), findsOneWidget);
        expect(find.text('Day trade'), findsOneWidget);
        expect(find.text('Alíquota 15% · 0 vendas'), findsOneWidget);
        expect(find.text('Alíquota 20% · 0 vendas'), findsOneWidget);
        expect(find.text('Isento até R\$ 20 mil em ações'), findsOneWidget);
        expect(find.text('Sem isenção'), findsOneWidget);
        expect(find.byTooltip('Nova compra'), findsOneWidget);
        expect(
          find.textContaining('\nInclui R\$ 5,00 de meses anteriores'),
          findsOneWidget,
        );

        // Fechar mês fica no menu
        await t.tap(find.byType(PopupMenuButton<String>));
        await t.pumpAndSettle();
        await t.tap(find.text('Fechar mês'));
        await t.pumpAndSettle();
        expect(find.text('Fechar 10/2026'), findsOneWidget);
      },
    );

    testWidgets('mês fechado e amigo não têm FAB nem menu', (t) async {
      final s = ServicosFalsos()..mesAberto = '2026-09';
      await _montar(t, servicos: s, tamanho: _celular);
      expect(find.byTooltip('Nova compra'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('Fechado'), findsOneWidget);
    });

    testWidgets(
      "cartão 'Meta de lucro / Preço-alvo · N ativas' abre as metas",
      (t) async {
        var abriu = 0;
        final s = ServicosFalsos()..metasAtivasFalsas = 2;
        await _montar(
          t,
          servicos: s,
          tamanho: _celular,
          aoAbrirMetas: () => abriu++,
        );
        await t.tap(find.text('Meta de lucro / Preço-alvo · 2 ativas'));
        expect(abriu, 1);
      },
    );

    testWidgets('cartão de metas sem ação não parece tocável', (t) async {
      final s = ServicosFalsos()..metasAtivasFalsas = 1;
      await _montar(t, servicos: s, tamanho: _celular);
      final texto = find.text('Meta de lucro / Preço-alvo · 1 ativa');
      expect(texto, findsOneWidget);
      expect(
        find.ancestor(of: texto, matching: find.byType(InkWell)),
        findsNothing,
      );
      // só o cartão de saldo leva a outra tela e mostra a seta
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('cartão de saldo mostra o caixa e leva à aba Caixa', (t) async {
      final s = ServicosFalsos();
      await _montar(t, servicos: s, tamanho: _celular);
      final r = s.visaoCaixa ?? caixaExemplo();
      expect(
        find.text(
          'Saldo disponível ${brl(r.resumo.disponivel)} · '
          'projetado ${brl(r.resumo.projetado)}',
        ),
        findsOneWidget,
      );
      await t.tap(find.textContaining('Saldo disponível'));
      expect(_estado(t).aba, Aba.caixa);
    });

    testWidgets(
      'compra nova pergunta se já houve a venda e abre o formulário de venda',
      (t) async {
        final s = ServicosFalsos();
        final base = mesAbertoExemplo();
        s.visaoAposCompra = visaoExemplo(
          Mes(
            mes: '2026-10',
            lotes: [
              ...base.lotes,
              Lote(
                id: 'L9',
                ticker: 'ITUB4',
                tipo: 'Ação',
                dataCompra: '2026-10-28',
                qtd: 10,
                preco: 30,
              ),
            ],
          ),
        );
        await _montar(t, servicos: s, tamanho: _celular);
        await t.tap(find.byTooltip('Nova compra'));
        await t.pumpAndSettle();
        expect(find.text('Novo ativo'), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('ticker')), 'ITUB4');
        await t.enterText(find.byKey(const ValueKey('qtd')), '10');
        await t.enterText(find.byKey(const ValueKey('preco')), '30');
        await t.tap(find.text('Salvar'));
        await t.pumpAndSettle();
        expect(find.text('Venda'), findsOneWidget);
        expect(find.text('Você já fez a venda de ITUB4?'), findsOneWidget);
        await t.tap(find.text('Sim, registrar venda'));
        await t.pumpAndSettle();
        expect(find.text('Registrar venda'), findsWidgets);
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('ticker')))
              .controller!
              .text,
          'ITUB4',
        );
      },
    );

    testWidgets('Ainda não encerra a pergunta sem abrir a venda', (t) async {
      final s = ServicosFalsos();
      final base = mesAbertoExemplo();
      s.visaoAposCompra = visaoExemplo(
        Mes(
          mes: '2026-10',
          lotes: [
            ...base.lotes,
            Lote(
              id: 'L9',
              ticker: 'ITUB4',
              tipo: 'Ação',
              dataCompra: '2026-10-28',
              qtd: 10,
              preco: 30,
            ),
          ],
        ),
      );
      await _montar(t, servicos: s, tamanho: _celular);
      await t.tap(find.byTooltip('Nova compra'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('ticker')), 'ITUB4');
      await t.enterText(find.byKey(const ValueKey('qtd')), '10');
      await t.enterText(find.byKey(const ValueKey('preco')), '30');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ainda não'));
      await t.pumpAndSettle();
      expect(find.text('Registrar venda'), findsNothing);
      expect(find.text('Venda'), findsNothing);
    });
  });
}
