import 'package:calculadoradarf/app/componentes/campo_data.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/montar_componente.dart';

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: '2026-10-28'));

  testWidgets(
    'CampoData: Hoje e Ontem preenchem; data fora dos limites some dos chips; texto inválido não aceita o valor inválido',
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

      // Texto inválido não deixa a data antiga valendo: o pai recebe null.
      await t.enterText(find.byType(TextField), '31/02/2026');
      await t.pump();
      expect(valor, isNull);
      await t.tap(find.text('Ontem'));
      await t.pump();
      expect(valor, '2026-10-27');
      await t.enterText(find.byType(TextField), 'abc');
      await t.pump();
      expect(valor, isNull);
      expect(chamadas, greaterThan(2));

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

  testWidgets('CampoData: data fora do período zera o valor e mostra o erro', (
    t,
  ) async {
    String? valor = '2026-10-15';
    await montarComponente(
      t,
      StatefulBuilder(
        builder: (c, set) => CampoData(
          valor: valor,
          minimo: '2026-10-01',
          maximo: '2026-10-31',
          aoMudar: (v) => set(() => valor = v),
        ),
      ),
    );
    await t.enterText(find.byType(TextField), '15/09/2026');
    await t.pump();
    expect(valor, isNull);
    expect(find.text('Data fora do período permitido.'), findsOneWidget);
    // O texto digitado fica (o pai zerou o valor, o campo não o apaga).
    expect(find.widgetWithText(TextField, '15/09/2026'), findsOneWidget);
  });

  testWidgets(
    'CampoData: erro aparece na data impossível e, ao sair, no texto incompleto',
    (t) async {
      await montarComponente(t, CampoData(aoMudar: (_) {}));
      await t.enterText(find.byType(TextField), '30/2/2026');
      await t.pump();
      expect(find.text('Data inválida.'), findsOneWidget);

      await t.enterText(find.byType(TextField), '12/1');
      await t.pump();
      expect(find.text('Data inválida.'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
      expect(find.text('Data inválida.'), findsOneWidget);
    },
  );

  testWidgets('CampoData: sem limites, o texto segue os do calendário', (
    t,
  ) async {
    String? valor;
    await montarComponente(t, CampoData(aoMudar: (v) => valor = v));
    // Depois de hoje (2026-10-28) e antes de 2000: o calendário não deixa.
    await t.enterText(find.byType(TextField), '29/10/2026');
    await t.pump();
    expect(valor, isNull);
    await t.enterText(find.byType(TextField), '31/12/1999');
    await t.pump();
    expect(valor, isNull);
    await t.enterText(find.byType(TextField), '01/01/2000');
    await t.pump();
    expect(valor, '2000-01-01');
  });

  testWidgets('CampoData: desmontar com o foco no campo não dá erro', (
    t,
  ) async {
    await montarComponente(t, CampoData(aoMudar: (_) {}));
    await t.enterText(find.byType(TextField), '12/1');
    await t.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    await montarComponente(t, const SizedBox());
    await t.pump();
    expect(t.takeException(), isNull);
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
