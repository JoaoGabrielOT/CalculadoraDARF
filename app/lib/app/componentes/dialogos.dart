// Diálogos de confirmação e de aviso (calculadora_darf.py:104-112).

import 'package:flutter/material.dart';

import '../tema/cores_app.dart';

/// Pergunta Sim/Cancelar. Fechar pelo Esc ou fora do diálogo vale como [nao].
Future<bool> confirmar(
  BuildContext c,
  String titulo,
  String texto, {
  String sim = 'Sim',
  String nao = 'Cancelar',
  bool perigo = false,
}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) {
      final cores = CoresApp.de(ctx);
      // Texto legível sobre o vermelho do tema: escuro se o vermelho é claro.
      final sobreQueda =
          ThemeData.estimateBrightnessForColor(cores.queda) == Brightness.light
          ? cores.fundo
          : cores.cartao;
      return AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(nao),
          ),
          FilledButton(
            style: perigo
                ? FilledButton.styleFrom(
                    backgroundColor: cores.queda,
                    foregroundColor: sobreQueda,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(sim),
          ),
        ],
      );
    },
  );
  return r ?? false;
}

Future<void> avisar(BuildContext c, String titulo, String texto) {
  return showDialog<void>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
