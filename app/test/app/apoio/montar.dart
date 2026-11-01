// Monta o app (ou uma tela) com serviços e plataforma falsos para os testes
// de widget.

import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/plataforma/plataforma.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/tema/temas.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'plataforma_falsa.dart';
import 'servicos_falsos.dart';

/// Sem [tela], monta o `AppCalculadora` inteiro; com [tela], monta só ela
/// debaixo dos mesmos provedores e do tema.
Future<void> montarApp(
  WidgetTester t, {
  ServicosFalsos? servicos,
  PlataformaFalsa? plataforma,
  Size tamanho = const Size(1366, 768),
  TemaVisual tema = TemaVisual.claro,
  Widget? tela,
}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final s = servicos ?? ServicosFalsos();
  s.estadoInicial ??= EstadoInicial(
    mesInicial: s.mesAberto,
    mesesComDados: s.meses,
    preferencias: Preferencias(tema: tema),
  );
  final p = plataforma ?? PlataformaFalsa();
  if (tela == null) {
    await t.pumpWidget(AppCalculadora(servicos: s, plataforma: p));
  } else {
    await t.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ServicosApp>.value(value: s),
          Provider<Plataforma>.value(value: p),
          ChangeNotifierProvider<EstadoApp>(
            lazy: false,
            create: (_) => EstadoApp(s, p)..iniciar(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('pt', 'BR'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('pt', 'BR')],
          theme: temaDe(resolverTema(tema, Brightness.light)),
          home: tela,
        ),
      ),
    );
  }
  await t.pump();
  await t.pump();
}
