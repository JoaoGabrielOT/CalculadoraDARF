import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 1400);
const _celular = Size(360, 3000);

/// Setembro fechado: ITUB4 vendido por inteiro e PETR4 ainda em carteira.
Mes _setembro() => Mes(
  mes: '2026-09',
  fechado: true,
  lotes: [
    ...mesFechadoExemplo().lotes,
    Lote(
      id: 'F2',
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-09-10',
      qtd: 100,
      preco: 31.5,
    ),
  ],
);

ServicosFalsos _falsos() => ServicosFalsos()
  ..visoes['2026-09'] = visaoExemplo(_setembro())
  ..cotacoesAtuaisResp = {
    'PETR4': CotacaoAtual(
      preco: 36.2,
      hora: DataHora.parse('2026-11-07T14:05:00-03:00'),
      fonte: 'Yahoo',
    ),
    'VALE3': CotacaoAtual(
      preco: 58.4,
      hora: DataHora.parse('2026-11-07T14:06:00-03:00'),
      fonte: 'Yahoo',
    ),
    'AAPL34': CotacaoAtual(
      preco: 57.1,
      hora: DataHora.parse('2026-11-07T14:07:00-03:00'),
      fonte: 'Yahoo',
    ),
  };

Future<ServicosFalsos> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  bool windows = true,
  String? mes,
}) async {
  final s = servicos ?? _falsos();
  await montarApp(
    t,
    servicos: s,
    plataforma: PlataformaFalsa(windows: windows),
    tamanho: tamanho,
    tela: const TelaApuracao(
      conteudo: listasApuracao,
      sliversCompactos: listasSliversApuracao,
    ),
  );
  await t.pumpAndSettle();
  if (mes != null) {
    Provider.of<EstadoApp>(
      t.element(find.byType(TelaApuracao)),
      listen: false,
    ).trocarMes(mes);
    await t.pumpAndSettle();
  }
  return s;
}

Future<void> _tocar(WidgetTester t, String texto) async {
  await t.tap(find.text(texto));
  await t.pumpAndSettle();
}

Finder _botao(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// Abre o ativo e o "Mais detalhes" dele.
Future<void> _abrirDetalhes(WidgetTester t, String ticker) async {
  await t.tap(find.byKey(Key('ativo-$ticker')));
  await t.pumpAndSettle();
  final detalhes = find.byKey(Key('detalhes-$ticker'));
  await t.ensureVisible(detalhes);
  await t.pumpAndSettle();
  await t.tap(detalhes);
  await t.pumpAndSettle();
}

bool _habilitado(WidgetTester t, String texto) =>
    t.widget<ButtonStyleButton>(_botao(texto)).onPressed != null;

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));
  tearDown(() => ambiente = Ambiente.sistema());

  testWidgets('seletor com os dois segmentos; padrão = carteira atual no mês '
      'aberto', (t) async {
    await _montar(t);
    expect(find.text('Posição em 28/10/2026'), findsOneWidget);
    expect(find.text('Carteira atual'), findsOneWidget);
    expect(find.byKey(const Key('tabela-lotes')), findsOneWidget);
    expect(find.byKey(const Key('lista-posicoes')), findsNothing);
  });

  testWidgets('mês histórico: padrão é a posição no último dia, sem valor de '
      'mercado nem cotação', (t) async {
    await _montar(t, mes: '2026-09');
    expect(find.text('Posição em 30/09/2026'), findsOneWidget);
    expect(find.byKey(const Key('lista-posicoes')), findsOneWidget);
    expect(find.byKey(const Key('tabela-lotes')), findsNothing);
    expect(find.text('cotação histórica não disponível'), findsOneWidget);
    expect(find.textContaining('Cotação atual'), findsNothing);
    expect(find.textContaining('VALOR DE MERCADO'), findsNothing);
    expect(find.byKey(const Key('ativo-PETR4')), findsOneWidget);
    expect(find.byKey(const Key('ativo-ITUB4')), findsNothing);
  });

  testWidgets('posição: linha com quantidade, preço médio, cotação e '
      'resultado; expandida, os cartões e as compras em "Mais detalhes"', (
    t,
  ) async {
    await _montar(t, mes: '2026-09');
    final linha = find.byKey(const Key('ativo-PETR4'));
    Finder em(Finder f) => find.descendant(of: linha, matching: f);
    expect(em(find.text('100')), findsOneWidget);
    expect(em(find.text('R\$ 31,50')), findsOneWidget);
    // sem cotação: cotação e resultado em "—" neutro
    expect(em(find.text('—')), findsNWidgets(2));
    expect(find.text('R\$ 3.150,00'), findsNothing);
    expect(find.byKey(const Key('cartoes-PETR4')), findsNothing);
    await t.tap(linha);
    await t.pumpAndSettle();
    final cartoes = find.byKey(const Key('cartoes-PETR4'));
    Finder noCartao(String texto) =>
        find.descendant(of: cartoes, matching: find.text(texto));
    for (final r in ['Investido', 'Valor atual', 'Em aberto', 'Equilíbrio']) {
      expect(noCartao(r), findsOneWidget, reason: r);
    }
    expect(noCartao('R\$ 3.150,00'), findsOneWidget);
    expect(noCartao('R\$ 31,51'), findsOneWidget);
    expect(noCartao('—'), findsNWidgets(2));
    expect(find.text('Realizado no mês'), findsOneWidget);
    expect(find.text('Acumulado desde 09/2026'), findsOneWidget);
    // compras e a lista longa ficam em "Mais detalhes"
    expect(find.byKey(const Key('compras-PETR4')), findsNothing);
    expect(find.byKey(const Key('indicadores-PETR4')), findsNothing);
    await t.tap(find.byKey(const Key('detalhes-PETR4')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('compras-PETR4')), findsOneWidget);
    expect(find.text('10/09/2026 · 100 de 100 × R\$ 31,50'), findsOneWidget);
    expect(find.text('Tipo: Ação · custo por compra'), findsOneWidget);
  });

  testWidgets('mês corrente: selo com fonte, data e hora da cotação atual', (
    t,
  ) async {
    final s = await _montar(t);
    await _tocar(t, 'Posição em 28/10/2026');
    expect(find.byKey(const Key('lista-posicoes')), findsOneWidget);
    expect(find.text('Cotação atual · Yahoo · 07/11 14:05'), findsOneWidget);
    expect(find.text('cotação histórica não disponível'), findsNothing);
    expect(find.text('COTAÇÃO'), findsOneWidget);
    expect(find.text('RESULTADO EM ABERTO'), findsOneWidget);
    // PETR4: 60 × 36,20 − 60 × 32,50, sobre o custo de R$ 1.950,00
    final ganho = find.text('▲ +R\$ 222,00 (+11,4%)');
    expect(ganho, findsOneWidget);
    final perda = find.text('▼ -R\$ 340,00 (-2,8%)'); // VALE3
    expect(perda, findsOneWidget);
    final cores = CoresApp.de(t.element(ganho));
    expect(t.widget<Text>(ganho).style?.color, cores.alta);
    expect(t.widget<Text>(perda).style?.color, cores.queda);
    await t.tap(find.byKey(const Key('ativo-PETR4')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('cartoes-PETR4')),
        matching: find.text('R\$ 2.172,00'),
      ),
      findsOneWidget,
    ); // valor atual
    expect(s.chamadas, contains('cotacoesAtuais(AAPL34,PETR4,VALE3)'));
  });

  testWidgets('celular: posição em cartões com o selo da cotação atual', (
    t,
  ) async {
    await _montar(t, tamanho: _celular, windows: false);
    await _tocar(t, 'Posição em 28/10/2026');
    expect(find.text('Cotação atual · Yahoo · 07/11 14:05'), findsOneWidget);
    expect(find.byKey(const Key('ativo-PETR4')), findsOneWidget);
    expect(find.text('▲ +R\$ 222,00 (+11,4%)'), findsOneWidget);
    expect(
      find.text('60 un. · PM R\$ 32,50 · cotação R\$ 36,20'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ativo-PETR4')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('cartoes-PETR4')),
        matching: find.text('R\$ 2.172,00'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('falha em cotacoesAtuais: a posição aparece sem valor de '
      'mercado', (t) async {
    final s = _falsos()..erros['cotacoesAtuais'] = 'sem rede';
    await _montar(t, servicos: s);
    await _tocar(t, 'Posição em 28/10/2026');
    expect(find.byKey(const Key('ativo-PETR4')), findsOneWidget);
    expect(find.textContaining('Cotação atual ·'), findsNothing);
    expect(find.text('cotação atual indisponível'), findsOneWidget);
    expect(find.text('R\$ 2.172,00'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('carteira atual mantém vender, editar e excluir dos lotes do '
      'mês aberto', (t) async {
    await _montar(t);
    await _tocar(t, 'Posição em 28/10/2026');
    expect(find.text('Registrar venda'), findsNothing);
    await _tocar(t, 'Carteira atual');
    expect(find.byKey(const Key('tabela-lotes')), findsOneWidget);
    expect(_habilitado(t, 'Registrar venda'), isTrue);
    expect(_habilitado(t, 'Editar'), isTrue);
    expect(_habilitado(t, 'Excluir'), isTrue);
  });

  testWidgets('carteira atual de um mês histórico mostra os lotes do mês '
      'aberto, com as ações', (t) async {
    final s = await _montar(t, mes: '2026-09');
    await _tocar(t, 'Carteira atual');
    expect(find.text('Lotes do mês aberto (10/2026)'), findsOneWidget);
    expect(find.byKey(const Key('tabela-lotes')), findsOneWidget);
    expect(find.text('VALE3'), findsWidgets);
    expect(_habilitado(t, 'Registrar venda'), isTrue);
    expect(s.chamadas, contains('carregarMes(2026-10, null)'));
  });

  testWidgets('carteira atual também leva o selo da cotação atual', (t) async {
    await _montar(t);
    expect(find.text('Cotação atual · Yahoo · 07/11 14:05'), findsOneWidget);
  });

  testWidgets('visão de amigo: a posição de hoje também busca a cotação '
      'atual, sem ficar em "…"', (t) async {
    await _montar(t);
    final estado = Provider.of<EstadoApp>(
      t.element(find.byType(TelaApuracao)),
      listen: false,
    );
    await estado.trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    await _tocar(t, 'Posição em 28/10/2026');
    expect(find.text('Cotação atual · Yahoo · 07/11 14:05'), findsOneWidget);
    expect(find.text('carregando cotação atual…'), findsNothing);
    expect(find.text('…'), findsNothing);
  });

  testWidgets('fechar o mês com "Carteira atual" escolhida: a lista acompanha '
      'o novo mês aberto', (t) async {
    final s = _falsos();
    s.fechamento = Fechamento(
      visao: visaoExemplo(
        Mes(mes: '2026-10', fechado: true, lotes: mesAbertoExemplo().lotes),
      ),
      mensagem: 'fechou',
    );
    await _montar(t, servicos: s);
    await _tocar(t, 'Carteira atual');
    // o novo mês aberto passa a ser 2026-11
    s.visoes['2026-11'] = visaoExemplo(
      Mes(
        mes: '2026-11',
        lotes: [
          Lote(
            id: 'N1',
            ticker: 'BBAS3',
            tipo: 'Ação',
            dataCompra: '2026-10-20',
            qtd: 10,
            preco: 25,
          ),
        ],
      ),
    );
    s.mesAberto = '2026-11';
    await t.tap(find.widgetWithText(FilledButton, 'Fechar mês'));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Fechar mês'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Carregando a carteira atual…'), findsNothing);
    expect(find.text('Lotes do mês aberto (11/2026)'), findsOneWidget);
    expect(find.text('BBAS3'), findsWidgets);
  });
  testWidgets('posição de mês passado: indicadores sem mercado, com os '
      'rótulos de mês, acumulado e método', (t) async {
    await _montar(t, mes: '2026-09');
    expect(find.byKey(const Key('indicadores-PETR4')), findsNothing);
    await _abrirDetalhes(t, 'PETR4');
    final painel = find.byKey(const Key('indicadores-PETR4'));
    expect(painel, findsOneWidget);
    // o método e a origem do custo vão na dica do (i) dos cartões
    expect(
      find.byTooltip(
        'Resultado: método por compra. Custo remanescente: por compra.',
      ),
      findsOneWidget,
    );
    for (final r in [
      'Quantidade em aberto',
      'Preço médio das compras (saldo)',
      'Preço médio das vendas no mês',
      'Rentabilidade realizada no mês (método por compra, %)',
    ]) {
      expect(
        find.descendant(of: painel, matching: find.text(r)),
        findsOneWidget,
        reason: r,
      );
    }
    expect(
      find.descendant(of: painel, matching: find.textContaining('mercado')),
      findsNothing,
    );
    expect(
      find.descendant(of: painel, matching: find.textContaining('Exposição')),
      findsNothing,
    );
    // sem vendas de PETR4 em setembro: "—" e não zero
    expect(
      find.descendant(of: painel, matching: find.text('—')),
      findsNWidgets(3),
    );
  });

  testWidgets('posição de hoje: não realizado, valor de mercado e exposição '
      'com cotação de todos os ativos', (t) async {
    await _montar(t);
    await _tocar(t, 'Posição em 28/10/2026');
    await _abrirDetalhes(t, 'PETR4');
    final painel = find.byKey(const Key('indicadores-PETR4'));
    final cartoes = find.byKey(const Key('cartoes-PETR4'));
    // não realizado e valor de mercado ficam nos cartões, fora da lista
    expect(
      find.descendant(
        of: cartoes,
        matching: find.text('▲ +R\$ 222,00 (+11,4%)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cartoes, matching: find.text('R\$ 2.172,00')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: painel,
        matching: find.text('Resultado não realizado (gerencial, R\$)'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: painel,
        matching: find.text('Exposição na carteira (%)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: painel, matching: find.textContaining('%')),
      findsWidgets,
    );
  });

  testWidgets('cotação que falhou deixa a exposição em "—"', (t) async {
    final s = _falsos()..cotacoesAtuaisResp.remove('VALE3');
    await _montar(t, servicos: s);
    await _tocar(t, 'Posição em 28/10/2026');
    await _abrirDetalhes(t, 'PETR4');
    final cartoes = find.byKey(const Key('cartoes-PETR4'));
    final linha = find.ancestor(
      of: find.text('Exposição na carteira (%)'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: linha.first, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cartoes, matching: find.text('R\$ 2.172,00')),
      findsOneWidget,
    );
  });

  testWidgets('detalhamento do mês traz os indicadores do ativo vendido', (
    t,
  ) async {
    await _montar(t, mes: '2026-09');
    expect(find.byKey(const Key('indicadores-vendidos')), findsOneWidget);
    expect(find.byKey(const Key('indicadores-ITUB4')), findsNothing);
    await t.tap(find.byKey(const Key('indicadores-vendido-ITUB4')));
    await t.pumpAndSettle();
    final painel = find.byKey(const Key('indicadores-ITUB4'));
    expect(painel, findsOneWidget);
    expect(
      find.descendant(of: painel, matching: find.text('R\$ 32,00')),
      findsOneWidget,
    ); // preço médio das vendas
    expect(
      find.descendant(of: painel, matching: find.text('Quantidade em aberto')),
      findsOneWidget,
    );
  });

  testWidgets('celular: indicadores expandidos sem overflow', (t) async {
    await _montar(t, tamanho: _celular, windows: false);
    await _tocar(t, 'Posição em 28/10/2026');
    await _abrirDetalhes(t, 'PETR4');
    expect(find.byKey(const Key('indicadores-PETR4')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('carteira atual: a cotação dos ativos da posição de hoje também '
      'é buscada', (t) async {
    final s = _falsos();
    s.posicoesPorMes['2026-10'] = VisaoPosicoes(
      dataCorte: hojeExemplo,
      corrente: true,
      posicoes: [
        PosicaoAtivo(
          ticker: 'ZZZZ3',
          tipo: 'Ação',
          qtd: 10,
          custoGerencial: 100,
          compras: const [],
        ),
      ],
    );
    await _montar(t, servicos: s);
    expect(
      s.chamadas.where((c) => c.startsWith('cotacoesAtuais(')).join(' '),
      contains('ZZZZ3'),
    );
  });
}
