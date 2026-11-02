import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calculadoradarf/app/componentes/logo_ativo.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/montar_componente.dart';

class _ServicosLogo implements ServicosApp {
  final pedidos = <String>[];
  final respostas = <String, Completer<ImagemBytes?>>{};

  @override
  Future<ImagemBytes?> logo(String ticker) {
    pedidos.add(ticker);
    return (respostas[ticker] ??= Completer()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

void main() {
  Widget Function(Widget) com(_ServicosLogo s) =>
      (app) => Provider<ServicosApp>.value(value: s, child: app);

  testWidgets(
    'LogoAtivo: mostra iniciais e troca pela imagem quando chega; não pede duas vezes o mesmo ticker',
    (t) async {
      final s = _ServicosLogo();
      await montarComponente(
        t,
        const EscopoLogos(
          child: Column(
            children: [
              LogoAtivo(ticker: 'PETR4'),
              LogoAtivo(ticker: 'PETR4'),
              LogoAtivo(ticker: 'VALE3', tamanho: 20),
            ],
          ),
        ),
        envolver: com(s),
      );
      expect(find.text('PETR'), findsNWidgets(2));
      expect(find.text('VALE'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      s.respostas['PETR4']!.complete(ImagemBytes(bytes: _png, svg: false));
      await t.pump();
      await t.pump();
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('PETR'), findsNothing);
      expect(find.text('VALE'), findsOneWidget);

      expect(s.pedidos, ['PETR4', 'VALE3']);
    },
  );

  testWidgets('LogoAtivo: sem logo ou com erro continua nas iniciais', (
    t,
  ) async {
    final s = _ServicosLogo();
    await montarComponente(
      t,
      const EscopoLogos(
        child: Column(
          children: [
            LogoAtivo(ticker: 'ABCD3'),
            LogoAtivo(ticker: 'XYZW4'),
          ],
        ),
      ),
      envolver: com(s),
    );
    s.respostas['ABCD3']!.complete(null);
    s.respostas['XYZW4']!.completeError(StateError('rede'));
    await t.pump();
    await t.pump();
    expect(find.text('ABCD'), findsOneWidget);
    expect(find.text('XYZW'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
