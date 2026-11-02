// Resumo financeiro da ordem: valor bruto, taxas, IRRF, débito ou crédito na
// conta e data de liquidação (calculadora_darf.py:179-214; android/main.py:251).

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/formularios.dart';
import '../../tema/cores_app.dart';

class PainelResumoOrdem extends StatelessWidget {
  const PainelResumoOrdem({super.key, required this.resumo, this.nota = ''});

  /// Nulo enquanto quantidade, preço ou data estão incompletos.
  final ResumoOrdem? resumo;
  final String nota;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final t = textosResumo(resumo);
    Widget linha(String titulo, String valor) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        Text(
          valor,
          style: TextStyle(
            color: c.texto,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            'RESUMO FINANCEIRO DA ORDEM',
            style: TextStyle(
              color: c.textoSuave,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          linha('Valor bruto', t?.bruto ?? '—'),
          linha('Taxas B3 (estimadas)', t?.taxas ?? '—'),
          linha('IRRF retido', t?.irrf ?? '—'),
          const SizedBox(height: 4),
          Text(
            t?.impacto ?? textoResumoVazio,
            style: TextStyle(
              color: t == null ? c.textoSuave : (t.debito ? c.queda : c.alta),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (t != null)
            Text(
              t.liquidacao,
              style: TextStyle(
                color: c.texto,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (nota.isNotEmpty)
            Text(nota, style: TextStyle(color: c.textoSuave, fontSize: 11)),
        ],
      ),
    );
  }
}
