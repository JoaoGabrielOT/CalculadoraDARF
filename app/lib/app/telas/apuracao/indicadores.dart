// Os quatro indicadores do mês (calculadora_darf.py:1334-1345, 1569-1592):
// lucro bruto, lucro líquido, imposto devido e total da DARF.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/textos.dart';
import '../../tema/cores_app.dart';

/// 4 colunas no expandido, 2x2 no compacto.
class Indicadores extends StatelessWidget {
  const Indicadores({
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
    final c = CoresApp.de(context);
    final r = apuracao;
    Color cor(double v) => v < 0 ? c.queda : (v > 0 ? c.alta : c.texto);
    final info = textoInfoDarf(r, mes);
    final anterior = r.darfAnterior != 0 && compacto
        ? '\nInclui ${brl(r.darfAnterior)} de meses anteriores'
        : '';
    final cartoes = [
      Kpi(
        titulo: 'Lucro bruto',
        valor: brl(r.bruto),
        sub: textoVendasNoMes(r),
        corValor: cor(r.bruto),
      ),
      Kpi(
        titulo: 'Lucro líquido',
        valor: brl(r.lucroLiquido),
        sub: 'após taxas e impostos',
        corValor: cor(r.lucroLiquido),
      ),
      Kpi(
        titulo: 'Imposto devido',
        valor: brl(r.impostoTotal),
        sub: textoIrrfRetido(r),
      ),
      Kpi(
        titulo: 'Total da DARF',
        valor: brl(r.darf),
        sub: info + anterior,
        corValor: r.darf >= darfMinimo ? c.alta : null,
      ),
    ];
    Widget cartao(Widget k) => SizedBox(
      width: double.infinity,
      child: Cartao(child: k),
    );
    if (!compacto) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [for (final k in cartoes) Expanded(child: cartao(k))],
        ),
      );
    }
    return Column(
      spacing: 12,
      children: [
        for (var i = 0; i < cartoes.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Expanded(child: cartao(cartoes[i])),
                Expanded(child: cartao(cartoes[i + 1])),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cartões "Swing trade" e "Day trade" do celular (android/main.py:798-814).
class CartoesRegime extends StatelessWidget {
  const CartoesRegime({super.key, required this.apuracao});

  final Apuracao apuracao;

  @override
  Widget build(BuildContext context) {
    final r = apuracao;
    final dt = r.ops.where((o) => o.dt).length;
    final st = r.ops.length - dt;
    String vendas(int n) => '$n venda${n != 1 ? 's' : ''}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Expanded(
            child: _Regime(
              titulo: 'Swing trade',
              imposto: brl(r.impSt),
              linha: 'Alíquota 15% · ${vendas(st)}',
              extra: r.isento
                  ? 'Isento até R\$ 20 mil em ações'
                  : 'Acima do limite de isenção',
            ),
          ),
          Expanded(
            child: _Regime(
              titulo: 'Day trade',
              imposto: brl(r.impDt),
              linha: 'Alíquota 20% · ${vendas(dt)}',
              extra: 'Sem isenção',
            ),
          ),
        ],
      ),
    );
  }
}

class _Regime extends StatelessWidget {
  const _Regime({
    required this.titulo,
    required this.imposto,
    required this.linha,
    required this.extra,
  });

  final String titulo;
  final String imposto;
  final String linha;
  final String extra;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final suave = TextStyle(color: c.textoSuave, fontSize: 11);
    return SizedBox(
      width: double.infinity,
      child: Cartao(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(titulo, style: TextStyle(color: c.textoSuave, fontSize: 12)),
            Text(
              imposto,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(linha, style: suave),
            Text(extra, style: suave),
          ],
        ),
      ),
    );
  }
}
