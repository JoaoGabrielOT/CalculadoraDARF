import 'package:calculadoradarf/app/componentes/grafico_linha.dart';
import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  PintorLinha pintor(WidgetTester t) {
    final cp = t.widget<CustomPaint>(
      find.descendant(
        of: find.byType(GraficoLinha),
        matching: find.byType(CustomPaint),
      ),
    );
    return cp.painter! as PintorLinha;
  }

  CoresApp cores(WidgetTester t) =>
      CoresApp.de(t.element(find.byType(GraficoLinha)));

  const pontos = [(0, 10.0), (10, 20.0), (20, 15.0), (30, 12.0)];

  Widget grafico({
    double? referencia,
    Color? cor,
    bool interativo = false,
    ValueChanged<(int, double)?>? aoTocar,
  }) => SizedBox(
    width: 300,
    height: 100,
    child: GraficoLinha(
      pontos: pontos,
      referencia: referencia,
      cor: cor,
      interativo: interativo,
      aoTocar: aoTocar,
    ),
  );

  testWidgets('GraficoLinha: tocar devolve o ponto mais próximo', (t) async {
    (int, double)? tocado;
    await montarComponente(
      t,
      grafico(interativo: true, aoTocar: (p) => tocado = p),
    );
    final topo = t.getTopLeft(find.byType(GraficoLinha));
    await t.tapAt(topo + const Offset(10, 50));
    expect(tocado, (0, 10.0));
    await t.tapAt(topo + const Offset(290, 50));
    expect(tocado, (30, 12.0));
    await t.tapAt(topo + const Offset(110, 50));
    expect(tocado, (10, 20.0));
  });

  testWidgets('GraficoLinha: não interativo ignora toques', (t) async {
    var chamadas = 0;
    await montarComponente(t, grafico(aoTocar: (_) => chamadas++));
    await t.tap(find.byType(GraficoLinha));
    expect(chamadas, 0);
  });

  testWidgets('GraficoLinha: cor de alta quando último > referência', (
    t,
  ) async {
    await montarComponente(t, grafico(referencia: 11));
    expect(pintor(t).cor, cores(t).alta);

    await montarComponente(t, grafico(referencia: 13));
    expect(pintor(t).cor, cores(t).queda);

    await montarComponente(t, grafico(referencia: 13, cor: Colors.purple));
    expect(pintor(t).cor, Colors.purple);
  });

  testWidgets('GraficoLinha: poucos pontos não quebra', (t) async {
    await montarComponente(
      t,
      const SizedBox(
        width: 300,
        height: 100,
        child: GraficoLinha(pontos: [(0, 5.0)]),
      ),
    );
    await montarComponente(
      t,
      const SizedBox(width: 300, height: 100, child: GraficoLinha(pontos: [])),
    );
    expect(t.takeException(), isNull);
  });
}
