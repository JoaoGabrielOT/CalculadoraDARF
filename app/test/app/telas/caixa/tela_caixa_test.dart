import 'package:calculadoradarf/app/componentes/cartao.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/caixa/tela_caixa.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 900);
const _celular = Size(360, 800);

Lote _compra(
  String id,
  String ticker,
  String data, {
  int qtd = 100,
  List<Venda>? vendas,
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: 10,
  vendas: vendas,
);

/// Hoje é 28/10/2026 (quarta). ITUB4 já liquidou (22/10); PETR4 liquida
/// amanhã (comprou 27/10 e vendeu metade hoje) e VALE3, na sexta (30/10).
List<Lote> _lotes() => [
  _compra('L0', 'ITUB4', '2026-10-20'),
  _compra(
    'L1',
    'PETR4',
    '2026-10-27',
    qtd: 200,
    vendas: [Venda(id: 'V1', data: '2026-10-28', qtd: 50, preco: 12)],
  ),
  _compra('L2', 'VALE3', '2026-10-28', qtd: 300),
];

/// Caixa calculado pelo núcleo; sem [saldo] o saldo não foi informado.
VisaoCaixa _visao({double? saldo = 5000, List<Lote>? lotes, String? amigo}) {
  final cfg = Config(
    caixa: saldo == null ? Caixa() : Caixa(saldo: saldo, data: '2026-10-01'),
  );
  final meses = {'2026-10': Mes(mes: '2026-10', lotes: lotes ?? _lotes())};
  final resumo = resumoCaixa(cfg, meses, hoje: hojeExemplo);
  return VisaoCaixa(
    resumo: resumo,
    projecao: projecaoCaixa(resumo, hoje: hojeExemplo),
    agenda: agendaCaixa(resumo, hoje: hojeExemplo),
    hoje: hojeExemplo,
    amigo: amigo,
  );
}

Future<ServicosFalsos> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
}) async {
  final s = servicos ?? ServicosFalsos();
  await montarApp(t, servicos: s, tamanho: tamanho, tela: const TelaCaixa());
  await t.pumpAndSettle();
  return s;
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaCaixa)), listen: false);

int _chamadasCaixa(ServicosFalsos s) =>
    s.chamadas.where((c) => c.startsWith('caixa(')).length;

bool _habilitado(Finder f, WidgetTester t) {
  final w = t.widget(f);
  if (w is FilledButton) return w.onPressed != null;
  if (w is OutlinedButton) return w.onPressed != null;
  throw StateError('botão inesperado: $w');
}

Finder _naTabela(String texto) => find.descendant(
  of: find.byKey(const Key('tabela-lancamentos')),
  matching: find.text(texto),
);

/// Tickers da tabela de lançamentos, de cima para baixo (um por linha).
List<String> _ordemTabela(WidgetTester t) {
  const tickers = ['ITUB4', 'PETR4', 'VALE3'];
  final achados = <(double, String)>[];
  for (final tk in tickers) {
    final f = _naTabela(tk);
    for (var i = 0; i < f.evaluate().length; i++) {
      achados.add((t.getTopLeft(f.at(i)).dy, tk));
    }
  }
  achados.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final a in achados) a.$2];
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets(
    "quatro blocos com valores e subtítulos; '—' sem saldo definido",
    (t) async {
      final s = ServicosFalsos()..visaoCaixa = _visao();
      await _montar(t, servicos: s);
      final r = s.visaoCaixa!.resumo;

      for (final titulo in [
        'DISPONÍVEL AGORA',
        'A RECEBER',
        'A PAGAR',
        'SALDO PROJETADO',
      ]) {
        expect(find.text(titulo), findsOneWidget);
      }
      Finder noBloco(String chave, String texto) => find.descendant(
        of: find.byKey(Key('bloco-$chave')),
        matching: find.text(texto),
      );
      expect(noBloco('disponivel', brl(r.disponivel)), findsOneWidget);
      expect(noBloco('receber', '+${brl(r.aReceber)}'), findsOneWidget);
      expect(noBloco('pagar', brl(-r.aDebitar)), findsOneWidget);
      expect(noBloco('projetado', brl(r.projetado)), findsOneWidget);
      expect(find.text('livre para operar hoje'), findsOneWidget);
      expect(find.text('vendas ainda não liquidadas'), findsOneWidget);
      expect(find.text('compras e IRRF ainda não liquidados'), findsOneWidget);
      expect(find.text('depois de tudo liquidar'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('−'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(
        find.textContaining(
          'Saldo informado em 01/10/2026: R\$ 5.000,00 · '
          'liquidado desde então: ${brl(r.entrou)}',
        ),
        findsOneWidget,
      );

      s.visaoCaixa = _visao(saldo: null);
      s.eventosFalsos.add(const EventoDadosMudaram());
      await t.pumpAndSettle();
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('clique em Informar saldo'), findsOneWidget);
      expect(find.textContaining('Saldo informado em'), findsNothing);
    },
  );

  testWidgets('Aporte/Retirada desabilitados sem saldo', (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao(saldo: null);
    await _montar(t, servicos: s);
    expect(find.text('✎  Informar saldo'), findsOneWidget);
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, '+  Aporte'), t),
      isFalse,
    );
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, '−  Retirada'), t),
      isFalse,
    );
    expect(
      _habilitado(find.widgetWithText(FilledButton, '✎  Informar saldo'), t),
      isTrue,
    );

    s.visaoCaixa = _visao();
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.text('✎  Definir saldo'), findsOneWidget);
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, '+  Aporte'), t),
      isTrue,
    );
    expect(
      _habilitado(find.widgetWithText(OutlinedButton, '−  Retirada'), t),
      isTrue,
    );
  });

  testWidgets('alerta de saldo negativo na liquidação com o texto do Python', (
    t,
  ) async {
    final s = ServicosFalsos()..visaoCaixa = _visao(saldo: 500);
    await _montar(t, servicos: s);
    final negativo = s.visaoCaixa!.projecao.firstWhere(
      (p) => p.saldoApos < -0.004,
    );
    expect(
      find.text(
        '⚠  Seu saldo fica negativo (${brl(negativo.saldoApos)}) na '
        'liquidação de ${fmtLiquidacao(negativo.data).toLowerCase()}. '
        'Deposite a diferença até essa data para cobrir as compras.',
      ),
      findsOneWidget,
    );

    // só o disponível negativo, sem projeção negativa
    s.visaoCaixa = _visao(
      saldo: -50,
      lotes: [_compra('L0', 'ITUB4', '2026-10-20')],
    );
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.text('⚠  O saldo disponível está negativo.'), findsOneWidget);

    s.visaoCaixa = _visao(saldo: 50000);
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.textContaining('⚠'), findsNothing);
    expect(find.textContaining('ⓘ'), findsNothing);
  });

  testWidgets("alerta 'Informe quanto você tem livre…' sem saldo", (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao(saldo: null);
    await _montar(t, servicos: s);
    expect(
      find.text(
        'ⓘ  Informe quanto você tem livre na corretora hoje. Depois disso o '
        'app soma as vendas e desconta as compras sozinho, na data em que '
        'cada uma liquida.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'próximas liquidações (até 8) com saldo depois; vazio com o texto do '
    'Python',
    (t) async {
      // 10 dias úteis seguidos de compras: 10 datas de liquidação pendentes
      const dias = [
        '2026-10-27',
        '2026-10-28',
        '2026-10-29',
        '2026-10-30',
        '2026-11-03',
        '2026-11-04',
        '2026-11-05',
        '2026-11-06',
        '2026-11-09',
        '2026-11-10',
      ];
      final s = ServicosFalsos()
        ..visaoCaixa = _visao(
          lotes: [for (final (i, d) in dias.indexed) _compra('L$i', 'AA$i', d)],
        );
      await _montar(t, servicos: s);
      final cartoes = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('liquidacao-'),
      );
      expect(cartoes, findsNWidgets(8));
      expect(find.text('Total do dia'), findsNWidgets(8));
      expect(find.text('Saldo depois'), findsNWidgets(8));
      final primeiro = s.visaoCaixa!.projecao.first;
      expect(find.text('Amanhã'), findsOneWidget);
      expect(find.text('D+1'), findsOneWidget);
      expect(find.text(brl(primeiro.saldoApos)), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('liquidacao-${primeiro.data}')),
          matching: find.text(fmtLiquidacao(primeiro.data)),
        ),
        findsOneWidget,
      );

      // mais de 5 lançamentos no mesmo dia
      s.visaoCaixa = _visao(
        lotes: [
          for (var i = 0; i < 7; i++) _compra('M$i', 'BB$i', '2026-10-27'),
        ],
      );
      s.eventosFalsos.add(const EventoDadosMudaram());
      await t.pumpAndSettle();
      expect(find.text('+ 2 lançamento(s)'), findsOneWidget);

      // sem nada pendente
      s.visaoCaixa = caixaExemplo();
      s.eventosFalsos.add(const EventoDadosMudaram());
      await t.pumpAndSettle();
      expect(
        find.text(
          'Nada a liquidar nos próximos dias. Compras e vendas aparecem aqui '
          'com a data em que o dinheiro entra ou sai da conta.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('sem saldo as próximas liquidações não mostram o saldo depois', (
    t,
  ) async {
    final s = ServicosFalsos()..visaoCaixa = _visao(saldo: null);
    await _montar(t, servicos: s);
    expect(find.text('Total do dia'), findsWidgets);
    expect(find.text('Saldo depois'), findsNothing);
  });

  testWidgets('lançamentos filtram por Todos/A liquidar/Liquidados e ordenam', (
    t,
  ) async {
    final s = ServicosFalsos()..visaoCaixa = _visao();
    await _montar(t, servicos: s);
    expect(_ordemTabela(t), ['ITUB4', 'PETR4', 'PETR4', 'VALE3']);
    expect(_naTabela('Liquidado'), findsOneWidget);
    expect(_naTabela('A liquidar'), findsNWidgets(3));

    await t.tap(find.widgetWithText(ChipFiltro, 'A liquidar'));
    await t.pumpAndSettle();
    expect(_naTabela('ITUB4'), findsNothing);
    expect(_naTabela('PETR4'), findsNWidgets(2));
    expect(_naTabela('VALE3'), findsOneWidget);

    await t.tap(find.widgetWithText(ChipFiltro, 'Liquidados'));
    await t.pumpAndSettle();
    expect(_naTabela('ITUB4'), findsOneWidget);
    expect(_naTabela('PETR4'), findsNothing);

    await t.tap(find.widgetWithText(ChipFiltro, 'Todos'));
    await t.pumpAndSettle();
    // VALOR NA CONTA crescente: o maior débito (VALE3) vem primeiro
    await t.tap(find.text('VALOR NA CONTA ↕'));
    await t.pumpAndSettle();
    expect(_ordemTabela(t), ['VALE3', 'PETR4', 'ITUB4', 'PETR4']);
    await t.tap(find.text('VALOR NA CONTA ▲'));
    await t.pumpAndSettle();
    expect(_ordemTabela(t), ['PETR4', 'ITUB4', 'PETR4', 'VALE3']);
  });

  testWidgets('lançamentos sem nada mostram o texto do Python', (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao(lotes: []);
    await _montar(t, servicos: s);
    expect(
      find.text(
        'Nenhum lançamento. Compras e vendas aparecem aqui com a data em '
        'que o dinheiro entra ou sai.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    "caixa do amigo: 'Caixa de <email> · somente leitura' e sem ações",
    (t) async {
      final s = ServicosFalsos()..visaoCaixa = _visao();
      await _montar(t, servicos: s);
      expect(find.text('✎  Definir saldo'), findsOneWidget);

      s.visaoCaixa = _visao(amigo: 'ana@exemplo.com', saldo: null);
      await _estado(t).trocarVisao('ana@exemplo.com');
      await t.pumpAndSettle();
      expect(s.chamadas, contains('caixa(ana@exemplo.com)'));
      expect(
        find.text('Caixa de ana@exemplo.com · somente leitura'),
        findsOneWidget,
      );
      expect(find.text('+  Aporte'), findsNothing);
      expect(find.text('−  Retirada'), findsNothing);
      expect(find.textContaining('Definir saldo'), findsNothing);
      expect(find.textContaining('Informar saldo'), findsNothing);
      expect(
        find.text('ana@exemplo.com ainda não informou o saldo da conta.'),
        findsOneWidget,
      );
      expect(find.text('não informado'), findsOneWidget);

      // com saldo, o alerta de negativo fala do amigo
      s.visaoCaixa = _visao(amigo: 'bia@exemplo.com', saldo: 500);
      await _estado(t).trocarVisao('bia@exemplo.com');
      await t.pumpAndSettle();
      expect(
        find.textContaining('⚠  O saldo de bia@exemplo.com fica negativo'),
        findsOneWidget,
      );

      await _estado(t).trocarVisao(null);
      await t.pumpAndSettle();
      expect(find.textContaining('somente leitura'), findsNothing);
      expect(find.text('✎  Definir saldo'), findsOneWidget);
    },
  );

  testWidgets('Aporte abre o formulário e a visão devolvida vale', (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao();
    await _montar(t, servicos: s);
    await t.tap(find.text('+  Aporte'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    s.visaoCaixa = _visao(saldo: 7777);
    await t.enterText(find.byKey(const ValueKey('valor')), '100');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimoSaldo, (modo: ModoSaldo.aporte, valor: 100.0));
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.textContaining('Saldo informado em 01/10/2026: R\$ 7.777,00'),
      findsOneWidget,
    );

    // Cancelar não muda nada
    await t.tap(find.text('✎  Definir saldo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('recarrega com versaoDados e na troca de amigo', (t) async {
    final s = await _montar(t);
    final antes = _chamadasCaixa(s);
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(_chamadasCaixa(s), greaterThan(antes));
    final depoisDoEvento = _chamadasCaixa(s);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(s.chamadas.last, 'caixa(ana@exemplo.com)');
    expect(_chamadasCaixa(s), greaterThan(depoisDoEvento));
  });

  testWidgets('virada do dia recarrega', (t) async {
    final s = await _montar(t);
    final antes = _chamadasCaixa(s);
    await t.pump(const Duration(seconds: 60));
    await t.pump(const Duration(seconds: 60));
    expect(_chamadasCaixa(s), antes, reason: 'mesmo dia: não recarrega');

    ambiente = Ambiente.fixo(hoje: '2026-10-29');
    await t.pump(const Duration(seconds: 60));
    await t.pumpAndSettle();
    expect(_chamadasCaixa(s), antes + 1);
    await t.pump(const Duration(seconds: 60));
    expect(_chamadasCaixa(s), antes + 1, reason: 'o novo dia já foi carregado');
  });

  testWidgets('falha ao carregar mostra o erro e não trava', (t) async {
    final s = ServicosFalsos()..erros['caixa'] = ErroValidacao('Sem caixa.');
    await _montar(t, servicos: s);
    expect(find.text('Sem caixa.'), findsOneWidget);
  });

  testWidgets(
    'recarga que falha no mesmo dono mantém o caixa e mostra o erro',
    (t) async {
      final s = ServicosFalsos()..visaoCaixa = _visao();
      await _montar(t, servicos: s);
      s.erros['caixa'] = ErroValidacao('Sem rede.');
      s.eventosFalsos.add(const EventoDadosMudaram());
      await t.pumpAndSettle();
      expect(find.text('Sem rede.'), findsOneWidget);
      expect(find.text('DISPONÍVEL AGORA'), findsOneWidget);
      expect(find.text('Próximas liquidações'), findsOneWidget);

      // o erro some quando a recarga seguinte dá certo
      s.erros.remove('caixa');
      s.eventosFalsos.add(const EventoDadosMudaram());
      await t.pumpAndSettle();
      expect(find.text('Sem rede.'), findsNothing);
    },
  );

  testWidgets('pedido superado mantém o caixa e não deixa em Carregando', (
    t,
  ) async {
    final s = ServicosFalsos()..visaoCaixa = _visao();
    await _montar(t, servicos: s);
    s.erros['caixa'] = PedidoSuperado('superado');
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.text('DISPONÍVEL AGORA'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('progresso-tela')), findsNothing);

    // sem nada à vista, a tela também não fica em Carregando
    final s2 = ServicosFalsos()..erros['caixa'] = PedidoSuperado('superado');
    await _montar(t, servicos: s2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('compacto: agenda financeira com grupos', (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao();
    await _montar(t, servicos: s, tamanho: _celular);
    final r = s.visaoCaixa!.resumo;
    expect(find.text('Saldo disponível (D+0)'), findsOneWidget);
    expect(find.text(brl(r.disponivel)), findsOneWidget);
    expect(find.text('Em trânsito (D+1/D+2)'), findsOneWidget);
    expect(find.text('Saldo projetado'), findsOneWidget);
    expect(find.text('Agenda financeira'), findsOneWidget);
    expect(find.text('Liquidados recentemente'), findsOneWidget);
    expect(find.text('ITUB4 · Compra'), findsOneWidget);
    expect(find.text('PETR4 · Compra'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);

    s.visaoCaixa = _visao(saldo: null, lotes: []);
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.text('Nenhum lançamento'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Nada pendente'), findsOneWidget);

    s.visaoCaixa = caixaExemplo();
    s.eventosFalsos.add(const EventoDadosMudaram());
    await t.pumpAndSettle();
    expect(find.text('Nenhuma liquidação pendente.'), findsOneWidget);
  });

  testWidgets('compacto: amigo não tem Editar', (t) async {
    final s = ServicosFalsos()..visaoCaixa = _visao();
    await _montar(t, servicos: s, tamanho: _celular);
    await _estado(t).trocarVisao('ana@exemplo.com');
    await t.pumpAndSettle();
    expect(find.text('Editar'), findsNothing);
    expect(
      find.text('Caixa de ana@exemplo.com · somente leitura'),
      findsOneWidget,
    );
  });
}
