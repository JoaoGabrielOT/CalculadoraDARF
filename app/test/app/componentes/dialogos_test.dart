import 'package:calculadoradarf/app/componentes/dialogos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  Future<BuildContext> contexto(WidgetTester t) async {
    await montarComponente(t, const SizedBox());
    return t.element(find.byType(SizedBox).first);
  }

  testWidgets('confirmar devolve true em Sim e false em Cancelar/Esc', (
    t,
  ) async {
    final c = await contexto(t);

    var f = confirmar(c, 'Excluir', 'Tem certeza?');
    await t.pumpAndSettle();
    expect(find.text('Excluir'), findsOneWidget);
    expect(find.text('Tem certeza?'), findsOneWidget);
    await t.tap(find.text('Sim'));
    await t.pumpAndSettle();
    expect(await f, isTrue);

    f = confirmar(c, 'Excluir', 'Tem certeza?', sim: 'Apagar', perigo: true);
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(await f, isFalse);

    f = confirmar(c, 'Excluir', 'Tem certeza?');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(await f, isFalse);
  });

  testWidgets('avisar mostra o texto e fecha em OK', (t) async {
    final c = await contexto(t);
    final f = avisar(c, 'Atenção', 'Algo aconteceu.');
    await t.pumpAndSettle();
    expect(find.text('Algo aconteceu.'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await f;
    expect(find.text('Algo aconteceu.'), findsNothing);
  });
}
