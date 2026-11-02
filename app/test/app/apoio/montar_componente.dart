// Monta um componente isolado com tema, pt-BR e `Scaffold`, sem serviços.

import 'package:calculadoradarf/app/tema/temas.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> montarComponente(
  WidgetTester t,
  Widget filho, {
  TemaVisual tema = TemaVisual.claro,
  Size tamanho = const Size(800, 600),
  Widget Function(Widget)? envolver,
}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final app = MaterialApp(
    locale: const Locale('pt', 'BR'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('pt', 'BR')],
    theme: temaDe(resolverTema(tema, Brightness.light)),
    home: Scaffold(body: Center(child: filho)),
  );
  await t.pumpWidget(envolver == null ? app : envolver(app));
}
