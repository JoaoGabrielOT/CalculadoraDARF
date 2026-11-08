// Indicadores de um ativo (entrega 2.1, §8): rótulos que separam mês e
// acumulado, realizado e não realizado, gerencial e fiscal, R$ e %. "—" é dado
// indisponível ou divisão por zero, nunca zero. Só formata o que o núcleo
// calculou.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';

/// Texto do valor que depende de cotação: "…" enquanto a consulta não voltou.
String _mercado(String Function() formata, bool chegou, bool disponivel) =>
    disponivel ? formata() : (chegou ? '—' : '…');

class PainelIndicadores extends StatelessWidget {
  const PainelIndicadores({
    super.key,
    required this.indicadores,
    required this.corrente,
    this.cotacoes = const {},
  });

  final IndicadoresAtivo indicadores;

  /// O corte é hoje: só então valem não realizado, valor de mercado e
  /// exposição (com o selo da cotação atual).
  final bool corrente;
  final Map<String, CotacaoAtual?> cotacoes;

  @override
  Widget build(BuildContext context) {
    final i = indicadores;
    final chegou = cotacoes.containsKey(i.ticker);
    String brlOu(double? v) => v == null ? '—' : brl(v);
    final custoRotulo = i.custoPorCompra ? 'por compra' : 'fiscal';
    final linhas = <(String, String, String)>[
      (
        'Quantidade em aberto',
        '${i.qtdAberta}',
        'Soma do restante de cada compra na data de corte.',
      ),
      (
        'Custo remanescente ($custoRotulo)',
        brlOu(i.custoRemanescente),
        i.custoPorCompra
            ? 'Gerencial: soma de restante × preço de cada compra do saldo.'
            : 'Fiscal: custo da posição pelo custo médio na data de corte.',
      ),
      (
        'Preço médio das compras (saldo)',
        brlOu(i.precoMedioCompras),
        'Custo remanescente ÷ quantidade em aberto. Sem saldo: "—".',
      ),
      (
        'Ponto de equilíbrio (R\$)',
        brlOu(i.pontoEquilibrio),
        'Preço de venda que cobre o custo: (custo ÷ Q + corretagem ÷ Q) ÷ '
            '(1 − taxa B3 swing), no tick. Sem saldo: "—".',
      ),
      (
        'Preço médio das vendas no mês',
        brlOu(i.precoMedioVendasMes),
        'Σ(quantidade × preço das vendas do mês) ÷ Σ quantidade vendida. '
            'Sem vendas no mês: "—".',
      ),
      (
        'Resultado realizado no mês (fiscal, R\$)',
        brl(i.resultadoMes),
        'Soma do resultado das vendas do ativo no mês, depois das taxas e '
            'antes do imposto.',
      ),
      (
        'Resultado realizado acumulado desde ${i.desde} (fiscal, R\$)',
        brl(i.resultadoAcumulado),
        'Soma do resultado realizado de cada mês até o consultado, cada mês '
            'pelo seu método, desde o primeiro mês com dados.',
      ),
      (
        'Ganho ou perda por unidade vendida no mês (R\$)',
        brlOu(i.ganhoPorUnidade),
        'Resultado realizado no mês ÷ quantidade vendida no mês. Sem vendas '
            'no mês: "—".',
      ),
      (
        'Rentabilidade realizada no mês (%)',
        i.rentabilidadeRealizada == null
            ? '—'
            : fmtPct(i.rentabilidadeRealizada! * 100),
        'Resultado realizado no mês ÷ custo das unidades vendidas no mês. '
            'Total sobre total, não a média dos percentuais de cada venda. '
            'Custo zero: "—".',
      ),
      (
        'Taxas e corretagem das vendas no mês (R\$)',
        brl(i.taxasMes),
        'Soma das taxas B3 e da corretagem das vendas do mês; as taxas de '
            'compra já estão no custo.',
      ),
      if (corrente) ...[
        (
          'Resultado não realizado (gerencial, R\$)',
          _mercado(() => brl(i.naoRealizado!), chegou, i.naoRealizado != null),
          'Q × cotação atual − custo remanescente. Só com cotação atual.',
        ),
        (
          'Valor de mercado (R\$)',
          _mercado(() => brl(i.valorMercado!), chegou, i.valorMercado != null),
          'Q × cotação atual.',
        ),
        (
          'Exposição na carteira (%)',
          _mercado(
            () => fmtPct(i.exposicao! * 100, sinal: false),
            chegou,
            i.exposicao != null,
          ),
          'Valor de mercado do ativo ÷ valor de mercado de toda a carteira. '
              'Sem cotação de algum ativo: "—".',
        ),
      ],
    ];
    final c = CoresApp.de(context);
    return Column(
      key: Key('indicadores-${i.ticker}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (rotulo, valor, formula) in linhas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Tooltip(
                    message: formula,
                    child: Text(
                      rotulo,
                      style: TextStyle(color: c.textoSuave, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
