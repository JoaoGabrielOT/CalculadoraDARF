import 'package:calculadoradarf/app/componentes/campo_data.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: '2026-10-28'));

  testWidgets(
    'CampoData: Hoje e Ontem preenchem; data fora dos limites some dos chips; texto inválido não muda o valor',
    (t) async {
      String? valor;
      var chamadas = 0;
      await montarComponente(
        t,
        StatefulBuilder(
          builder: (c, set) => CampoData(
            valor: valor,
            aoMudar: (v) => set(() {
              valor = v;
              chamadas++;
            }),
          ),
        ),
      );
      await t.tap(find.text('Hoje'));
      await t.pump();
      expect(valor, '2026-10-28');
      expect(find.widgetWithText(TextField, '28/10/2026'), findsOneWidget);
      await t.tap(find.text('Ontem'));
      await t.pump();
      expect(valor, '2026-10-27');

      final antes = chamadas;
      await t.enterText(find.byType(TextField), '31/02/2026');
      await t.pump();
      await t.enterText(find.byType(TextField), 'abc');
      await t.pump();
      expect(valor, '2026-10-27');
      expect(chamadas, antes);

      await t.enterText(find.byType(TextField), '05/10/2026');
      await t.pump();
      expect(valor, '2026-10-05');

      // Limites: só ontem permitido; "Hoje" some.
      await montarComponente(
        t,
        CampoData(maximo: '2026-10-27', minimo: '2026-10-01', aoMudar: (_) {}),
      );
      expect(find.text('Hoje'), findsNothing);
      expect(find.text('Ontem'), findsOneWidget);

      // Permitido customizado também esconde o chip.
      await montarComponente(
        t,
        CampoData(permitido: (iso) => iso != '2026-10-27', aoMudar: (_) {}),
      );
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Ontem'), findsNothing);
    },
  );

  testWidgets('CampoData: data fora dos limites digitada não é aceita', (
    t,
  ) async {
    String? valor;
    await montarComponente(
      t,
      CampoData(
        minimo: '2026-10-01',
        maximo: '2026-10-31',
        aoMudar: (v) => valor = v,
      ),
    );
    await t.enterText(find.byType(TextField), '15/09/2026');
    await t.pump();
    expect(valor, isNull);
    await t.enterText(find.byType(TextField), '15/10/2026');
    await t.pump();
    expect(valor, '2026-10-15');
  });

  testWidgets('CampoData: calendário respeita os dias permitidos', (t) async {
    String? valor;
    await montarComponente(
      t,
      CampoData(
        valor: '2026-10-15',
        minimo: '2026-10-01',
        maximo: '2026-10-31',
        permitido: (iso) => iso != '2026-10-20',
        aoMudar: (v) => valor = v,
      ),
    );
    await t.tap(find.byIcon(Icons.calendar_month));
    await t.pumpAndSettle();
    await t.tap(find.text('20'));
    await t.pump();
    // Dia bloqueado: o seletor continua aberto sem escolher nada.
    expect(valor, isNull);
    await t.tap(find.text('22'));
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(valor, '2026-10-22');
  });
}
