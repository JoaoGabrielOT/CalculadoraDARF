import 'dart:async';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/metas/tela_metas.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/dados_exemplo.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 1000);

final _lote = Lote(
  id: 'L1',
  ticker: 'PETR4',
  tipo: 'Ação',
  dataCompra: '2026-10-05',
  qtd: 100,
  preco: 9,
);

final _cotacao = CotacaoInfo(
  preco: 10,
  hora: DataHora.parse('2026-10-28T11:55:00-03:00'),
  fonte: 'Yahoo',
  atual: true,
);

/// 30 pregões até [fim], fechando em 10 com ATR pequeno; o pico de [topo]
/// (na barra 12) é a resistência dos últimos 20 pregões.
List<BarraDiaria> _barras({
  double topo = 12.5,
  double volume = 1e6,
  String fim = '2026-10-27',
}) => [
  for (var i = 0; i < 30; i++)
    BarraDiaria(
      data: somarDias(fim, -(29 - i)),
      abre: 10,
      alta: i == 12 ? topo : 10.2,
      baixa: 9.8,
      fech: 10,
      volume: volume,
    ),
];

CompraNaPosicao _compra(
  String id, {
  String data = '2026-10-05',
  int qtd = 100,
  double preco = 9,
}) => CompraNaPosicao(
  loteId: id,
  mes: '2026-10',
  dataCompra: data,
  qtdOriginal: qtd,
  restante: qtd,
  preco: preco,
);

PosicaoAtivo _posicao(String ticker, List<CompraNaPosicao> compras) =>
    PosicaoAtivo(
      ticker: ticker,
      tipo: 'Ação',
      qtd: compras.fold(0, (s, c) => s + c.restante),
      custoGerencial: compras.fold(0.0, (s, c) => s + c.restante * c.preco),
      compras: compras,
    );

SugestaoAtivo _ativo(
  String ticker, {
  EstadoDados estado = EstadoDados.ok,
  String? mensagem,
  double topo = 12.5,
  double volume = 1e6,
  CotacaoInfo? cotacao,
  List<CompraNaPosicao>? compras,
  bool semPosicao = false,
  bool semBarras = false,
  String fimBarras = '2026-10-27',
}) => SugestaoAtivo(
  ticker: ticker,
  estado: estado,
  mensagem: mensagem,
  cotacao: cotacao ?? _cotacao,
  barras: semBarras
      ? const []
      : _barras(topo: topo, volume: volume, fim: fimBarras),
  posicao: semPosicao ? null : _posicao(ticker, compras ?? [_compra('L1')]),
);

/// O cenário de swing que a tela deve mostrar para [a].
CenarioMercado _cenario(SugestaoAtivo a) => cenarioSwing(
  ticker: a.ticker,
  barras: a.barras,
  hoje: hojeExemplo,
  cotacao: a.cotacao,
  qtd: a.posicao!.qtd,
);

VisaoSugestoes _visao(List<SugestaoAtivo> ativos) => VisaoSugestoes(
  ativos: ativos,
  rodape: const [('Patrimônio considerado', 'R\$ 10.000,00', null)],
);

Future<ServicosFalsos> _abrir(WidgetTester t, ServicosFalsos s) async {
  s.visaoMetas ??= VisaoMetas(
    metas: const [],
    descricoes: const {},
    lotes: [(mes: '2026-10', lote: _lote, livre: 100)],
    ativas: 0,
  );
  await abrirNoTeste<void>(t, s, abrirMetas, tamanho: _pc);
  return s;
}

int _chamadasSugestoes(ServicosFalsos s) =>
    s.chamadas.where((c) => c.startsWith('sugestoesMetas')).length;

Future<void> _expandir(WidgetTester t, String ticker) async {
  await _tocar(t, find.byKey(ValueKey('abrir-$ticker')));
}

/// Rola até o item (a lista é maior que a janela do diálogo) e toca.
Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Abre a lista suspensa [chave] e escolhe [rotulo].
Future<void> _escolher(WidgetTester t, String chave, String rotulo) async {
  await t.tap(find.byKey(ValueKey(chave)));
  await t.pumpAndSettle();
  await t.tap(find.text(rotulo).last);
  await t.pumpAndSettle();
}

/// Os filtros rolam junto com a lista.
Future<void> _aoTopo(WidgetTester t) async {
  await t.drag(find.byType(ListView).first, const Offset(0, 3000));
  await t.pumpAndSettle();
}

Future<void> _digitar(
  WidgetTester t,
  String chave,
  String texto, {
  bool esperar = true,
}) async {
  await t.enterText(find.byKey(ValueKey(chave)), texto);
  if (esperar) await t.pump(const Duration(milliseconds: 300));
  await t.pumpAndSettle();
}

/// Posição vertical de cada ticker na lista, de cima para baixo.
List<String> _ordem(WidgetTester t, List<String> tickers) {
  final y = {
    for (final k in tickers)
      if (find.byKey(ValueKey('sug-$k')).evaluate().isNotEmpty)
        k: t.getTopLeft(find.byKey(ValueKey('sug-$k'))).dy,
  };
  return (y.keys.toList()..sort((a, b) => y[a]!.compareTo(y[b]!)));
}

ButtonStyleButton _botao(WidgetTester t, String texto, {int indice = 0}) => t
    .widgetList<ButtonStyleButton>(
      find.ancestor(
        of: find.text(texto),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    )
    .elementAt(indice);

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  testWidgets('carregando sem travar e ativos quando chega; avisos no '
      'rodapé', (t) async {
    final espera = Completer<VisaoSugestoes>();
    var n = 0;
    final s = ServicosFalsos()
      ..sugestoesMetasFn = (_) =>
          n++ == 0 ? Future.value(_visao([])) : espera.future;
    await _abrir(t, s);
    await t.tap(find.text('Atualizar'));
    await t.pump();
    expect(find.text('Carregando sugestões…'), findsOneWidget);
    expect(find.text('Atualizar'), findsOneWidget);
    espera.complete(_visao([_ativo('PETR4')]));
    await t.pumpAndSettle();
    expect(find.textContaining('Atualizado às '), findsOneWidget);
    expect(find.byKey(const ValueKey('sug-PETR4')), findsOneWidget);
    expect(find.text('PATRIMÔNIO CONSIDERADO'), findsOneWidget);
    expect(find.text(avisoSugestao), findsOneWidget);
    expect(find.text(avisoProventos), findsOneWidget);
    expect(find.text(avisoGap), findsOneWidget);
  });

  testWidgets("sem posições: 'Nenhuma compra em aberto.'", (t) async {
    await _abrir(t, ServicosFalsos());
    expect(find.text('Nenhuma compra em aberto.'), findsOneWidget);
  });

  testWidgets('agrupa por ativo e expande as compras', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _ativo(
          'PETR4',
          compras: [
            _compra('L1'),
            _compra('L2', data: '2026-10-06', qtd: 50, preco: 12),
          ],
        ),
      ]);
    await _abrir(t, s);
    expect(find.byKey(const ValueKey('sug-PETR4')), findsOneWidget);
    expect(find.textContaining('gerencial'), findsNothing);
    await _expandir(t, 'PETR4');
    expect(find.textContaining('Compra de 05/10/2026'), findsOneWidget);
    expect(find.textContaining('Compra de 06/10/2026'), findsOneWidget);
    expect(find.textContaining('custo gerencial'), findsNWidgets(2));
  });

  testWidgets('filtros de horizonte, posições abertas e dados', (t) async {
    final hoje = hojeExemplo;
    final s = ServicosFalsos()
      ..sugestoesMetasFn = (radar) async => _visao([
        _ativo(
          'PETR4',
          compras: [
            _compra('L1'),
            _compra('L2', data: hoje, qtd: 20),
          ],
        ),
        _ativo(
          'VALE3',
          estado: EstadoDados.semDados,
          mensagem: 'Sem dados para VALE3 no Yahoo Finance.',
          semBarras: true,
        ),
        if (radar) _ativo('WEGE3', semPosicao: true),
      ]);
    await _abrir(t, s);
    expect(find.byKey(const ValueKey('sug-PETR4')), findsOneWidget);
    expect(find.byKey(const ValueKey('sug-VALE3')), findsOneWidget);
    expect(find.byKey(const ValueKey('sug-WEGE3')), findsNothing);
    expect(s.chamadas, contains('sugestoesMetas()'));

    // desligado, o radar entra (e só então é pedido)
    await t.tap(find.text('Só posições abertas'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('sugestoesMetas(radar)'));
    expect(find.byKey(const ValueKey('sug-WEGE3')), findsOneWidget);
    await t.tap(find.text('Só posições abertas'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sug-WEGE3')), findsNothing);

    await _escolher(t, 'filtro-dados', 'Com dados');
    expect(find.byKey(const ValueKey('sug-PETR4')), findsOneWidget);
    expect(find.byKey(const ValueKey('sug-VALE3')), findsNothing);
    await _escolher(t, 'filtro-dados', 'Sem dados ou desatualizados');
    expect(find.byKey(const ValueKey('sug-PETR4')), findsNothing);
    expect(find.byKey(const ValueKey('sug-VALE3')), findsOneWidget);
    await _escolher(t, 'filtro-dados', 'Todos');

    // day trade: só quem tem compra de hoje
    await t.tap(find.text('Day trade'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sug-PETR4')), findsOneWidget);
    expect(find.byKey(const ValueKey('sug-VALE3')), findsNothing);
    await t.tap(find.text('Swing'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sug-VALE3')), findsOneWidget);
  });

  testWidgets('ordena por R/R, distância até o alvo, liquidez e ticker, '
      'sem dado no fim', (t) async {
    final todos = ['ZZZZ3', 'AAAA3', 'MMMM3', 'BBBB3'];
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _ativo('ZZZZ3', topo: 12.5, volume: 2e6),
        _ativo('AAAA3', topo: 11.5, volume: 1e6),
        _ativo('MMMM3', topo: 13.5, volume: 3e6),
        _ativo(
          'BBBB3',
          estado: EstadoDados.semDados,
          mensagem: 'sem dados',
          semBarras: true,
        ),
      ]);
    await _abrir(t, s);
    // padrão: R/R, do maior para o menor
    expect(_ordem(t, todos), ['MMMM3', 'ZZZZ3', 'AAAA3', 'BBBB3']);

    Future<void> ordenar(String rotulo) =>
        _escolher(t, 'ordem-sugestoes', rotulo);

    await ordenar('Distância até o alvo');
    expect(_ordem(t, todos), ['AAAA3', 'ZZZZ3', 'MMMM3', 'BBBB3']);
    await ordenar('Liquidez');
    expect(_ordem(t, todos), ['MMMM3', 'ZZZZ3', 'AAAA3', 'BBBB3']);
    await ordenar('Ticker');
    expect(_ordem(t, todos), ['AAAA3', 'MMMM3', 'ZZZZ3', 'BBBB3']);
  });

  testWidgets('recalcula ao mudar quantidade, preço e horizonte sem nova '
      'requisição', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _ativo(
          'PETR4',
          compras: [
            _compra('L1'),
            _compra('L2', data: hojeExemplo, qtd: 20),
          ],
        ),
      ]);
    await _abrir(t, s);
    expect(_chamadasSugestoes(s), 1);
    await _expandir(t, 'PETR4');
    expect(find.textContaining('Qtd. digitada'), findsNothing);

    await t.enterText(find.byKey(const ValueKey('qtd-PETR4')), '40');
    await t.pump(const Duration(milliseconds: 100));
    // a espera de 300 ms entre teclas ainda não acabou
    expect(find.textContaining('Qtd. digitada (40)'), findsNothing);
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.textContaining('Qtd. digitada (40)'), findsWidgets);

    expect(find.textContaining('no preço digitado'), findsNothing);
    await _digitar(t, 'preco-PETR4', '10,50');
    expect(find.textContaining('no preço digitado'), findsWidgets);

    await _aoTopo(t);
    await t.tap(find.text('Day trade'));
    await t.pumpAndSettle();
    await t.tap(find.text('Swing'));
    await t.pumpAndSettle();
    expect(_chamadasSugestoes(s), 1);
  });

  testWidgets('falha da fonte em um ticker não quebra a tela', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _ativo('PETR4'),
        _ativo(
          'VALE3',
          estado: EstadoDados.falha,
          mensagem: 'Sem conexão com a internet.',
          semBarras: true,
        ),
      ]);
    await _abrir(t, s);
    expect(find.text('Sem conexão com a internet.'), findsOneWidget);
    expect(find.textContaining('Alvo R\$'), findsOneWidget);
  });

  testWidgets('dados desatualizados mostram data e hora', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _ativo(
          'PETR4',
          estado: EstadoDados.desatualizado,
          fimBarras: '2026-10-23',
          cotacao: CotacaoInfo(
            preco: 10,
            hora: DataHora.parse('2026-10-26T17:30:00-03:00'),
            fonte: 'Yahoo',
            atual: false,
          ),
        ),
      ]);
    await _abrir(t, s);
    expect(find.textContaining('Dados desatualizados'), findsOneWidget);
    expect(find.textContaining('26/10/2026 17:30'), findsWidgets);
    expect(find.textContaining('23/10/2026'), findsWidgets);
  });

  testWidgets('meta financeira separada do cenário', (t) async {
    final a = _ativo('PETR4');
    final s = ServicosFalsos()..visaoSugestoes = _visao([a]);
    await _abrir(t, s);
    await _expandir(t, 'PETR4');
    expect(find.text('Ponto de equilíbrio'), findsOneWidget);
    expect(find.text('Meta financeira (simulação)'), findsOneWidget);
    expect(find.text('Cenário de mercado'), findsOneWidget);
    expect(find.textContaining('por ação, sem taxas'), findsWidgets);

    // meta alcançável: sem aviso
    await _digitar(t, 'lucro-PETR4', '50');
    expect(
      find.text('Meta acima do cenário de mercado para o horizonte'),
      findsNothing,
    );
    // meta muito acima do alvo: o aviso aparece e o cenário não muda
    final c = _cenario(a);
    await _digitar(t, 'lucro-PETR4', '5000');
    expect(
      find.text('Meta acima do cenário de mercado para o horizonte'),
      findsOneWidget,
    );
    expect(find.textContaining(brl(c.alvo!)), findsWidgets);
    expect(find.textContaining('na meta'), findsWidgets);
    expect(s.ultimaMetaAlvo, isNull);
  });

  group('criar meta de alvo e stop', () {
    testWidgets('sem oportunidade fica desativado; com oportunidade usa o '
        'alvo e o stop do cenário, depois da confirmação', (t) async {
      final bom = _ativo('PETR4', topo: 12.5);
      final ruim = _ativo('VALE3', topo: 10.2);
      final c = _cenario(bom);
      expect(c.oportunidade, isTrue);
      expect(_cenario(ruim).oportunidade, isFalse);
      final s = ServicosFalsos()..visaoSugestoes = _visao([bom, ruim]);
      await _abrir(t, s);
      expect(find.text('Sem oportunidade identificada'), findsWidgets);
      await _expandir(t, 'VALE3');
      expect(_botao(t, 'Criar meta de alvo e stop').onPressed, isNull);
      await _expandir(t, 'VALE3'); // fecha
      await _aoTopo(t);
      await _expandir(t, 'PETR4');
      expect(_botao(t, 'Criar meta de alvo e stop').onPressed, isNotNull);

      // 'Voltar' não cria nada
      await _tocar(t, find.text('Criar meta de alvo e stop'));
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Voltar'));
      await t.pumpAndSettle();
      expect(s.ultimaMetaAlvo, isNull);
      expect(s.ultimoStop, isNull);

      await _tocar(t, find.text('Criar meta de alvo e stop'));
      await t.tap(find.text('Criar metas'));
      await t.pumpAndSettle();
      expect(s.ultimaMetaAlvo?.loteId, 'L1');
      expect(s.ultimaMetaAlvo?.qtd, 100);
      expect(s.ultimaMetaAlvo?.preco, c.alvo);
      expect(s.ultimoStop?.preco, c.stop);
      expect(s.ultimoStop?.qtd, 100);
      expect(s.ultimoStop?.movel, isFalse);
      expect(s.ultimoStop?.precoAtual, 10);
      // o stop nasce ligado (OCO) ao alvo recém-criado
      expect(s.ultimoStop?.ocoCom, isNotNull);
    });

    testWidgets('sem quantidade livre avisa e não cria', (t) async {
      final s = ServicosFalsos()
        ..visaoMetas = const VisaoMetas(
          metas: [],
          descricoes: {},
          lotes: [],
          ativas: 0,
        )
        ..visaoSugestoes = _visao([_ativo('PETR4')]);
      await _abrir(t, s);
      await _expandir(t, 'PETR4');
      await _tocar(t, find.text('Criar meta de alvo e stop'));
      expect(find.textContaining('Não há quantidade livre'), findsOneWidget);
      expect(s.ultimaMetaAlvo, isNull);
    });
  });

  testWidgets('horizonte e fonte sempre visíveis no alvo', (t) async {
    final s = ServicosFalsos()..visaoSugestoes = _visao([_ativo('PETR4')]);
    await _abrir(t, s);
    // sem expandir
    expect(find.textContaining('5 a 20 pregões'), findsWidgets);
    expect(find.textContaining('Yahoo'), findsWidgets);
    expect(find.textContaining('28/10/2026 11:55'), findsWidgets);
  });

  testWidgets('Atualizar recarrega e o pedido antigo é descartado', (t) async {
    final lenta = Completer<VisaoSugestoes>();
    var n = 0;
    final s = ServicosFalsos()
      ..sugestoesMetasFn = (_) {
        n++;
        return switch (n) {
          2 => lenta.future,
          3 => Future.value(
            _visao([
              _ativo(
                'TERC3',
                estado: EstadoDados.falha,
                mensagem: 'terceira',
                semBarras: true,
              ),
            ]),
          ),
          _ => Future.value(_visao([])),
        };
      };
    await _abrir(t, s);
    await t.tap(find.text('Atualizar'));
    await t.pump();
    await t.tap(find.text('Atualizar'));
    await t.pumpAndSettle();
    expect(find.text('terceira'), findsOneWidget);
    lenta.complete(
      _visao([
        _ativo(
          'SEGU3',
          estado: EstadoDados.falha,
          mensagem: 'segunda',
          semBarras: true,
        ),
      ]),
    );
    await t.pumpAndSettle();
    expect(find.text('segunda'), findsNothing);
    expect(find.text('terceira'), findsOneWidget);
  });
}
