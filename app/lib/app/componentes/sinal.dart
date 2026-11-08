// Cor de um resultado pelo sinal: lucro no verde do tema, perda no vermelho,
// zero ou sem dado na cor normal do texto. A seta vem do texto
// (`textoResultado`), para o sentido não depender só da cor.

import 'package:flutter/material.dart';

import '../regras/apresentacao.dart';
import '../tema/cores_app.dart';

extension CorDoSinal on CoresApp {
  /// Nulo no neutro: o texto fica na cor padrão.
  Color? doSinal(Sinal s) => switch (s) {
    Sinal.alta => alta,
    Sinal.queda => queda,
    Sinal.neutro => null,
  };

  Color? doValor(double? v) => doSinal(sinalDe(v));
}
