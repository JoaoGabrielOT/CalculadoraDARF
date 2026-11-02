// Indicadores de carregamento: nunca bloqueiam a interface, só ocupam o lugar
// do que ainda não chegou.

import 'package:flutter/material.dart';

import '../tema/cores_app.dart';

class Carregando extends StatelessWidget {
  const Carregando({super.key, this.texto});

  final String? texto;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: c.navAtivo,
            semanticsLabel: texto ?? 'Carregando',
          ),
          if (texto != null) ...[
            const SizedBox(height: 12),
            Text(texto!, style: TextStyle(color: c.textoSuave)),
          ],
        ],
      ),
    );
  }
}

/// Barra cinza no lugar de um texto ou valor que ainda não chegou. Sem
/// [largura], ocupa a largura disponível (o pai precisa limitá-la).
class Esqueleto extends StatelessWidget {
  const Esqueleto({super.key, this.largura, this.altura = 16});

  final double? largura;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: largura ?? double.infinity,
        height: altura,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.linha,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
