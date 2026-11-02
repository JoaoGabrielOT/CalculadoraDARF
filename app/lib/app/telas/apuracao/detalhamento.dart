// Detalhamento da apuração: limite de isenção, taxas, impostos e total a pagar
// (calculadora_darf.py:1408-1443, 1594-1612; android/main.py:816-840).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/textos.dart';
import '../../tema/cores_app.dart';

/// Largura da coluna lateral no layout expandido.
const larguraDetalhamento = 340.0;

const _rodape =
    'Código da DARF: 6015\n'
    'Vencimento: último dia útil do mês seguinte\n'
    'Taxas B3: 0,030% swing · 0,023% day trade';

/// Lateral de 340 px no expandido; no celular um cartão recolhido por padrão.
class Detalhamento extends StatelessWidget {
  const Detalhamento({
    super.key,
    required this.apuracao,
    required this.mes,
    required this.compacto,
  });

  final Apuracao apuracao;
  final String mes;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final corpo = _Corpo(apuracao, mes);
    final rodape = _Rodape();
    if (compacto) {
      return Cartao(
        padding: EdgeInsets.zero,
        // o ListTile pinta sobre o Material, não sobre o fundo do cartão
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text(
                'Detalhamento',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [corpo, const SizedBox(height: 12), rodape],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: larguraDetalhamento,
      child: Cartao(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Text(
                'Detalhamento',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: corpo,
              ),
            ),
            Padding(padding: const EdgeInsets.all(16), child: rodape),
          ],
        ),
      ),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo(this.r, this.mes);

  final Apuracao r;
  final String mes;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cor = r.isento ? c.alta : c.queda;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIMITE DE ISENÇÃO (AÇÕES · SWING)',
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          textoLimiteIsencao(r),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: math.min(r.vendasAcoesSt / limiteIsencao, 1).toDouble(),
            minHeight: 10,
            color: cor,
            backgroundColor: c.linha,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          textoIsencao(r),
          style: TextStyle(
            color: cor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Divider(height: 24, color: c.linha),
        _Linha('Taxas B3 + corretagem', brl(r.custos)),
        _Linha('Imposto swing trade (15%)', brl(r.impSt)),
        _Linha('Imposto day trade (20%)', brl(r.impDt)),
        _Linha('Imposto devido', brl(r.impostoTotal)),
        _Linha(
          'IRRF retido (dedo-duro)',
          r.irrf != 0 ? '- ${brl(r.irrf)}' : brl(0),
        ),
        _Linha('DARF de meses anteriores', brl(r.darfAnterior)),
        Divider(height: 24, color: c.linha),
        _Linha(
          'Total a pagar',
          brl(r.darf),
          forte: true,
          cor: r.darf >= darfMinimo ? c.alta : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            textoInfoDarf(r, mes),
            style: TextStyle(color: c.textoSuave, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.titulo, this.valor, {this.forte = false, this.cor});

  final String titulo;
  final String valor;
  final bool forte;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              titulo,
              style: TextStyle(
                color: forte ? c.texto : c.textoSuave,
                fontSize: forte ? 14 : 13,
                fontWeight: forte ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor ?? c.texto,
              fontSize: forte ? 15 : 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.linha.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _rodape,
            style: TextStyle(color: c.textoSuave, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
