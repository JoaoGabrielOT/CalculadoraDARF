import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/dados_exemplo.dart';
import '../../apoio/servicos_falsos.dart';

VisaoMes _visao(ServicosFalsos s) => s.visoes['2026-10']!;

Future<ResultadoForm<VisaoMes>> _abrir(
  WidgetTester t,
  ServicosFalsos s, {
  Map<String, String>? iniciais,
  Lote? editar,
  Size tamanho = const Size(1366, 768),
}) => abrirNoTeste<VisaoMes>(
  t,
  s,
  (c) => abrirFormCompra(c, _visao(s), iniciais: iniciais, editar: editar),
  tamanho: tamanho,
);

/// O campo de data é o único `TextField` sem chave do formulário.
Finder get _campoData => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Data',
);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets(
    'chips Frequentes preenchem o ticker, mostram o tipo e focam a quantidade',
    (t) async {
      await _abrir(t, ServicosFalsos());
      expect(find.text('Novo ativo'), findsOneWidget);
      expect(find.text('Dados da compra'), findsOneWidget);
      expect(find.text('Frequentes'), findsOneWidget);
      await t.tap(find.text('PETR4'));
      await t.pump();
      expect(campoTexto(t, 'ticker').controller!.text, 'PETR4');
      expect(
        find.text('Tipo: Ação (identificado pelo ticker)'),
        findsOneWidget,
      );
      expect(campoTexto(t, 'qtd').focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    "resumo muda ao digitar e mostra 'Preencha quantidade, preço e data.' "
    'quando incompleto',
    (t) async {
      await _abrir(t, ServicosFalsos());
      expect(find.text('Preencha quantidade, preço e data.'), findsOneWidget);
      await t.enterText(campo('qtd'), '100');
      await t.enterText(campo('preco'), '10');
      await t.pump();
      expect(find.text('Preencha quantidade, preço e data.'), findsNothing);
      expect(find.text('R\$ 1.000,00'), findsOneWidget);
      expect(find.textContaining('Será debitado da conta: '), findsOneWidget);
      expect(find.textContaining('Liquidação financeira'), findsOneWidget);
      expect(find.textContaining('day trade'), findsOneWidget);
      await t.enterText(campo('qtd'), '200');
      await t.pump();
      expect(find.text('R\$ 2.000,00'), findsOneWidget);
      // data apagada: incompleto de novo
      await t.enterText(_campoData, '');
      await t.pump();
      expect(find.text('Preencha quantidade, preço e data.'), findsOneWidget);
    },
  );

  testWidgets('erro do serviço aparece no rodapé sem fechar', (t) async {
    final s = ServicosFalsos()
      ..erros['registrarCompra'] = ErroValidacao('O mês está fechado.');
    final r = await _abrir(t, s);
    await t.enterText(campo('ticker'), 'petr4');
    await t.enterText(campo('qtd'), '100');
    await t.enterText(campo('preco'), '32,50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('O mês está fechado.'), findsOneWidget);
    expect(find.text('Novo ativo'), findsOneWidget);
    expect(r.concluido, isFalse);
  });

  testWidgets('validação local mostra a mensagem do Python sem chamar o '
      'serviço', (t) async {
    final s = ServicosFalsos();
    await _abrir(t, s);
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Informe o ticker.'), findsOneWidget);
    await t.enterText(campo('ticker'), 'PETR4');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Quantidade inválida.'), findsOneWidget);
    expect(s.chamadas.where((c) => c.startsWith('registrarCompra')), isEmpty);
  });

  testWidgets('data inválida bloqueia o salvar e nunca usa a data anterior', (
    t,
  ) async {
    final s = ServicosFalsos();
    await _abrir(t, s);
    await t.enterText(campo('ticker'), 'PETR4');
    await t.enterText(campo('qtd'), '100');
    await t.enterText(campo('preco'), '32,50');
    await t.enterText(_campoData, '31/02/2026');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Selecione a data da compra.'), findsOneWidget);
    expect(s.ultimaCompra, isNull);
  });

  testWidgets('salvar devolve a visão nova; Enter também salva', (t) async {
    final s = ServicosFalsos();
    final r = await _abrir(t, s);
    await t.enterText(campo('ticker'), 'petr4');
    await t.enterText(campo('qtd'), '100');
    await t.enterText(campo('preco'), '32,50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(r.valor?.mes, '2026-10');
    expect(s.ultimaCompra?.ticker, 'PETR4');
    expect(s.ultimaCompra?.dataCompra, hojeExemplo);
    expect(s.ultimaCompra?.qtd, 100);
    expect(s.ultimaCompra?.preco, 32.5);

    final s2 = ServicosFalsos();
    final r2 = await _abrir(t, s2);
    await t.enterText(campo('ticker'), 'VALE3');
    await t.enterText(campo('qtd'), '10');
    await t.enterText(campo('preco'), '60');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(r2.concluido, isTrue);
    expect(s2.ultimaCompra?.ticker, 'VALE3');
  });

  testWidgets('Esc cancela e devolve nulo', (t) async {
    final r = await _abrir(t, ServicosFalsos());
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(r.concluido, isTrue);
    expect(r.valor, isNull);
    expect(find.text('Novo ativo'), findsNothing);
  });

  testWidgets(
    "editar: preenche os campos, mostra 'Já vendidas' e limita a data à "
    'primeira venda',
    (t) async {
      final s = ServicosFalsos();
      final lote = mesAbertoExemplo().lotes.first; // PETR4, 40 vendidas
      await _abrir(t, s, editar: lote);
      expect(find.text('Editar compra'), findsOneWidget);
      expect(find.text('Já vendidas: 40'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, 'PETR4');
      expect(campoTexto(t, 'qtd').controller!.text, '100');
      expect(campoTexto(t, 'preco').controller!.text, '32,50');
      expect(find.text('05/10/2026'), findsOneWidget);
      // depois da primeira venda (20/10) a data é recusada
      await t.enterText(_campoData, '21/10/2026');
      await t.pump();
      expect(find.text('Data fora do período permitido.'), findsOneWidget);
      expect(find.text('Hoje'), findsNothing);
      await t.enterText(_campoData, '10/10/2026');
      await t.enterText(campo('qtd'), '30'); // menos do que já foi vendido
      await t.tap(find.text('Salvar'));
      await t.pump();
      expect(s.chamadas.where((c) => c.startsWith('editarCompra')), isEmpty);
      expect(find.textContaining('vendid'), findsWidgets);
      await t.enterText(campo('qtd'), '80');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(s.ultimaCompra?.dataCompra, '2026-10-10');
      expect(s.chamadas.last, 'editarCompra(2026-10, L1, PETR4)');
    },
  );

  testWidgets('iniciais preenchem os campos e focam a quantidade', (t) async {
    await _abrir(
      t,
      ServicosFalsos(),
      iniciais: {'ticker': 'VALE3', 'qtd': '5'},
    );
    expect(campoTexto(t, 'ticker').controller!.text, 'VALE3');
    expect(campoTexto(t, 'qtd').controller!.text, '5');
    expect(campoTexto(t, 'qtd').focusNode!.hasFocus, isTrue);
  });

  testWidgets('compacto: tela cheia com botões de 48 dp', (t) async {
    await _abrir(t, ServicosFalsos(), tamanho: const Size(360, 800));
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final salvar = t.getSize(find.widgetWithText(FilledButton, 'Salvar'));
    expect(salvar.height, greaterThanOrEqualTo(48));
  });

  testWidgets('expandido: diálogo de 420 px', (t) async {
    await _abrir(t, ServicosFalsos());
    expect(find.byType(AppBar), findsNothing);
    expect(
      t.getSize(find.byKey(const ValueKey('quadro-formulario'))).width,
      420,
    );
  });
}
