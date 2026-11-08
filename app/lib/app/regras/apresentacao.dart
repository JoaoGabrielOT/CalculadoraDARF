// Apresentação de resultados (sem Flutter nem IO): sinal, seta e texto com
// sinal explícito, e os poucos valores derivados que só a tela usa (valor
// atual, percentuais e a posição do marcador na barra stop · atual · alvo).
// Nada aqui muda um cálculo do núcleo.

import '../../nucleo/nucleo.dart';

/// Sentido de um resultado; até meio centavo é neutro (como `brl`).
enum Sinal { alta, queda, neutro }

Sinal sinalDe(double? v) => v == null || v.abs() <= 0.004
    ? Sinal.neutro
    : (v > 0 ? Sinal.alta : Sinal.queda);

/// A seta acompanha a cor, para o sentido não depender só dela.
String setaDe(Sinal s) => switch (s) {
  Sinal.alta => '▲ ',
  Sinal.queda => '▼ ',
  Sinal.neutro => '',
};

/// `+R$ 270,00`, `-R$ 50,00`; zero sem sinal.
String brlComSinal(double v) =>
    '${sinalDe(v) == Sinal.alta ? '+' : ''}${brl(v)}';

/// Percentual com uma casa e sinal: `+8,6%`; `—` sem dado.
String pctCurto(double? v) {
  if (v == null) return '—';
  final t = fmtDec(v.abs()).replaceAll('-', '');
  final s = t == '0,0' ? '' : (v > 0 ? '+' : '-');
  return '$s$t%';
}

/// `▲ +R$ 270,00 (+8,6%)`; sem percentual, só o valor; sem valor, `—`.
String textoResultado(double? valor, double? pct) {
  if (valor == null) return '—';
  final base = '${setaDe(sinalDe(valor))}${brlComSinal(valor)}';
  return pct == null ? base : '$base (${pctCurto(pct)})';
}

/// Quantidade × cotação, em centavos; nulo sem cotação.
double? valorAtual(int qtd, double? cotacao) =>
    cotacao == null || cotacao == 0 ? null : arredondar(qtd * cotacao, 2);

/// [valor] ÷ [base] × 100; nulo sem dado ou com base zero.
double? pctSobre(double? valor, double? base) =>
    valor == null || base == null || base == 0 ? null : valor / base * 100;

/// Variação de [de] até [para], em %.
double? variacaoPct(double? de, double? para) =>
    de == null || para == null || de == 0 ? null : (para / de - 1) * 100;

/// Posição (0 a 1) do preço [atual] entre o [stop] e o [alvo], limitada às
/// pontas; nulo sem os três ou com alvo que não fica acima do stop.
double? posicaoMarcador({double? stop, double? atual, double? alvo}) {
  if (stop == null || atual == null || alvo == null || alvo <= stop) {
    return null;
  }
  return ((atual - stop) / (alvo - stop)).clamp(0.0, 1.0);
}
