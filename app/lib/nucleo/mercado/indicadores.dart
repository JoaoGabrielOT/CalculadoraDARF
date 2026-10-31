// Indicadores de mercado (mercado.py:6-15, 22-102).

import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../modelos/barras.dart';

typedef Risco = ({String rotulo, String fundo, String texto});

/// `FAIXAS_RISCO`: (limite, rótulo, fundo, texto).
const _faixasRisco = <(double, String, String, String)>[
  (2.2, 'Menor Risco', '#10b981', '#ffffff'),
  (3.0, 'Médio Risco', '#f59e0b', '#1f2937'),
  (4.5, 'Alto Risco', '#f97316', '#ffffff'),
  (double.infinity, 'Alto Risco / Muito Alto', '#ef4444', '#ffffff'),
];

/// Período do gráfico -> (range e intervalo do Yahoo, validade do cache em
/// segundos).
const periodosGrafico = <String, (String, String, int)>{
  '1D': ('1d', '5m', 60),
  '5D': ('5d', '30m', 120),
  '1M': ('1mo', '1d', 900),
  '6M': ('6mo', '1d', 1800),
  '1A': ('1y', '1d', 1800),
  '5A': ('5y', '1wk', 3600),
  'Máx': ('max', '1mo', 3600),
};

/// ATR de Wilder: média móvel suavizada do True Range.
double? calcularAtr(
  List<double> maximas,
  List<double> minimas,
  List<double> fechamentos, [
  int n = 14,
]) {
  final trs = [
    for (var i = 1; i < fechamentos.length; i++)
      maxPython(
        maxPython(
          maximas[i] - minimas[i],
          (maximas[i] - fechamentos[i - 1]).abs(),
        ),
        (minimas[i] - fechamentos[i - 1]).abs(),
      ),
  ];
  if (trs.length < n) return null;
  var atr = somaPython(trs.take(n)) / n;
  for (final tr in trs.skip(n)) {
    atr = (atr * (n - 1) + tr) / n;
  }
  return atr;
}

/// Pontos de pivô clássicos do pregão: PP=(H+L+C)/3, R1=2·PP−L, S1=2·PP−H.
({double pp, double r1, double s1}) calcularPivos(
  double alta,
  double baixa,
  double fech,
) {
  final pp = (alta + baixa + fech) / 3;
  return (pp: pp, r1: 2 * pp - baixa, s1: 2 * pp - alta);
}

/// Chandelier Exit: máxima das últimas n barras − mult × ATR(n) de Wilder.
/// Nulo com menos de n+1 barras.
double? calcularChandelier(
  List<BarraDiaria> barras, {
  int n = 22,
  int mult = 3,
}) {
  if (barras.length < n + 1) return null;
  final atr = calcularAtr(
    [for (final b in barras) b.alta],
    [for (final b in barras) b.baixa],
    [for (final b in barras) b.fech],
    n,
  );
  if (atr == null) return null;
  return maxDe(barras.skip(barras.length - n).map((b) => b.alta)) - mult * atr;
}

/// Chandelier Exit de cada prefixo de barras em uma só passada: o item i é
/// igual a `calcularChandelier(barras[:i + 1], n, mult)`.
List<double?> serieChandelier(
  List<BarraDiaria> barras, {
  int n = 22,
  int mult = 3,
}) {
  final saida = List<double?>.filled(barras.length, null);
  double? atr;
  final trs = <double>[];
  BarraDiaria? anterior;
  for (final (i, b) in barras.indexed) {
    if (i >= 1) {
      final tr = maxPython(
        maxPython(b.alta - b.baixa, (b.alta - anterior!.fech).abs()),
        (b.baixa - anterior.fech).abs(),
      );
      trs.add(tr);
      if (i == n) {
        atr = somaPython(trs) / n;
      } else if (i > n) {
        atr = (atr! * (n - 1) + tr) / n;
      }
    }
    anterior = b;
    if (atr != null) {
      saida[i] =
          maxDe(barras.skip(i - n + 1).take(n).map((x) => x.alta)) - mult * atr;
    }
  }
  return saida;
}

/// < 2,2 verde; 2,2 a 3,0 amarelo; acima de 3,0 até 4,5 laranja; acima de 4,5
/// vermelho.
Risco classificarRisco(double atrPct) {
  for (final (i, (limite, rotulo, fundo, texto)) in _faixasRisco.indexed) {
    if (i == 0 ? atrPct < limite : atrPct <= limite) {
      return (rotulo: rotulo, fundo: fundo, texto: texto);
    }
  }
  final ultima = _faixasRisco.last;
  return (rotulo: ultima.$2, fundo: ultima.$3, texto: ultima.$4);
}

/// `_valido`: número finito (não NaN) e positivo.
bool valido(Object? v) => v is num && !v.isNaN && v > 0;

/// (variação em R$, variação %) em relação ao fechamento anterior.
(double?, double?) variacao(double? preco, double? anterior) {
  if (!valido(preco) || !valido(anterior)) return (null, null);
  return (preco! - anterior!, (preco / anterior - 1) * 100);
}

/// Último fechamento de um pregão anterior ao dia atual do mercado;
/// [pares] = (data `AAAA-MM-DD`, fechamento).
double? anteriorDe(List<(String, double)> pares, String diaAtual) {
  final antes = [
    for (final (d, c) in ordenadoPor(pares, (p) => [p.$1, p.$2]))
      if (compararTexto(d, diaAtual) < 0) c,
  ];
  return antes.isEmpty ? null : antes.last;
}
