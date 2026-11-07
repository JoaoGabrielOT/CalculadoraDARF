import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/telas/metas/tela_metas.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/servicos_falsos.dart';

/// Alta o bastante para o diálogo de 900 px mostrar a calculadora inteira.
const _pc = Size(1366, 1000);
const _celular = Size(400, 850);

Lote _lote(String id, String ticker, int qtd, double preco, String data) =>
    Lote(
      id: id,
      ticker: ticker,
      tipo: 'Ação',
      dataCompra: data,
      qtd: qtd,
      preco: preco,
    );

final _l1 = _lote('L1', 'PETR4', 100, 32.5, '2026-10-05');
final _l2 = _lote('L2', 'VALE3', 200, 60.1, '2026-10-08');

List<LoteLivre> _lotes() => [
  (mes: '2026-10', lote: _l1, livre: 60),
  (mes: '2026-10', lote: _l2, livre: 200),
];

VisaoMetas _visao(List<Meta> metas, {List<LoteLivre>? lotes}) => VisaoMetas(
  metas: metas,
  descricoes: {for (final m in metas) m.id: descricao(m, todas: metas)},
  lotes: lotes ?? _lotes(),
  ativas: metas.where((m) => m.statusOuAtiva == 'ativa').length,
);

Projecao _proj({
  double custos = 20,
  double imposto = 150,
  double bruto = 1234.56,
  double apos = 1084.56,
  double irrf = 0,
}) => Projecao(
  c: ResultadoVenda(
    dt: false,
    compra: 1950,
    venda: 3184.56,
    taxas: custos - 5,
    corretagem: 5,
    bruto: bruto,
    liquido: bruto - custos,
  ),
  imposto: imposto,
  irrf: irrf,
  darfEstimado: imposto,
  custos: custos,
  lucroAposImposto: apos,
);

PrecoAlvo _alvo({bool dayTrade = false, double irrf = 0}) {
  final p = _proj(irrf: irrf);
  return PrecoAlvo(
    p: p,
    preco: 21.78,
    precoExato: 21.7712,
    precoMedio: 32.5,
    brutoNecessario: 1176.47,
    lucroDesejado: 1000,
    qtd: 60,
    dayTrade: dayTrade,
  );
}

EstadoApp _estado(WidgetTester t) => Provider.of<EstadoApp>(
  t.element(find.byType(Scaffold).first),
  listen: false,
);

Future<ServicosFalsos> _abrir(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
}) async {
  final s = servicos ?? ServicosFalsos();
  s.visaoMetas ??= _visao(metasExemplo().reversed.toList());
  await abrirNoTeste<void>(t, s, abrirMetas, tamanho: tamanho);
  return s;
}

Future<void> _irParaCalculadora(WidgetTester t) async {
  await t.tap(find.text('Calculadora'));
  await t.pumpAndSettle();
}

Future<void> _digitar(WidgetTester t, String chave, String texto) async {
  await t.enterText(campo(chave), texto);
  await t.pumpAndSettle();
}

Meta _meta(
  String id,
  String criada, {
  String status = 'ativa',
  String ticker = 'PETR4',
  double alvo = 40,
}) => Meta(
  id: id,
  ticker: ticker,
  tipo: 'Ação',
  loteId: 'L1',
  qtd: 10,
  precoAlvo: alvo,
  criadaEm: criada,
  status: status,
);

void main() {
  group('textoVerificacao', () {
    test('textos dos quatro resultados', () {
      expect(
        textoVerificacao(VerificacaoConcluida(RelatorioMetas()), '14:05'),
        'Verificado às 14:05.',
      );
      expect(
        textoVerificacao(const VerificacaoEmAndamento(), '14:05'),
        'Verificação já em andamento.',
      );
      expect(
        textoVerificacao(const SemMetasAtivas(), '14:05'),
        'Não há metas ativas para verificar.',
      );
      expect(
        textoVerificacao(
          const VerificacaoFalhou('Sem conexão com a internet.'),
          '14:05',
        ),
        'Não foi possível verificar: Sem conexão com a internet.',
      );
    });
  });

  group('Verificar agora', () {
    testWidgets(
      "mostra 'Verificando o histórico de preços…' e depois o texto",
      (t) async {
        final espera = Completer<ResultadoVerificacao>();
        final s = ServicosFalsos()..verificarMetasFn = () => espera.future;
        await _abrir(t, servicos: s);
        await t.tap(find.text('Verificar agora'));
        await t.pump();
        expect(find.text('Verificando o histórico de preços…'), findsOneWidget);
        // o botão fica desabilitado enquanto verifica
        await t.tap(find.text('Verificar agora'));
        await t.pump();
        expect(
          s.chamadas.where((c) => c.startsWith('verificarMetas')),
          hasLength(1),
        );
        espera.complete(VerificacaoConcluida(RelatorioMetas()));
        await t.pumpAndSettle();
        expect(find.textContaining('Verificado às '), findsOneWidget);
        expect(find.text('Verificando o histórico de preços…'), findsNothing);
      },
    );

    testWidgets("com falha nunca diz 'em andamento' e libera o botão", (
      t,
    ) async {
      final s = ServicosFalsos()
        ..resultadoVerificacao = const VerificacaoFalhou(
          'Sem conexão com a internet.',
        );
      await _abrir(t, servicos: s);
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(
        find.text('Não foi possível verificar: Sem conexão com a internet.'),
        findsOneWidget,
      );
      expect(find.textContaining('em andamento'), findsNothing);
      // liberado: a próxima verificação chama o serviço de novo
      s.resultadoVerificacao = VerificacaoConcluida(RelatorioMetas());
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(find.textContaining('Verificado às '), findsOneWidget);
      expect(
        s.chamadas.where((c) => c.startsWith('verificarMetas')),
        hasLength(2),
      );
    });

    testWidgets('exceção do serviço mostra o erro real e libera o botão', (
      t,
    ) async {
      final s = ServicosFalsos()..erros['verificarMetas'] = ErroValidacao('x');
      await _abrir(t, servicos: s);
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(find.text('Não foi possível verificar: x'), findsOneWidget);
      s.erros.clear();
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(
        s.chamadas.where((c) => c.startsWith('verificarMetas')),
        hasLength(2),
      );
    });

    testWidgets('sem metas ativas e já em andamento', (t) async {
      final s = ServicosFalsos();
      await _abrir(t, servicos: s);
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(find.text('Não há metas ativas para verificar.'), findsOneWidget);
      s.resultadoVerificacao = const VerificacaoEmAndamento();
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      expect(find.text('Verificação já em andamento.'), findsOneWidget);
    });

    testWidgets('uma meta executada na verificação vira aviso', (t) async {
      final rel = RelatorioMetas()
        ..mudou = true
        ..executadas.add(
          _meta('M1', '2026-10-21T11:00:00-03:00', status: 'executada')
            ..execucao = {
              'preco_usado': 40.0,
              'data': '2026-10-28',
              'hora': '10:15',
              'motivo': 'Máxima do dia chegou ao alvo.',
            },
        );
      final s = ServicosFalsos()
        ..resultadoVerificacao = VerificacaoConcluida(rel);
      await _abrir(t, servicos: s);
      await t.tap(find.text('Verificar agora'));
      await t.pumpAndSettle();
      final avisos = _estado(t).avisos;
      expect(avisos, hasLength(1));
      expect(avisos.single.titulo, 'Meta atingida');
    });
  });

  group('lista', () {
    testWidgets(
      'ordenada por criação, com status colorido e Cancelar só nas ativas',
      (t) async {
        final metas = [
          _meta('A', '2026-10-23T11:00:00-03:00', ticker: 'AAAA3'),
          _meta(
            'B',
            '2026-10-22T11:00:00-03:00',
            status: 'cancelada',
            ticker: 'BBBB3',
          ),
          _meta(
            'C',
            '2026-10-21T11:00:00-03:00',
            status: 'executada',
            ticker: 'CCCC3',
          )..ultimoErro = 'Falha ao gravar a venda.',
        ];
        final s = ServicosFalsos()..visaoMetas = _visao(metas);
        await _abrir(t, servicos: s);
        final y = [
          for (final tk in ['AAAA3', 'BBBB3', 'CCCC3'])
            t.getTopLeft(find.textContaining('$tk · 10 un.')).dy,
        ];
        expect(y[0] < y[1] && y[1] < y[2], isTrue);
        expect(find.text('Cancelar meta'), findsOneWidget);
        final cores = CoresApp.de(t.element(find.text('Ativa')));
        expect(t.widget<Text>(find.text('Ativa')).style?.color, cores.aviso);
        expect(
          t.widget<Text>(find.text('Cancelada')).style?.color,
          cores.textoSuave,
        );
        expect(t.widget<Text>(find.text('Executada')).style?.color, cores.alta);
        // detalhe com erro em vermelho
        final detalhe = find.textContaining('Falha ao gravar a venda.');
        expect(t.widget<Text>(detalhe).style?.color, cores.queda);
        expect(
          find.textContaining('Criada em 23/10/2026 11:00'),
          findsOneWidget,
        );
      },
    );

    testWidgets('lista vazia', (t) async {
      final s = ServicosFalsos()..visaoMetas = _visao([]);
      await _abrir(t, servicos: s);
      expect(find.text('Nenhuma meta criada.'), findsOneWidget);
    });

    testWidgets('cancelar confirma com o texto do Python', (t) async {
      final s = ServicosFalsos()
        ..visaoMetas = _visao([_meta('A', '2026-10-23T11:00:00-03:00')]);
      await _abrir(t, servicos: s);
      await t.tap(find.text('Cancelar meta'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'A venda automática não será mais registrada para esta meta.',
        ),
        findsOneWidget,
      );
      // Voltar não cancela
      await t.tap(find.text('Voltar'));
      await t.pumpAndSettle();
      expect(s.chamadas.where((c) => c.startsWith('cancelarMeta')), isEmpty);
      // confirmar cancela e relê a lista
      final antes = s.chamadas.where((c) => c == 'metas()').length;
      await t.tap(find.text('Cancelar meta'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Cancelar meta'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('cancelarMeta(A)'));
      expect(
        s.chamadas.where((c) => c == 'metas()').length,
        greaterThan(antes),
      );
    });

    testWidgets('cancelar com erro do serviço mostra o aviso "Meta"', (
      t,
    ) async {
      final s = ServicosFalsos()
        ..visaoMetas = _visao([_meta('A', '2026-10-23T11:00:00-03:00')])
        ..erros['cancelarMeta'] = ErroValidacao('Essa meta já foi executada.');
      await _abrir(t, servicos: s);
      await t.tap(find.text('Cancelar meta'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Cancelar meta'));
      await t.pumpAndSettle();
      expect(find.text('Meta'), findsOneWidget);
      expect(find.text('Essa meta já foi executada.'), findsOneWidget);
    });
  });

  group('Calculadora', () {
    ServicosFalsos servicos() => ServicosFalsos()
      ..precoAlvo = _alvo(irrf: 0.5)
      ..projecaoFn = (preco) =>
          _proj(custos: 25, imposto: 30, bruto: 300, apos: -50);

    testWidgets('escolher compra preenche a quantidade livre', (t) async {
      await _abrir(t, servicos: servicos());
      await _irParaCalculadora(t);
      expect(campoTexto(t, 'meta-qtd').controller?.text, '60');
      await t.tap(find.byKey(const ValueKey('meta-compra')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('VALE3').last);
      await t.pumpAndSettle();
      expect(campoTexto(t, 'meta-qtd').controller?.text, '200');
      expect(
        find.textContaining('VALE3 · 08/10/2026 · R\$ 60,10 · 200 livres'),
        findsWidgets,
      );
    });

    testWidgets('calcular preenche o preço-alvo e as linhas', (t) async {
      final s = servicos();
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      expect(
        find.text('Informe a quantidade e o lucro líquido desejado.'),
        findsOneWidget,
      );
      await _digitar(t, 'meta-lucro', '1000');
      expect(s.chamadas, contains('calcularPrecoAlvo(L1, 60, 1000.0)'));
      expect(campoTexto(t, 'meta-preco').controller?.text, '21,78');
      expect(find.text('Lucro líquido desejado'), findsOneWidget);
      expect(find.text('R\$ 1.000,00'), findsOneWidget);
      expect(find.text('R\$ 32,50'), findsOneWidget);
      expect(find.text('R\$ 20,00'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsOneWidget);
      expect(find.text('R\$ 21,78'), findsOneWidget);
      expect(find.text('R\$ 1.234,56'), findsOneWidget);
      expect(find.text('R\$ 1.084,56'), findsOneWidget);
      expect(
        find.textContaining(
          'Swing trade (15%) · custos: taxas B3 R\$ 15,00 + '
          'corretagem R\$ 5,00. IRRF retido estimado: R\$ 0,50 (abate da DARF).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Estimativa conservadora: sem isenção de R\$ 20 mil e sem prejuízos '
          'anteriores.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('quantidade acima da livre', (t) async {
      final s = servicos();
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await _digitar(t, 'meta-lucro', '1000');
      await _digitar(t, 'meta-qtd', '61');
      expect(find.text('Quantidade maior que a livre (60).'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsNothing);
    });

    testWidgets('erro do núcleo vira nota e não deixa linhas', (t) async {
      final s = servicos()
        ..erros['calcularPrecoAlvo'] = ErroValidacao(
          'Com esse resultado o preço de venda seria zero ou negativo.',
        );
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await _digitar(t, 'meta-lucro', '1000');
      expect(
        find.text(
          'Com esse resultado o preço de venda seria zero ou negativo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('editar o preço reprojeta', (t) async {
      final s = servicos();
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await _digitar(t, 'meta-lucro', '1000');
      await _digitar(t, 'meta-preco', '25,50');
      expect(s.chamadas, contains('projetarPreco(L1, 60, 25.5)'));
      expect(find.text('R\$ 25,00'), findsOneWidget); // custo
      expect(find.text('R\$ 30,00'), findsOneWidget); // imposto
      expect(find.text('-R\$ 50,00'), findsOneWidget); // líquido negativo
      final cores = CoresApp.de(t.element(find.text('-R\$ 50,00')));
      expect(t.widget<Text>(find.text('-R\$ 50,00')).style?.color, cores.queda);
      // o sugerido não muda
      expect(find.text('R\$ 21,78'), findsOneWidget);
    });

    testWidgets('criar mostra a mensagem de sucesso e envia os valores', (
      t,
    ) async {
      final s = servicos();
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await _digitar(t, 'meta-lucro', '1000');
      await t.ensureVisible(find.text('Criar venda automática com este preço'));
      await t.tap(find.text('Criar venda automática com este preço'));
      await t.pumpAndSettle();
      expect(s.ultimaMetaAlvo, (
        loteId: 'L1',
        qtd: 60,
        preco: 21.78,
        lucro: 1000.0,
      ));
      expect(
        find.text(
          'Meta criada. O app vai registrar a venda quando o preço-alvo for '
          'atingido.',
        ),
        findsOneWidget,
      );
      // verifica logo depois de criar
      expect(
        s.chamadas.where((c) => c.startsWith('verificarMetas')),
        hasLength(1),
      );
    });

    testWidgets('criar com erro do serviço mostra o texto', (t) async {
      final s = servicos()
        ..erros['criarMetaAlvo'] = ErroValidacao('Quantidade acima da livre.');
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await _digitar(t, 'meta-lucro', '1000');
      await t.ensureVisible(find.text('Criar venda automática com este preço'));
      await t.tap(find.text('Criar venda automática com este preço'));
      await t.pumpAndSettle();
      expect(find.text('Quantidade acima da livre.'), findsOneWidget);
      expect(s.chamadas.where((c) => c.startsWith('verificarMetas')), isEmpty);
    });

    testWidgets('validações locais do criar', (t) async {
      final s = servicos();
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      await t.ensureVisible(find.text('Criar venda automática com este preço'));
      await _digitar(t, 'meta-qtd', 'abc');
      await t.tap(find.text('Criar venda automática com este preço'));
      await t.pumpAndSettle();
      expect(find.text('Quantidade inválida.'), findsOneWidget);
      await _digitar(t, 'meta-qtd', '10');
      await _digitar(t, 'meta-preco', '');
      await t.tap(find.text('Criar venda automática com este preço'));
      await t.pumpAndSettle();
      expect(find.text('Preço-alvo inválido.'), findsOneWidget);
      expect(s.ultimaMetaAlvo, isNull);
    });

    testWidgets('sem compra em aberto', (t) async {
      final s = servicos()..visaoMetas = _visao([], lotes: []);
      await _abrir(t, servicos: s);
      await _irParaCalculadora(t);
      expect(find.text('Nenhuma compra em aberto'), findsOneWidget);
      await t.ensureVisible(find.text('Criar venda automática com este preço'));
      await t.tap(find.text('Criar venda automática com este preço'));
      await t.pumpAndSettle();
      expect(
        find.text('Não há compra em aberto para criar a meta.'),
        findsOneWidget,
      );
    });
  });

  group('janela', () {
    testWidgets('expandido: diálogo com abas à esquerda e METAS à direita', (
      t,
    ) async {
      await _abrir(t);
      expect(find.text('Meta de lucro / Preço-alvo'), findsOneWidget);
      expect(
        find.text('Registro automático no app; não envia ordem à corretora'),
        findsOneWidget,
      );
      expect(find.text('Sugestões'), findsOneWidget);
      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.text('METAS'), findsOneWidget);
      final dialogo = t.getSize(find.byKey(const ValueKey('metas-dialogo')));
      expect(dialogo.width, 900);
    });

    testWidgets('compacto: tela cheia com abas', (t) async {
      await _abrir(t, tamanho: _celular);
      expect(find.byType(TabBar), findsOneWidget);
      await t.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Metas')),
      );
      await t.pumpAndSettle();
      expect(find.text('Verificar agora'), findsOneWidget);
      expect(find.textContaining('PETR4 · 60 un. a'), findsOneWidget);
      expect(find.textContaining('VALE3 · 100 un. · stop'), findsOneWidget);
    });

    testWidgets('com amigo na tela volta para "Meus dados" antes de abrir', (
      t,
    ) async {
      final s = ServicosFalsos();
      await _abrir(t, servicos: s);
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
      final estado = _estado(t);
      await estado.trocarVisao('amigo@exemplo.com');
      await t.pumpAndSettle();
      expect(estado.amigo, 'amigo@exemplo.com');
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(estado.amigo, isNull);
      expect(s.chamadas, contains('esquecerAmigo()'));
      expect(find.text('Meta de lucro / Preço-alvo'), findsOneWidget);
    });
  });

  group('avisos do relatório (EventoMetas)', () {
    Meta executada(String id, {String? gatilho}) =>
        Meta(
            id: id,
            ticker: 'PETR4',
            loteId: 'L1',
            qtd: 60,
            precoAlvo: gatilho == 'stop' ? null : 40,
            gatilho: gatilho,
            stopAtual: gatilho == 'stop' ? 30 : null,
            criadaEm: '2026-10-21T11:00:00-03:00',
            status: 'executada',
          )
          ..execucao = {
            'preco_usado': 40.0,
            'data': '2026-10-28',
            'hora': '10:15',
            'motivo': 'Máxima do dia chegou ao alvo.',
          };

    const registro = 'Registro automático no app; não envia ordem à corretora.';

    testWidgets('EventoMetas abre o diálogo com os textos do Windows', (
      t,
    ) async {
      final s = ServicosFalsos();
      await montarApp(t, servicos: s, tamanho: _pc);
      await t.pumpAndSettle();
      s.eventosFalsos.add(
        EventoMetas(RelatorioMetas()..executadas.add(executada('M1'))),
      );
      await t.pumpAndSettle();
      expect(find.text('Meta atingida'), findsOneWidget);
      expect(
        find.text(
          'PETR4: venda de 60 a R\$ 40,00 registrada em 28/10/2026 10:15.\n\n'
          'Máxima do dia chegou ao alvo.\n\n$registro',
        ),
        findsOneWidget,
      );
    });

    test('stop atingido leva o aviso do gap', () {
      final aviso = avisoRelatorioMetas(
        RelatorioMetas()..executadas.add(executada('M1', gatilho: 'stop')),
      )!;
      expect(aviso.$1, 'Stop atingido');
      expect(
        aviso.$2,
        'PETR4: venda de 60 a R\$ 40,00 registrada em 28/10/2026 10:15.\n\n'
        'Máxima do dia chegou ao alvo.\n$avisoGap\n\n$registro',
      );
    });

    test('inválidas e avisos manuais', () {
      final inv = avisoRelatorioMetas(
        RelatorioMetas()
          ..invalidas.add(
            _meta('I', '2026-10-21T11:00:00-03:00', status: 'inválida')
              ..ultimoErro = 'Compra não existe mais.',
          ),
      )!;
      expect(inv.$1, 'Meta inválida');
      expect(inv.$2, 'PETR4: Compra não existe mais.');
      final man = avisoRelatorioMetas(
        RelatorioMetas()..avisos.add('Ajuste a venda duplicada.'),
      )!;
      expect(man.$1, 'Ajuste manual necessário');
      expect(man.$2, 'Ajuste a venda duplicada.');
      expect(avisoRelatorioMetas(RelatorioMetas()), isNull);
    });

    test('vários itens num diálogo só, com cada título', () {
      final aviso = avisoRelatorioMetas(
        RelatorioMetas()
          ..executadas.addAll([executada('M1'), executada('M2')])
          ..avisos.add('Ajuste a venda duplicada.'),
      )!;
      expect(aviso.$1, 'Metas');
      expect('Meta atingida'.allMatches(aviso.$2), hasLength(2));
      expect(aviso.$2, contains('Ajuste manual necessário\n'));
      // dois alvos: mesmo título, um diálogo só
      final dois = avisoRelatorioMetas(
        RelatorioMetas()..executadas.addAll([executada('M1'), executada('M2')]),
      )!;
      expect(dois.$1, 'Meta atingida');
      expect('PETR4: venda de'.allMatches(dois.$2), hasLength(2));
    });
  });
}
