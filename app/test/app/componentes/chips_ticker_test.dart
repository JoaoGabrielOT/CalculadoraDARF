import 'package:calculadoradarf/app/componentes/chips_ticker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  testWidgets('ChipsTicker marca o escolhido e avisa o toque', (t) async {
    String? escolhido;
    await montarComponente(
      t,
      ChipsTicker(
        tickers: const ['PETR4', 'VALE3'],
        marcado: 'VALE3',
        aoEscolher: (v) => escolhido = v,
      ),
    );
    expect(find.text('Frequentes'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await t.tap(find.text('PETR4'));
    expect(escolhido, 'PETR4');
  });

  testWidgets('ChipsTicker sem tickers não mostra nada', (t) async {
    await montarComponente(
      t,
      ChipsTicker(tickers: const [], aoEscolher: (_) {}),
    );
    expect(find.text('Frequentes'), findsNothing);
  });
}
