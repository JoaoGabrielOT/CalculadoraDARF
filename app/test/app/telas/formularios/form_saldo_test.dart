import 'package:calculadoradarf/app/componentes/controles.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/dados_exemplo.dart';
import '../../apoio/servicos_falsos.dart';

/// Resumo com saldo definido (R$ 5.000 e nenhuma movimentação pendente
/// relevante para o texto testado) ou sem saldo.
ResumoCaixa _resumo({required bool definido}) {
  final base = caixaExemplo().resumo;
  return ResumoCaixa(
    definido: definido,
    base: base.base,
    saldoBase: base.saldoBase,
    entrou: base.entrou,
    disponivel: definido ? 5000 : 0,
    aDebitar: base.aDebitar,
    aReceber: base.aReceber,
    transito: base.transito,
    projetado: base.projetado,
    itens: base.itens,
  );
}

Future<ResultadoForm<VisaoCaixa>> _abrir(
  WidgetTester t,
  ServicosFalsos s, {
  required bool definido,
  ModoSaldo modo = ModoSaldo.definir,
  Size tamanho = const Size(1366, 768),
}) => abrirNoTeste<VisaoCaixa>(
  t,
  s,
  (c) => abrirFormSaldo(c, _resumo(definido: definido), modo),
  tamanho: tamanho,
);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  testWidgets("sem saldo definido só 'Definir saldo'", (t) async {
    await _abrir(t, ServicosFalsos(), definido: false);
    expect(find.text('Saldo em conta'), findsOneWidget);
    expect(
      find.text('Informe o saldo livre na conta da corretora hoje.'),
      findsOneWidget,
    );
    expect(find.text('Definir saldo'), findsOneWidget);
    expect(find.text('Aporte'), findsNothing);
    expect(find.text('Retirada'), findsNothing);
    expect(campoTexto(t, 'valor').controller!.text, '');
    expect(find.text('Saldo disponível hoje (R\$)'), findsOneWidget);
  });

  testWidgets('com saldo definido mostra os três modos e o saldo atual', (
    t,
  ) async {
    await _abrir(t, ServicosFalsos(), definido: true);
    expect(find.text('Saldo disponível hoje: R\$ 5.000,00'), findsOneWidget);
    expect(find.text('Definir saldo'), findsOneWidget);
    expect(find.text('Aporte'), findsOneWidget);
    expect(find.text('Retirada'), findsOneWidget);
    expect(campoTexto(t, 'valor').controller!.text, '5000,00');
  });

  for (final (nome, tamanho, altura) in [
    ('PC', const Size(1366, 768), 40.0),
    ('celular 360', const Size(360, 800), 48.0),
  ]) {
    testWidgets('$nome: modos num Segmentado de largura cheia e rodapé com '
        'Cancelar em texto e Salvar cheio', (t) async {
      await _abrir(t, ServicosFalsos(), definido: true, tamanho: tamanho);
      final seg = find.byType(Segmentado<ModoSaldo>);
      expect(seg, findsOneWidget);
      expect(t.getSize(seg).height, altura);
      for (final r in ['Definir saldo', 'Aporte', 'Retirada']) {
        final rotulo = find.descendant(of: seg, matching: find.text(r));
        expect(rotulo, findsOneWidget);
        expect(t.getSize(rotulo).height, lessThan(22));
      }
      // mesma largura do campo logo abaixo
      expect(
        t.getSize(seg).width,
        t.getSize(find.byKey(const Key('valor'))).width,
      );
      final cancelar = find.widgetWithText(TextButton, 'Cancelar');
      final salvar = find.widgetWithText(FilledButton, 'Salvar');
      expect(cancelar, findsOneWidget);
      expect(salvar, findsOneWidget);
      expect(t.getSize(cancelar).height, altura);
      expect(t.getSize(salvar).height, altura);
      expect(t.getCenter(cancelar).dy, t.getCenter(salvar).dy);
      expect(t.getTopLeft(salvar).dx, greaterThan(t.getTopRight(cancelar).dx));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('trocar o modo muda rótulo e ajuda', (t) async {
    await _abrir(t, ServicosFalsos(), definido: true);
    expect(
      find.text(
        'Use o saldo livre que a corretora mostra hoje, já com as '
        'liquidações de hoje.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Aporte'));
    await t.pump();
    expect(find.text('Valor do aporte (R\$)'), findsOneWidget);
    expect(find.text('Soma ao saldo disponível.'), findsOneWidget);
    expect(campoTexto(t, 'valor').controller!.text, '');
    await t.tap(find.text('Retirada'));
    await t.pump();
    // gênero errado como no Python (calculadora_darf.py:563; android:1639)
    expect(find.text('Valor do retirada (R\$)'), findsOneWidget);
    expect(find.text('Desconta do saldo disponível.'), findsOneWidget);
  });

  testWidgets('modo inicial aporte muda o título e começa vazio', (t) async {
    await _abrir(t, ServicosFalsos(), definido: true, modo: ModoSaldo.aporte);
    expect(find.text('Aporte'), findsNWidgets(2)); // título e opção
    expect(find.text('Valor do aporte (R\$)'), findsOneWidget);
    expect(campoTexto(t, 'valor').controller!.text, '');
  });

  testWidgets('validações: valor inválido e valor zero em aporte', (t) async {
    final s = ServicosFalsos();
    await _abrir(t, s, definido: true);
    await t.enterText(campo('valor'), 'abc');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Valor inválido.'), findsOneWidget);
    await t.tap(find.text('Aporte'));
    await t.pump();
    await t.enterText(campo('valor'), '0');
    await t.tap(find.text('Salvar'));
    await t.pump();
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
    expect(s.ultimoSaldo, isNull);
  });

  testWidgets('salvar chama alterarSaldo com o modo e devolve a visão', (
    t,
  ) async {
    final s = ServicosFalsos();
    final r = await _abrir(t, s, definido: true);
    await t.tap(find.text('Aporte'));
    await t.pump();
    await t.enterText(campo('valor'), '250,50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.ultimoSaldo?.modo, ModoSaldo.aporte);
    expect(s.ultimoSaldo?.valor, 250.5);
    expect(r.valor, isNotNull);
  });

  testWidgets('erro do serviço aparece no rodapé sem fechar', (t) async {
    final s = ServicosFalsos()
      ..erros['alterarSaldo'] = ErroValidacao('Valor inválido.');
    final r = await _abrir(t, s, definido: false);
    await t.enterText(campo('valor'), '100');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('Valor inválido.'), findsOneWidget);
    expect(r.concluido, isFalse);
  });

  testWidgets('compacto: tela cheia', (t) async {
    await _abrir(
      t,
      ServicosFalsos(),
      definido: true,
      tamanho: const Size(360, 800),
    );
    expect(find.byType(AppBar), findsOneWidget);
  });
}
