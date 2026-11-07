// Apoio do teste de integração: cliente HTTP sem rede e capturas de tela.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:calculadoradarf/app/app.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Cliente do isolate de serviços: responde 503 a tudo (cotações, logos,
/// notícias e Google falham como numa queda do servidor).
http.Client criarClienteSemRede() =>
    MockClient((_) async => http.Response('indisponível', 503));

const _pastaCapturas = String.fromEnvironment('CAPTURAS');

/// Grava `<CAPTURAS>/<nome>.png` com o que está em [chaveCaptura]; sem
/// `--dart-define=CAPTURAS=...` não faz nada.
Future<void> capturar(WidgetTester t, String nome) async {
  if (_pastaCapturas.isEmpty) return;
  await t.pump();
  final limite =
      chaveCaptura.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final imagem = await limite.toImage(pixelRatio: 1);
  final png = await imagem.toByteData(format: ui.ImageByteFormat.png);
  imagem.dispose();
  final arquivo = File('$_pastaCapturas/$nome.png');
  await arquivo.parent.create(recursive: true);
  await arquivo.writeAsBytes(png!.buffer.asUint8List());
}
