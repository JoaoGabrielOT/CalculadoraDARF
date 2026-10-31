// Patrimônio e limites de risco (sugestoes.py:169-244).

import '../ambiente.dart';
import '../apuracao.dart';
import '../caixa.dart';
import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../metas/cadeia.dart';
import '../modelos/config.dart';
import '../modelos/mes.dart';
import '../repositorio.dart';
import 'sugestoes.dart';

/// Patrimônio para a regra dos 2%: caixa projetado mais posições abertas a
/// mercado.
class Patrimonio {
  Patrimonio({
    required this.valor,
    required this.caixa,
    required this.posicoes,
    required this.caixaDefinido,
    required this.semCotacao,
  });

  final double valor;
  final double caixa;
  final double posicoes;
  final bool caixaDefinido;

  /// Tickers abertos sem cotação, que ficam fora do patrimônio.
  final List<String> semCotacao;
}

/// Patrimônio para a regra dos 2%: caixa projetado + posições abertas a
/// mercado.
///
/// Usa o caixa projetado (e não o disponível) porque ele já desconta a
/// compra ainda não liquidada, que o valor da posição também conta. Cada
/// cadeia de cópias de uma compra entra uma vez. [cotacoes]: `{ticker:
/// preço}`; posição sem cotação fica de fora e é listada em `semCotacao`.
/// Caixa não definido: só posições.
Patrimonio patrimonio(
  Config cfg,
  Map<String, double>? cotacoes,
  Map<String, Mes> meses, {
  String? hoje,
}) {
  final resumo = resumoCaixa(cfg, meses, hoje: hoje);
  var posicoes = 0.0;
  final sem = <String>[];
  for (final x in lotesAbertos(meses)) {
    final lote = x.lote;
    final preco = cotacoes?[lote.ticker];
    if (preco == null || preco == 0) {
      if (!sem.contains(lote.ticker)) sem.add(lote.ticker);
      continue;
    }
    posicoes += restante(lote) * preco;
  }
  final caixa = resumo.definido ? resumo.projetado : 0.0;
  return Patrimonio(
    valor: caixa + posicoes,
    caixa: caixa,
    posicoes: posicoes,
    caixaDefinido: resumo.definido,
    semCotacao: ordenadoPor(sem, (t) => [t]),
  );
}

/// `(patrimonio(), resultado do mês de hoje)` lendo os meses uma vez só; é o
/// que `linhasRodape` mostra.
(Patrimonio, double) resumoPatrimonio(
  Repositorio repo,
  Config cfg,
  Map<String, double>? cotacoes, {
  String? hoje,
}) {
  hoje ??= ambiente.hoje();
  final meses = repo.carregarMeses();
  return (
    patrimonio(cfg, cotacoes, meses, hoje: hoje),
    resultadoMes(meses, hoje.substring(0, 7)),
  );
}

/// Perda no stop contra 2% do patrimônio: [pct] (perda em % do patrimônio ou
/// nulo), [limite] (R$) e [excede].
class AlertaRisco {
  AlertaRisco({this.pct, required this.limite, required this.excede});

  final double? pct;
  final double limite;
  final bool excede;
}

/// Compara a perda no stop com 2% do patrimônio. [resultado]: o resultado no
/// stop (negativo = perda); resultado zero ou positivo (stop acima da compra)
/// não é risco e nunca alerta.
AlertaRisco alertaRisco(double resultado, double? valorPatrimonio) {
  final valor = valorPatrimonio;
  final positivo = valor != null && valor != 0 && valor > 0;
  final limite = positivo ? valor * limiteRisco : 0.0;
  if (resultado >= 0) {
    return AlertaRisco(pct: null, limite: limite, excede: false);
  }
  final perda = resultado.abs();
  if (!positivo) {
    return AlertaRisco(pct: null, limite: 0.0, excede: true);
  }
  return AlertaRisco(
    pct: perda / valor * 100,
    limite: limite,
    excede: perda > limite,
  );
}

/// Resultado líquido das vendas do mês (antes do imposto).
double resultadoMes(Map<String, Mes> meses, String mes) {
  final d = meses[mes];
  if (d == null) return 0.0;
  return somaPython([
    for (final l in d.lotes)
      for (final v in l.vendas) calcularVenda(l, v).liquido,
  ]);
}
