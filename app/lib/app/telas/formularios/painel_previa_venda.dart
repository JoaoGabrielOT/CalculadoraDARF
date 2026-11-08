// Painel "Fiscal x gerencial" da venda por quantidade: o resultado pelas
// compras escolhidas, o resultado fiscal (custo médio), a parte de day trade e
// o aviso de que a escolha das compras não muda o imposto. Só mostra o que o
// serviço calculou (`previaVenda`); nada é recalculado aqui.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/formularios.dart';
import '../../tema/cores_app.dart';

class PainelPreviaVenda extends StatelessWidget {
  const PainelPreviaVenda({
    super.key,
    required this.previa,
    required this.erro,
    this.custoMedio = true,
  });

  /// Nulo enquanto os campos estão incompletos ou a prévia não chegou.
  final PreviaVenda? previa;

  /// Erro do serviço ao calcular a prévia (vazio quando não há).
  final String erro;
  final bool custoMedio;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final p = previa;
    TextStyle suave(double tam) =>
        TextStyle(color: c.textoSuave, fontSize: tam);
    TextStyle forte(Color cor) =>
        TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700);
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            'FISCAL X GERENCIAL',
            style: TextStyle(
              color: c.textoSuave,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (erro.isNotEmpty)
            Text(erro, style: TextStyle(color: c.queda, fontSize: 12)),
          if (p != null) ...[
            Text(
              _nb(textoResultadoGerencial(p.gerencial)),
              style: forte(p.gerencial < 0 ? c.queda : c.alta),
            ),
            Text(
              _nb(textoResultadoFiscal(p.fiscal, custoMedio: custoMedio)),
              style: forte(p.fiscal < 0 ? c.queda : c.alta),
            ),
            Text(
              textoDayTradeComum(p.qtdDt, p.qtdComum),
              style: TextStyle(color: c.texto, fontSize: 12),
            ),
            if (p.aviso != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    p.aviso!,
                    style: TextStyle(
                      color: c.queda,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 4),
          Text(textoEscolhaDasCompras, style: suave(11)),
        ],
      ),
    );
  }
}

/// Espaço sem quebra depois de "R$": o valor não se separa do símbolo.
String _nb(String t) => t.replaceAll('R\$ ', 'R\$ ');
