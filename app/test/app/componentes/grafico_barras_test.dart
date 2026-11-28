import 'package:calculadoradarf/app/componentes/grafico_barras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  const barras = [
    BarraGrafico('Último preço', 10, 'R\$ 10,00'),
    BarraGrafico('Alvo médio', 15, 'R\$ 15,00', cor: Colors.green),
    BarraGrafico('Alvo mín', 5, 'R\$ 5,00', cor: Colors.red),
  ];

  testWidgets('mostra valor e rótulo de cada barra em 360 px', (t) async {
    await montarComponente(
      t,
      const SizedBox(width: 300, child: GraficoBarras(barras: barras)),
      tamanho: const Size(360, 600),
    );
    for (final b in barras) {
      expect(find.text(b.texto), findsOneWidget);
      expect(find.text(b.rotulo), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('pintor: uma barra por valor, repinta só se mudar', (t) async {
    await montarComponente(
      t,
      const SizedBox(width: 300, child: GraficoBarras(barras: barras)),
    );
    final pintor =
        t
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(GraficoBarras),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as PintorBarras;
    expect(pintor.valores, [10, 15, 5]);
    final igual = PintorBarras(
      valores: pintor.valores,
      cores: pintor.cores,
      base: pintor.base,
    );
    expect(igual.shouldRepaint(pintor), isFalse);
    expect(
      PintorBarras(
        valores: const [1],
        cores: const [Colors.red],
        base: pintor.base,
      ).shouldRepaint(pintor),
      isTrue,
    );
  });

  testWidgets('lista vazia e valores zerados não quebram', (t) async {
    await montarComponente(
      t,
      const SizedBox(width: 300, child: GraficoBarras(barras: [])),
    );
    expect(t.takeException(), isNull);
    await montarComponente(
      t,
      const SizedBox(
        width: 300,
        child: GraficoBarras(barras: [BarraGrafico('a', 0, '0')]),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
