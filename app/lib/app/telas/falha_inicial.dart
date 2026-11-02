// Tela de falha ao iniciar: o motivo e "Tentar de novo".

import 'package:flutter/material.dart';

class CorpoFalha extends StatelessWidget {
  const CorpoFalha(this.mensagem, {super.key, required this.aoTentar});

  final String mensagem;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Não foi possível iniciar a Calculadora DARF.\n$mensagem',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: aoTentar,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    ),
  );
}
