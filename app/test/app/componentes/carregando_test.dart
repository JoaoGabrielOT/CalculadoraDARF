import 'package:calculadoradarf/app/componentes/carregando.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  testWidgets('Carregando mostra o indicador e o texto opcional', (t) async {
    await montarComponente(t, const Carregando(texto: 'Buscando cotações...'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Buscando cotações...'), findsOneWidget);
    await montarComponente(t, const Carregando());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Esqueleto ocupa o tamanho pedido', (t) async {
    await montarComponente(t, const Esqueleto(largura: 120, altura: 14));
    expect(t.getSize(find.byType(Esqueleto)), const Size(120, 14));
  });
}
