// Atalhos de tickers (os mais usados) para preencher um campo de ativo.

import 'package:flutter/material.dart';

import '../tema/cores_app.dart';
import 'cartao.dart';

class ChipsTicker extends StatelessWidget {
  const ChipsTicker({
    super.key,
    required this.tickers,
    this.marcado,
    required this.aoEscolher,
    this.titulo = 'Frequentes',
  });

  final List<String> tickers;
  final String? marcado;
  final ValueChanged<String> aoEscolher;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    if (tickers.isEmpty) return const SizedBox.shrink();
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tickers)
              ChipFiltro(
                rotulo: t,
                selecionado: t == marcado,
                aoTocar: () => aoEscolher(t),
              ),
          ],
        ),
      ],
    );
  }
}
