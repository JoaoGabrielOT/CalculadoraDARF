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
  preco: 32.5,
);

Projecao _proj() => Projecao(
  c: ResultadoVenda(
    dt: false,
    compra: 3250,
    venda: 3600,
    taxas: 1,
    corretagem: 0,
    bruto: 350,
    liquido: 349,
  ),
  imposto: 0,
  irrf: 0,
  darfEstimado: 0,
  custos: 1,
  lucroAposImposto: 349,
);

Sugestao _sug({
  String modo = 'swing',
  bool movel = true,
  bool stopValido = true,
  double? atr22 = 1.23456789,
}) => Sugestao(
  modo: modo,
  atr14: 0.987654321,
  atr22: atr22,
  stopInicial: 30,
  chandelier: movel ? 31 : null,
  pp: 35,
  r1: 36,
  s1: 34,
  stop: 31.5,
  alvo: 36,
  movelDisponivel: movel,
  baseData: '2026-11-06',
)..stopValido = stopValido;

ItemSugestao _item({
  Sugestao? sug,
  String? erro,
  AlertaRisco? alerta,
  double perda = -150,
}) {
  final item = ItemSugestao(
    lote: _lote,
    qtd: 60,
    sug: erro == null ? (sug ?? _sug()) : null,
    erro: erro,
    precoAtual: 33,
    alerta: alerta,
  );
  if (erro == null) {
    item.aval = Avaliacao(
      projAlvo: _proj(),
      projStop: _proj(),
      lucroAlvo: 349,
      perdaStop: perda,
      distAlvoPct: 9.09,
      distStopPct: -4.54,
    );
  }
  return item;
}

SugestaoPosicao _pos(ItemSugestao item, {int livre = 60}) => SugestaoPosicao(
  posicao: (
    mes: '2026-10',
    lote: _lote,
    restante: 100,
    livre: livre,
    ativas: <Meta>[],
  ),
  qtd: 60,
  item: item,
);

VisaoSugestoes _visao(List<SugestaoPosicao> itens) => VisaoSugestoes(
  itens: itens,
  rodape: const [('Patrimônio considerado', 'R\$ 10.000,00', null)],
);

Future<ServicosFalsos> _abrir(WidgetTester t, ServicosFalsos s) async {
  s.visaoMetas ??= const VisaoMetas(
    metas: [],
    descricoes: {},
    lotes: [],
    ativas: 0,
  );
  await abrirNoTeste<void>(t, s, abrirMetas, tamanho: _pc);
  return s;
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
  testWidgets('carregando sem travar e cartões quando chega', (t) async {
    final espera = Completer<VisaoSugestoes>();
    var n = 0;
    final s = ServicosFalsos()
      ..sugestoesMetasFn = () =>
          n++ == 0 ? Future.value(_visao([])) : espera.future;
    await _abrir(t, s);
    await t.tap(find.text('Atualizar'));
    await t.pump();
    expect(find.text('Carregando sugestões…'), findsOneWidget);
    expect(find.text('Atualizar'), findsOneWidget);
    espera.complete(_visao([_pos(_item())]));
    await t.pumpAndSettle();
    expect(find.textContaining('Atualizado às '), findsOneWidget);
    expect(
      find.text('PETR4 · 100 un. a R\$ 32,50 · compra de 05/10/2026'),
      findsOneWidget,
    );
    expect(
      find.text('60 un. livres para metas · cálculo para 60 un.'),
      findsOneWidget,
    );
    expect(find.text('Criar meta de alvo'), findsOneWidget);
    expect(find.text('Criar stop fixo'), findsOneWidget);
    expect(find.text('Criar stop móvel'), findsOneWidget);
    expect(find.text('PATRIMÔNIO CONSIDERADO'), findsOneWidget);
    expect(find.text(avisoSugestao), findsOneWidget);
    expect(find.text(avisoProventos), findsOneWidget);
  });

  testWidgets("sem posições: 'Nenhuma compra em aberto.'", (t) async {
    await _abrir(t, ServicosFalsos());
    expect(find.text('Nenhuma compra em aberto.'), findsOneWidget);
  });

  testWidgets('erro do Yahoo no cartão com mensagemErro', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _pos(_item(erro: 'Sem conexão com a internet.')),
      ]);
    await _abrir(t, s);
    expect(find.text('Sem conexão com a internet.'), findsOneWidget);
    expect(find.text('Criar meta de alvo'), findsNothing);
  });

  testWidgets('stop móvel só no swing com móvel disponível; stops '
      'desabilitados sem stopValido', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _pos(_item(sug: _sug(modo: 'day_trade', movel: false))),
        _pos(_item(sug: _sug(stopValido: false))),
      ]);
    await _abrir(t, s);
    expect(find.text('Criar stop móvel'), findsOneWidget);
    expect(find.text('Criar stop fixo'), findsNWidgets(2));
    expect(_botao(t, 'Criar stop fixo').onPressed, isNotNull);
    expect(_botao(t, 'Criar stop fixo', indice: 1).onPressed, isNull);
    expect(_botao(t, 'Criar stop móvel').onPressed, isNull);
  });

  testWidgets('alerta de 2% do patrimônio aparece no cartão', (t) async {
    final s = ServicosFalsos()
      ..visaoSugestoes = _visao([
        _pos(_item(alerta: AlertaRisco(pct: 3.5, limite: 200, excede: true))),
      ]);
    await _abrir(t, s);
    expect(find.text('ALERTA DE RISCO'), findsOneWidget);
    expect(
      find.textContaining('3,50% do patrimônio; o limite de 2% é R\$ 200,00'),
      findsOneWidget,
    );
  });

  group('criar', () {
    testWidgets('alvo sem parceira usa a quantidade livre; depois verifica e '
        'recarrega as sugestões', (t) async {
      final s = ServicosFalsos()..visaoSugestoes = _visao([_pos(_item())]);
      await _abrir(t, s);
      s.chamadas.clear();
      await t.tap(find.text('Criar meta de alvo'));
      await t.pumpAndSettle();
      expect(s.ultimaMetaAlvo?.qtd, 60);
      expect(s.ultimaMetaAlvo?.preco, 36);
      expect(s.ultimoOcoAlvo, isNull);
      final nomes = s.chamadas.map((c) => c.split('(').first).toList();
      expect(nomes, containsAllInOrder(['criarMetaAlvo', 'verificarMetas']));
      expect(
        nomes.sublist(nomes.indexOf('verificarMetas')),
        contains('sugestoesMetas'),
      );
    });

    testWidgets("com parceira OCO pergunta 'Ligar em OCO' e usa a quantidade "
        "da parceira; 'Voltar' não cria", (t) async {
      final parceira = metasExemplo().first; // M1, alvo, 60 un.
      final s = ServicosFalsos()
        ..visaoSugestoes = _visao([_pos(_item(), livre: 10)])
        ..parceirasOco['stop'] = parceira;
      await _abrir(t, s);
      await t.tap(find.text('Criar stop fixo'));
      await t.pumpAndSettle();
      expect(find.text('Ligar em OCO'), findsOneWidget);
      expect(
        find.textContaining(
          'Será ligado (OCO) à meta ${descricao(parceira).titulo}.\n\n'
          'Quando uma das duas executar, a outra é cancelada '
          'automaticamente. Quantidade: 60 un.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Voltar'));
      await t.pumpAndSettle();
      expect(s.ultimoStop, isNull);
      await t.tap(find.text('Criar stop fixo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Criar com OCO'));
      await t.pumpAndSettle();
      expect(s.ultimoStop?.ocoCom, 'M1');
      expect(s.ultimoStop?.qtd, 60);
    });

    testWidgets('sem quantidade livre avisa e não cria', (t) async {
      final s = ServicosFalsos()
        ..visaoSugestoes = _visao([_pos(_item(), livre: 0)]);
      await _abrir(t, s);
      await t.tap(find.text('Criar meta de alvo'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Não há quantidade livre nesta compra: cancele uma meta ativa '
          'antes.',
        ),
        findsOneWidget,
      );
      expect(s.ultimaMetaAlvo, isNull);
    });

    testWidgets('stop móvel passa movel: true e o dicionário sugestao', (
      t,
    ) async {
      final s = ServicosFalsos()..visaoSugestoes = _visao([_pos(_item())]);
      await _abrir(t, s);
      await t.tap(find.text('Criar stop móvel'));
      await t.pumpAndSettle();
      final st = s.ultimoStop!;
      expect(st.movel, isTrue);
      expect(st.preco, 31.5);
      expect(st.precoAtual, 33);
      expect(st.sugestao, {
        'modo': 'swing',
        'atr14': 0.9877,
        'compra': 32.5,
        'atr22': 1.2346,
      });
    });

    testWidgets('stop fixo sem atr22 não leva a chave', (t) async {
      final s = ServicosFalsos()
        ..visaoSugestoes = _visao([_pos(_item(sug: _sug(atr22: null)))]);
      await _abrir(t, s);
      await t.tap(find.text('Criar stop fixo'));
      await t.pumpAndSettle();
      expect(s.ultimoStop!.movel, isFalse);
      expect(s.ultimoStop!.sugestao!.containsKey('atr22'), isFalse);
    });

    testWidgets('erro do serviço vira aviso', (t) async {
      final s = ServicosFalsos()
        ..visaoSugestoes = _visao([_pos(_item())])
        ..erros['criarMetaAlvo'] = ArgumentError('preço inválido');
      await _abrir(t, s);
      await t.tap(find.text('Criar meta de alvo'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Meta'), findsOneWidget);
    });
  });

  testWidgets('Atualizar recarrega e o pedido antigo é descartado', (t) async {
    final lenta = Completer<VisaoSugestoes>();
    var n = 0;
    final s = ServicosFalsos()
      ..sugestoesMetasFn = () {
        n++;
        return switch (n) {
          2 => lenta.future,
          3 => Future.value(_visao([_pos(_item(erro: 'terceira'))])),
          _ => Future.value(_visao([])),
        };
      };
    await _abrir(t, s);
    await t.tap(find.text('Atualizar'));
    await t.pump();
    await t.tap(find.text('Atualizar'));
    await t.pumpAndSettle();
    expect(find.text('terceira'), findsOneWidget);
    lenta.complete(_visao([_pos(_item(erro: 'segunda'))]));
    await t.pumpAndSettle();
    expect(find.text('segunda'), findsNothing);
    expect(find.text('terceira'), findsOneWidget);
  });
}
