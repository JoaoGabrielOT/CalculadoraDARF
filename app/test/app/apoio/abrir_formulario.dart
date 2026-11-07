// Abre um formulário a partir de um botão de teste e guarda o resultado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'montar.dart';
import 'plataforma_falsa.dart';
import 'servicos_falsos.dart';

class ResultadoForm<T> {
  T? valor;
  bool concluido = false;
}

Future<ResultadoForm<T>> abrirNoTeste<T>(
  WidgetTester t,
  ServicosFalsos servicos,
  Future<T?> Function(BuildContext) abrir, {
  Size tamanho = const Size(1366, 768),
  PlataformaFalsa? plataforma,
}) async {
  final r = ResultadoForm<T>();
  await montarApp(
    t,
    servicos: servicos,
    plataforma: plataforma,
    tamanho: tamanho,
    tela: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              r.valor = await abrir(c);
              r.concluido = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
  return r;
}

/// Campo de texto de um formulário pela chave.
Finder campo(String chave) => find.byKey(ValueKey(chave));

/// O `TextField` de [chave].
TextField campoTexto(WidgetTester t, String chave) =>
    t.widget<TextField>(campo(chave));
