// Indicadores de um ativo (entrega 2.1, §8): rótulos que separam mês e
// acumulado, realizado e não realizado, gerencial e fiscal, R$ e %.
// O rótulo do resultado e da rentabilidade segue o método da apuração do mês;
// o do custo remanescente, a origem do custo do saldo. "—" é dado
// indisponível ou divisão por zero, nunca zero. Só formata o que o núcleo
// calculou.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';

/// Texto do valor que depende de cotação: "…" enquanto a consulta não voltou.
String _mercado(String Function() formata, bool chegou, bool disponivel) =>
    disponivel ? formata() : (chegou ? '—' : '…');

/// "método por compra" ou "fiscal (custo médio)", conforme o mês consultado.
String rotuloMetodo(IndicadoresAtivo i) => i.metodoResultado == metodoCustoMedio
    ? 'fiscal (custo médio)'
    : 'método por compra';

/// Uma linha dos indicadores: [id] estável, rótulo, valor e a fórmula (dica).
typedef LinhaIndicador = ({
  String id,
  String rotulo,
  String valor,
  String formula,
});

/// Ids das linhas que os cartões da posição já mostram em destaque.
const idsResumo = {
  'custo',
  'equilibrio',
  'resultadoMes',
  'acumulado',
  'naoRealizado',
  'valorMercado',
};

/// As linhas da lista longa, na ordem da tela.
List<LinhaIndicador> linhasIndicadores(
  IndicadoresAtivo i, {
  required bool corrente,
  Map<String, CotacaoAtual?> cotacoes = const {},
}) {
  final chegou = cotacoes.containsKey(i.ticker);
  String brlOu(double? v) => v == null ? '—' : brl(v);
  final metodo = rotuloMetodo(i);
  final custoRotulo = i.custoPorCompra ? 'por compra' : 'fiscal';
  LinhaIndicador l(String id, String rotulo, String valor, String formula) =>
      (id: id, rotulo: rotulo, valor: valor, formula: formula);
  return [
    l(
      'qtd',
      'Quantidade em aberto',
      '${i.qtdAberta}',
      'Soma do restante de cada compra na data de corte.',
    ),
    l(
      'custo',
      'Custo remanescente ($custoRotulo)',
      brlOu(i.custoRemanescente),
      i.custoPorCompra
          ? 'Gerencial: soma de restante × preço de cada compra do saldo.'
          : 'Fiscal: custo da posição pelo custo médio na data de corte.',
    ),
    l(
      'pmCompras',
      'Preço médio das compras (saldo)',
      brlOu(i.precoMedioCompras),
      'Custo remanescente ÷ quantidade em aberto. Sem saldo: "—".',
    ),
    l(
      'equilibrio',
      'Ponto de equilíbrio (R\$)',
      brlOu(i.pontoEquilibrio),
      'Preço de venda que cobre o custo: (custo ÷ Q + corretagem ÷ Q) ÷ '
          '(1 − taxa B3 swing), no tick. Sem saldo: "—".',
    ),
    l(
      'pmVendas',
      'Preço médio das vendas no mês',
      brlOu(i.precoMedioVendasMes),
      'Σ(quantidade × preço das vendas do mês) ÷ Σ quantidade vendida. '
          'Sem vendas no mês: "—".',
    ),
    l(
      'resultadoMes',
      'Resultado realizado no mês ($metodo, R\$)',
      brl(i.resultadoMes),
      'Soma do resultado das vendas do ativo no mês, depois das taxas e '
          'antes do imposto.',
    ),
    l(
      'acumulado',
      'Resultado realizado acumulado desde ${i.desde} ($metodo, R\$)',
      brl(i.resultadoAcumulado),
      'Soma do resultado realizado de cada mês até o consultado, cada mês '
          'pelo seu método, desde o primeiro mês com dados.',
    ),
    l(
      'porUnidade',
      'Ganho ou perda por unidade vendida no mês (R\$)',
      brlOu(i.ganhoPorUnidade),
      'Resultado realizado no mês ÷ quantidade vendida no mês. Sem vendas '
          'no mês: "—".',
    ),
    l(
      'rentabilidade',
      'Rentabilidade realizada no mês ($metodo, %)',
      i.rentabilidadeRealizada == null
          ? '—'
          : fmtPct(i.rentabilidadeRealizada! * 100),
      'Resultado realizado no mês ÷ custo das unidades vendidas no mês. '
          'Total sobre total, não a média dos percentuais de cada venda. '
          'Custo zero: "—".',
    ),
    l(
      'taxas',
      'Taxas e corretagem das vendas no mês (R\$)',
      brl(i.taxasMes),
      'Soma das taxas B3 da compra e da venda das unidades vendidas no mês '
          'e da corretagem, descontadas do resultado no método atual.',
    ),
    if (corrente) ...[
      l(
        'naoRealizado',
        'Resultado não realizado (gerencial, R\$)',
        _mercado(() => brl(i.naoRealizado!), chegou, i.naoRealizado != null),
        'Q × cotação atual − custo remanescente. Só com cotação atual.',
      ),
      l(
        'valorMercado',
        'Valor de mercado (R\$)',
        _mercado(() => brl(i.valorMercado!), chegou, i.valorMercado != null),
        'Q × cotação atual.',
      ),
      l(
        'exposicao',
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
}

/// Fórmula (dica) da linha [id], para quem mostra o valor fora da lista.
String formulaIndicador(IndicadoresAtivo i, String id) {
  for (final l in linhasIndicadores(i, corrente: true)) {
    if (l.id == id) return l.formula;
  }
  return '';
}

class PainelIndicadores extends StatelessWidget {
  const PainelIndicadores({
    super.key,
    required this.indicadores,
    required this.corrente,
    this.cotacoes = const {},
    this.ocultar = const {},
  });

  final IndicadoresAtivo indicadores;

  /// O corte é hoje: só então valem não realizado, valor de mercado e
  /// exposição (com o selo da cotação atual).
  final bool corrente;
  final Map<String, CotacaoAtual?> cotacoes;

  /// Ids das linhas já mostradas em outro lugar (ver [idsResumo]).
  final Set<String> ocultar;

  @override
  Widget build(BuildContext context) {
    final i = indicadores;
    final linhas = [
      for (final l in linhasIndicadores(
        i,
        corrente: corrente,
        cotacoes: cotacoes,
      ))
        if (!ocultar.contains(l.id)) l,
    ];
    final c = CoresApp.de(context);
    return Column(
      key: Key('indicadores-${i.ticker}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (id: _, :rotulo, :valor, :formula) in linhas)
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
