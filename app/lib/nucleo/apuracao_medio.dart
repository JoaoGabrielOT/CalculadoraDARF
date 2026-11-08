// Apuração do mês pelas regras da Receita (entrega 2.1, §5.2): custo médio
// ponderado por ticker nas operações comuns, com as despesas de aquisição, e
// day trade por ativo no dia, até a menor das quantidades comprada e vendida,
// sem contar o estoque anterior (IN RFB 1.585/2015, arts. 56, 59, 64 e 65).
// Usa só os totais por ticker e por dia, nunca qual compra a venda consumiu.
// O custo da posição é arredondado ao centavo a cada evento (D10).

import 'alocacao.dart' show grupoDe;
import 'apuracao.dart';
import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

String avisoSaldoInconsistente(String ticker) =>
    'Saldo inconsistente em $ticker: confira as vendas';

/// Os avisos de [tickers], um por linha.
String avisosSaldoInconsistente(List<String> tickers) =>
    tickers.map(avisoSaldoInconsistente).join('\n');

/// Por que o mês com saldo inconsistente não pode ser fechado (§5.6).
String bloqueioSaldoInconsistente(List<String> tickers) =>
    'O mês não pode ser fechado com saldo inconsistente.\n\n'
    '${avisosSaldoInconsistente(tickers)}';

const textoCopiaLevadaTravada =
    'Compra levada de um mês anterior: quantidade e preço fazem parte da '
    'posição inicial e não podem ser editados.';

/// Cópia levada ou compra de mês anterior: já está na posição inicial.
bool _estoqueAnterior(Lote l, String mes) =>
    (l.origem != null && l.origem!.isNotEmpty) ||
    compararTexto(l.dataCompra, '$mes-01') < 0;

/// Posição inicial do mês de corte (D3): os lotes levados pela `qtd` (o saldo
/// no início do mês; as vendas do próprio mês são eventos da apuração).
Map<String, PosicaoFiscal> posicaoInicialDerivada(Mes d) {
  final p = <String, PosicaoFiscal>{};
  for (final l in d.lotes) {
    if (!_estoqueAnterior(l, d.mes)) continue;
    final x = p[l.ticker] ??= PosicaoFiscal(qtd: 0, custo: 0);
    x.qtd += l.qtd;
    x.custo = arredondar(
      x.custo + arredondar(l.qtd * l.preco * (1 + taxaB3Swing), 2),
      2,
    );
  }
  return {for (final t in ordenadoCom(p.keys, compararTexto)) t: p[t]!};
}

/// Menor mês com o marcador de custo médio, ou nulo.
String? mesDeCorte(Iterable<Mes> meses) {
  String? corte;
  for (final m in meses) {
    if (m.metodo == metodoCustoMedio &&
        (corte == null || compararTexto(m.mes, corte) < 0)) {
      corte = m.mes;
    }
  }
  return corte;
}

/// Regra efetiva (§5.3): com marcador, custo médio; fechado sem marcador,
/// por compra para sempre; aberto, custo médio a partir do corte.
bool usaCustoMedio(Mes m, String? corte) {
  if (m.metodo == metodoCustoMedio) return true;
  if (m.fechado) return false;
  return corte != null && compararTexto(m.mes, corte) >= 0;
}

/// Marca [d] para o custo médio com a posição inicial derivada dos lotes
/// levados e o [prejuizo] anterior (padrão zero).
void marcarCustoMedio(Mes d, {PrejuizoAcumulado? prejuizo}) {
  d.metodo = metodoCustoMedio;
  d.posicaoInicial = posicaoInicialDerivada(d);
  d.prejuizoAnterior = prejuizo ?? PrejuizoAcumulado();
}

class _Dia {
  final compras = <Lote>[];
  final vendas = <Venda>[];
}

/// Parte do resultado de um dia atribuída a uma linha de venda.
class _Linha {
  _Linha(this.qtdDt, this.fracao);

  int qtdDt;
  final double fracao;
  double compra = 0;
  double taxas = 0;
  double corretagem = 0;
  double bruto = 0;
  double resDt = 0;
  double resComum = 0;
}

/// Compensação do prejuízo anterior (art. 64): (tributável, compensado,
/// prejuízo final).
(double, double, double) _compensar(double base, double anterior) {
  if (base > 0) {
    final comp = minPython(base, anterior);
    return (base - comp, comp, anterior - comp);
  }
  return (0.0, 0.0, anterior - base);
}

/// Quantidade de day trade de cada linha: `q·dt/S` pelos maiores restos, para
/// que a soma dê `dt`.
List<int> _repartir(List<int> qtds, int dt, int s) {
  final base = [for (final q in qtds) q * dt ~/ s];
  var falta = dt - base.fold(0, (a, b) => a + b);
  final ordem = ordenadoPor([
    for (var i = 0; i < qtds.length; i++) i,
  ], (i) => [-(qtds[i] * dt % s), i]);
  for (final i in ordem) {
    if (falta <= 0) break;
    base[i]++;
    falta--;
  }
  return base;
}

Apuracao apurarCustoMedio(Mes d) {
  final posicao = <String, PosicaoFiscal>{
    for (final e in (d.posicaoInicial ?? const {}).entries)
      e.key: PosicaoFiscal(qtd: e.value.qtd, custo: e.value.custo),
  };
  final prej = d.prejuizoAnterior ?? PrejuizoAcumulado();

  // 1. eventos por ticker e por dia
  final tipos = <String, String>{};
  final eventos = <String, Map<String, _Dia>>{};
  for (final l in d.lotes) {
    tipos.putIfAbsent(l.ticker, () => l.tipo);
    final dias = eventos[l.ticker] ??= {};
    if (!_estoqueAnterior(l, d.mes)) {
      (dias[l.dataCompra] ??= _Dia()).compras.add(l);
    }
    for (final v in l.vendas) {
      (dias[v.data] ??= _Dia()).vendas.add(v);
    }
  }

  final linhas = Map<Venda, _Linha>.identity();
  final inconsistentes = <String>{};
  final resAcoesComum = <double>[];
  final resBdrComum = <double>[];
  final resDtTodos = <double>[];
  final vendasAcoes = <double>[];
  final irrfStDia = <String, double>{};
  final resDtDia = <String, double>{};

  // 2. dia a dia, em ordem cronológica
  for (final t in ordenadoCom(eventos.keys, compararTexto)) {
    final tipo = tipos[t]!;
    final dias = eventos[t]!;
    for (final data in ordenadoCom(dias.keys, compararTexto)) {
      final dia = dias[data]!;
      final b = dia.compras.fold(0, (s, l) => s + l.qtd);
      final s = dia.vendas.fold(0, (s, v) => s + v.qtd);
      final dt = b < s ? b : s;
      final pc = b == 0
          ? 0.0
          : somaPython(dia.compras.map((l) => l.qtd * l.preco)) / b;
      final pv = s == 0
          ? 0.0
          : somaPython(dia.vendas.map((v) => v.qtd * v.preco)) / s;
      // uma ordem por compra e uma por venda (grupo), rateadas por quantidade
      final corrCompras = corretagemPorOrdem * dia.compras.length;
      final corrVendas =
          corretagemPorOrdem *
          {for (final v in dia.vendas) grupoDe(v.id)}.length;
      final corrDt =
          (b == 0 ? 0.0 : corrCompras * dt / b) +
          (s == 0 ? 0.0 : corrVendas * dt / s);
      final taxasDt = (dt * pv + dt * pc) * taxaB3Daytrade;
      final resDt = dt * pv - dt * pc - taxasDt - corrDt;

      final pos = posicao[t] ??= PosicaoFiscal(qtd: 0, custo: 0);
      if (b - dt > 0) {
        pos.custo = arredondar(
          pos.custo +
              arredondar(
                (b - dt) * pc * (1 + taxaB3Swing) + corrCompras * (b - dt) / b,
                2,
              ),
          2,
        );
        pos.qtd += b - dt;
      }

      final n = s - dt;
      var q = n;
      var custoBaixado = 0.0;
      var taxasComum = 0.0;
      var corrComum = 0.0;
      var resComum = 0.0;
      if (n > 0) {
        // venda acima da posição: só a parte coberta é apurada
        if (n > pos.qtd) {
          inconsistentes.add(t);
          q = pos.qtd;
        }
        if (q > 0) {
          custoBaixado = q == pos.qtd
              ? pos.custo
              : arredondar(q * pos.custo / pos.qtd, 2);
          taxasComum = q * pv * taxaB3Swing;
          corrComum = corrVendas * q / s;
          resComum = q * pv - custoBaixado - taxasComum - corrComum;
          pos.custo = arredondar(pos.custo - custoBaixado, 2);
          pos.qtd -= q;
        }
        final valorComum = n * pv;
        if (tipo == 'Ação') vendasAcoes.add(valorComum);
        irrfStDia[data] = (irrfStDia[data] ?? 0.0) + valorComum * irrfSwing;
      }
      if (tipo == 'Ação') resAcoesComum.add(resComum);
      if (tipo == 'BDR') resBdrComum.add(resComum);
      if (dt > 0) {
        resDtTodos.add(resDt);
        resDtDia[data] = (resDtDia[data] ?? 0.0) + resDt;
      }

      // 3. atribuição às linhas pela quantidade (fração dt/S de day trade)
      if (s == 0) continue;
      final qtdDt = _repartir([for (final v in dia.vendas) v.qtd], dt, s);
      for (final (i, v) in dia.vendas.indexed) {
        final f = v.qtd / s;
        linhas[v] = _Linha(qtdDt[i], dt / s)
          ..compra = (dt * pc + custoBaixado) * f
          ..taxas = (taxasDt + taxasComum) * f
          ..corretagem = (corrDt + corrComum) * f
          ..bruto = (dt * pv - dt * pc + q * pv - custoBaixado) * f
          ..resDt = resDt * f
          ..resComum = resComum * f;
      }
    }
  }

  // 4. isenção: só a parte comum das vendas de ações
  final vendasAcoesSt = somaPython(vendasAcoes);
  final isento = vendasAcoesSt <= limiteIsencao;

  final ops = <Operacao>[];
  for (final l in d.lotes) {
    for (final v in l.vendas) {
      final x = linhas[v]!;
      final resultado = x.resDt + x.resComum;
      final isentoLinha = l.tipo == 'Ação' && isento;
      ops.add(
        Operacao(
            c: ResultadoVenda(
              dt: x.fracao == 1,
              compra: x.compra,
              venda: v.qtd * v.preco,
              taxas: x.taxas,
              corretagem: x.corretagem,
              bruto: x.bruto,
              liquido: resultado,
            ),
            ticker: l.ticker,
            tipo: l.tipo,
            data: v.data,
            qtd: v.qtd,
            preco: v.preco,
            loteId: l.id,
            vendaId: v.id,
          )
          ..regime = x.fracao == 1
              ? 'Day trade'
              : x.fracao == 0
              ? (isentoLinha ? 'Swing (isento)' : 'Swing')
              : 'Misto'
          // estimativa por linha, como no método por compra; o imposto do
          // mês sai das bases compensadas abaixo
          ..imposto =
              maxPython(x.resDt, 0.0) * aliqDaytrade +
              (isentoLinha ? 0.0 : maxPython(x.resComum, 0.0) * aliqSwing)
          ..qtdDt = x.qtdDt
          ..custoFiscal = x.compra
          ..resultadoFiscal = resultado,
      );
    }
  }

  // 5 a 7. bases e compensações separadas (comum e day trade)
  final resAcoes = somaPython(resAcoesComum);
  final baseComum =
      (isento ? minPython(resAcoes, 0.0) : resAcoes) + somaPython(resBdrComum);
  final (tribComum, compComum, prejComumFinal) = _compensar(
    baseComum,
    prej.comum,
  );
  final (tribDt, compDt, prejDtFinal) = _compensar(
    somaPython(resDtTodos),
    prej.dayTrade,
  );

  // 8. imposto e IRRF como no método por compra
  final impSt = tribComum * aliqSwing;
  final impDt = tribDt * aliqDaytrade;
  final irrfSt = somaPython(irrfStDia.values.where((x) => x > 1));
  final irrfDt = somaPython(
    resDtDia.values
        .where((r) => r * irrfDaytrade > 1)
        .map((r) => r * irrfDaytrade),
  );
  final irrf = irrfSt + irrfDt;
  final impostoTotal = impSt + impDt;
  final darfMes = maxPython(impostoTotal - irrf, 0.0);
  final darfAnterior = d.darfAnterior;

  // 5.6: saldo dos lotes igual à posição fiscal e nenhum lote negativo
  final restantes = <String, int>{};
  for (final l in d.lotes) {
    final r = restante(l);
    if (r < 0) inconsistentes.add(l.ticker);
    restantes[l.ticker] = (restantes[l.ticker] ?? 0) + r;
  }
  for (final t in {...restantes.keys, ...posicao.keys}) {
    if ((restantes[t] ?? 0) != (posicao[t]?.qtd ?? 0)) inconsistentes.add(t);
  }

  // 9. saídas para o fechamento
  return Apuracao(
    ops: ops,
    vendasAcoesSt: vendasAcoesSt,
    isento: isento,
    bruto: somaPython(ops.map((o) => o.bruto)),
    custos: somaPython(ops.map((o) => o.taxas + o.corretagem)),
    impSt: impSt,
    impDt: impDt,
    impostoTotal: impostoTotal,
    irrf: irrf,
    lucroLiquido: somaPython(ops.map((o) => o.liquido)) - impostoTotal,
    darfMes: darfMes,
    darfAnterior: darfAnterior,
    darf: darfMes + darfAnterior,
    metodo: metodoCustoMedio,
    compensadoComum: compComum,
    compensadoDt: compDt,
    prejuizoComumFinal: prejComumFinal,
    prejuizoDtFinal: prejDtFinal,
    posicaoFinal: {
      for (final t in ordenadoCom(posicao.keys, compararTexto))
        if (posicao[t]!.qtd > 0) t: posicao[t]!,
    },
    inconsistentes: ordenadoCom(inconsistentes, compararTexto),
    irrfSwingPorDia: irrfStDia,
    resultadoDtPorDia: resDtDia,
  );
}
