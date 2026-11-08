// Tick (variação mínima de apregoação) da B3 para ações, units e BDRs.
//
// Confirmado em 07/11/2026 no documento oficial da B3 "Variações Mínimas de
// Apregoação" (Nov/2021, https://b3.com.br/data/files/6E/85/D1/AC/47D5D710B25F40D78C094EA8/Variacoes%20Minimas%20de%20Apregoacao%20-%20Nov2021.pdf):
// "Ações (Vista e Fração)", Units, BDRs Patrocinados, BDRs Não Patrocinados e
// BDR de ETF têm tick único de R$ 0,01, sem faixas por preço, no lote padrão e
// no fracionário. O documento de 13/10/2026 listado na página de regras de
// negociação (https://b3.com.br/data/files/18/07/28/5E/60D11A103BBB511AAC094EA8/Variacoes%20Minimas%20de%20Apregoacao%20-%2013.10.2026.pdf)
// só traz derivativos (futuros, opções sobre futuros, eventos e futuros de
// ações/units/ETFs a 0,01); não há tabela do mercado à vista nele. Conclusão:
// tabela do mercado à vista confirmada pela versão de 2021 (R$ 0,01); a de
// 13/10/2026 não a repete.

import 'compat/numeros.dart';

/// Faixas de preço (limite superior inclusive) e o tick de cada uma.
const List<({double ate, double tick})> faixasTick = [
  (ate: double.infinity, tick: 0.01),
];

/// Tolerância, em ticks, contra o ruído do ponto flutuante (`7.60 / 0.01`).
const double _tolTicks = 1e-9;

double _finito(double v) {
  if (!v.isFinite) {
    throw ArgumentError.value(v, 'v', 'valor não finito');
  }
  return v;
}

/// Tick da faixa de [preco] para [ticker]. A tabela atual não depende do
/// ticker (ações, units e BDRs têm o mesmo tick).
double tickDe(String ticker, double preco) {
  _finito(preco);
  for (final f in faixasTick) {
    if (preco <= f.ate) return f.tick;
  }
  return faixasTick.last.tick;
}

double _ticks(String ticker, double v) {
  final t = tickDe(ticker, _finito(v));
  final n = v / t;
  return _finito(n);
}

/// Arredonda [v] para baixo ao tick (o stop nunca fica acima do calculado).
double pisoTick(String ticker, double v) {
  final t = tickDe(ticker, v);
  return arredondar(((_ticks(ticker, v) + _tolTicks).floorToDouble()) * t, 2) +
      0.0;
}

/// Arredonda [v] para cima ao tick (o preço nunca fica abaixo do necessário).
double tetoTick(String ticker, double v) {
  final t = tickDe(ticker, v);
  return arredondar(((_ticks(ticker, v) - _tolTicks).ceilToDouble()) * t, 2) +
      0.0;
}
