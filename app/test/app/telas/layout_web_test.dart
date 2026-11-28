// Web no celular: alturas baixas, paisagem e teclado aberto sem overflow.

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
import 'package:calculadoradarf/app/telas/login_web/tela_login_web.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/abrir_formulario.dart';
import '../apoio/dados_exemplo.dart';
import '../apoio/montar.dart';
import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

const _tamanhos = [Size(320, 568), Size(390, 844), Size(667, 375)];

PlataformaFalsa _web() => PlataformaFalsa(web: true, windows: false);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  for (final tamanho in _tamanhos) {
    testWidgets('com token, a casca cabe em $tamanho', (t) async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(
          temCredencial: true,
          temToken: true,
          email: 'eu@gmail.com',
          status: StatusSync.ok,
        );
      await montarApp(t, servicos: s, plataforma: _web(), tamanho: tamanho);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(Casca), findsOneWidget);
    });

    testWidgets('a tela de login cabe em $tamanho', (t) async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(temCredencial: true);
      await montarApp(t, servicos: s, plataforma: _web(), tamanho: tamanho);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TelaLoginWeb), findsOneWidget);
    });
  }

  for (final tamanho in const [Size(320, 568), Size(667, 375)]) {
    testWidgets('AppBar e faixa do amigo cabem em $tamanho', (t) async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(
          temCredencial: true,
          temToken: true,
          email: 'eu@gmail.com',
          status: StatusSync.ok,
        );
      await montarApp(t, servicos: s, plataforma: _web(), tamanho: tamanho);
      await t.pumpAndSettle();
      final estado = Provider.of<EstadoApp>(
        t.element(find.byType(Casca)),
        listen: false,
      );
      await estado.trocarVisao('nome.bem.comprido.de.verdade@exemplo.com');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Voltar aos meus'), findsOneWidget);
      expect(find.byTooltip('Atualizar'), findsWidgets);
    });
  }

  testWidgets('formulário de compra com o teclado aberto', (t) async {
    final s = ServicosFalsos();
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(t.view.resetViewInsets);
    await abrirNoTeste<VisaoMes>(
      t,
      s,
      (c) => abrirFormCompra(c, s.visoes['2026-10']!),
      tamanho: const Size(390, 844),
      plataforma: _web(),
    );
    expect(t.takeException(), isNull);
    final salvar = find.text('Salvar');
    await t.ensureVisible(salvar);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(salvar.hitTestable(), findsOneWidget);
  });
}
