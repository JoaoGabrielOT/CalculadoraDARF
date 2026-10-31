// Regras de compra e venda e apuração do mês (nucleo.py:259-375, 444-452,
// 459-485, 520-524). A ordem das operações aritméticas é a do Python.

import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'datas.dart';
import 'formatacao.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

int vendido(Lote l) => l.vendas.fold(0, (soma, v) => soma + v.qtd);

int restante(Lote l) => l.qtd - vendido(l);

/// Cópia da compra sem uma das vendas (usada ao editar essa venda).
Lote semVenda(Lote l, String vendaId) => Lote.fromJson({
  ...l.toJson(),
  'vendas': [
    for (final v in l.vendas)
      if (v.id != vendaId) v.toJson(),
  ],
});

/// Valida a edição de uma compra que já pode ter vendas. Devolve a mensagem de
/// erro ou nulo.
String? erroEdicaoLote(Lote lote, Lote novo) {
  final ja = vendido(lote);
  if (novo.qtd < ja) {
    return 'A quantidade não pode ser menor que a já vendida ($ja).';
  }
  if (lote.vendas.isNotEmpty) {
    final primeira = lote.vendas
        .map((v) => v.data)
        .reduce((a, b) => compararTexto(b, a) < 0 ? b : a);
    if (compararTexto(novo.dataCompra, primeira) > 0) {
      return 'A data da compra não pode ser depois da primeira venda '
          '(${fmtData(primeira)}).';
    }
  }
  return null;
}

String statusLote(Lote l) {
  final r = restante(l);
  if (r == l.qtd) return 'Não vendido';
  if (r == 0) return 'Vendido';
  return 'Vendido parcial';
}

/// Resultado de uma venda (`calcular_venda`).
class ResultadoVenda {
  ResultadoVenda({
    required this.dt,
    required this.compra,
    required this.venda,
    required this.taxas,
    required this.corretagem,
    required this.bruto,
    required this.liquido,
  });

  final bool dt;
  final double compra;
  final double venda;
  final double taxas;
  final double corretagem;
  final double bruto;
  final double liquido;

  Map<String, Object?> toJson() => {
    'dt': dt,
    'compra': compra,
    'venda': venda,
    'taxas': taxas,
    'corretagem': corretagem,
    'bruto': bruto,
    'liquido': liquido,
  };
}

/// `calcular_venda` com a venda dada por quantidade (inteira ou fracionária,
/// como na calculadora de metas), preço e data.
ResultadoVenda calcularVendaQtd(Lote lote, num qtd, double preco, String data) {
  final compra = qtd * lote.preco;
  final venda = qtd * preco;
  final dt = data == lote.dataCompra;
  final taxa = dt ? taxaB3Daytrade : taxaB3Swing;
  final taxas = (compra + venda) * taxa;
  final corretagem = corretagemPorOrdem * (1 + qtd / lote.qtd);
  final bruto = venda - compra;
  final liquido = bruto - taxas - corretagem;
  return ResultadoVenda(
    dt: dt,
    compra: compra,
    venda: venda,
    taxas: taxas,
    corretagem: corretagem,
    bruto: bruto,
    liquido: liquido,
  );
}

ResultadoVenda calcularVenda(Lote lote, Venda v) =>
    calcularVendaQtd(lote, v.qtd, v.preco, v.data);

/// Venda do mês com o regime e o imposto (item de `apurar()["ops"]`).
class Operacao extends ResultadoVenda {
  Operacao({
    required ResultadoVenda c,
    required this.ticker,
    required this.tipo,
    required this.data,
    required this.qtd,
    required this.preco,
    required this.loteId,
    required this.vendaId,
  }) : super(
         dt: c.dt,
         compra: c.compra,
         venda: c.venda,
         taxas: c.taxas,
         corretagem: c.corretagem,
         bruto: c.bruto,
         liquido: c.liquido,
       );

  final String ticker;
  final String tipo;
  final String data;
  final int qtd;
  final double preco;
  final String loteId;
  final String vendaId;
  String regime = '';
  double imposto = 0.0;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'ticker': ticker,
    'tipo': tipo,
    'data': data,
    'qtd': qtd,
    'preco': preco,
    'lote_id': loteId,
    'venda_id': vendaId,
    'regime': regime,
    'imposto': imposto,
  };
}

/// Resultado de `apurar` (nucleo.py:307-367).
class Apuracao {
  Apuracao({
    required this.ops,
    required this.vendasAcoesSt,
    required this.isento,
    required this.bruto,
    required this.custos,
    required this.impSt,
    required this.impDt,
    required this.impostoTotal,
    required this.irrf,
    required this.lucroLiquido,
    required this.darfMes,
    required this.darfAnterior,
    required this.darf,
  });

  final List<Operacao> ops;
  final double vendasAcoesSt;
  final bool isento;
  final double bruto;
  final double custos;
  final double impSt;
  final double impDt;
  final double impostoTotal;
  final double irrf;
  final double lucroLiquido;
  final double darfMes;
  final double darfAnterior;
  final double darf;

  /// O que o mês fechado grava em `resumo` (sem `ops`).
  ResumoApuracao get resumo => ResumoApuracao(
    vendasAcoesSt: vendasAcoesSt,
    isento: isento,
    bruto: bruto,
    custos: custos,
    impSt: impSt,
    impDt: impDt,
    impostoTotal: impostoTotal,
    irrf: irrf,
    lucroLiquido: lucroLiquido,
    darfMes: darfMes,
    darfAnterior: darfAnterior,
    darf: darf,
  );

  Map<String, Object?> toJson() => {
    'ops': [for (final o in ops) o.toJson()],
    ...resumo.toJson(),
  };
}

Apuracao apurar(Mes d) {
  final ops = <Operacao>[];
  for (final l in d.lotes) {
    for (final v in l.vendas) {
      ops.add(
        Operacao(
          c: calcularVenda(l, v),
          ticker: l.ticker,
          tipo: l.tipo,
          data: v.data,
          qtd: v.qtd,
          preco: v.preco,
          loteId: l.id,
          vendaId: v.id,
        ),
      );
    }
  }

  final vendasAcoesSt = somaPython(
    ops.where((o) => !o.dt && o.tipo == 'Ação').map((o) => o.venda),
  );
  final isento = vendasAcoesSt <= limiteIsencao;

  for (final o in ops) {
    if (o.dt) {
      o.regime = 'Day trade';
      o.imposto = maxPython(o.liquido, 0.0) * aliqDaytrade;
    } else if (o.tipo == 'Ação' && isento) {
      o.regime = 'Swing (isento)';
      o.imposto = 0.0;
    } else {
      o.regime = 'Swing';
      o.imposto = maxPython(o.liquido, 0.0) * aliqSwing;
    }
  }

  final resAcoesSt = somaPython(
    ops.where((o) => !o.dt && o.tipo == 'Ação').map((o) => o.liquido),
  );
  final resBdrSt = somaPython(
    ops.where((o) => !o.dt && o.tipo == 'BDR').map((o) => o.liquido),
  );
  final baseSt = (isento ? minPython(resAcoesSt, 0.0) : resAcoesSt) + resBdrSt;
  final baseDt = somaPython(ops.where((o) => o.dt).map((o) => o.liquido));
  final impSt = maxPython(baseSt, 0.0) * aliqSwing;
  final impDt = maxPython(baseDt, 0.0) * aliqDaytrade;

  final irrfStDia = <String, double>{};
  final resDtDia = <String, double>{};
  for (final o in ops) {
    if (o.dt) {
      resDtDia[o.data] = (resDtDia[o.data] ?? 0.0) + o.liquido;
    } else {
      irrfStDia[o.data] = (irrfStDia[o.data] ?? 0.0) + o.venda * irrfSwing;
    }
  }
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
  final darf = darfMes + darfAnterior;

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
    darf: darf,
  );
}

String infoDarf(Apuracao r, String mes) {
  if (r.darf >= darfMinimo) {
    return 'Código 6015 · vence no último dia útil de '
        '${fmtMes(proximoMes(mes))}';
  }
  if (r.darf > 0) return 'Abaixo de R\$ 10 · acumula para o próximo mês';
  return 'Nada a pagar neste mês';
}

String mensagemFechamento(Apuracao r, String prox) {
  final String msg;
  if (r.darf >= darfMinimo) {
    msg =
        'DARF a pagar: ${brl(r.darf)}\nCódigo: 6015\n'
        'Vencimento: último dia útil de ${fmtMes(prox)}.';
  } else if (r.darf > 0) {
    msg =
        'A DARF de ${brl(r.darf)} é menor que R\$ 10 e foi transferida '
        'para ${fmtMes(prox)}.';
  } else {
    msg = 'Não há DARF a pagar neste mês.';
  }
  return '$msg\n\nAtivos não vendidos foram levados para ${fmtMes(prox)}.';
}

/// Ação ou BDR pelo código de negociação da B3: BDRs terminam em 31, 32, 33,
/// 34, 35 ou 39 (ex.: AAPL34, T1TW34); o resto é ação ou unit (PETR4,
/// TAEE11). O "F" do fracionário é ignorado.
String tipoPorTicker(String? ticker) {
  var t = (ticker ?? '').trim().toUpperCase();
  if (t.endsWith('F') && t.runes.length > 5) {
    t = t.substring(0, t.length - 1);
  }
  final m = RegExp(r'^[A-Z0-9]{4}([0-9]{2})$').firstMatch(t);
  return m != null && sufixosBdr.contains(m.group(1)) ? 'BDR' : 'Ação';
}

/// Ajusta o tipo (Ação/BDR) das compras do mês pelo ticker. Devolve verdadeiro
/// se algo mudou.
bool corrigirTiposMes(Mes d) {
  var mudou = false;
  for (final l in d.lotes) {
    final certo = tipoPorTicker(l.ticker);
    if (l.tipo != certo) {
      l.tipo = certo;
      mudou = true;
    }
  }
  return mudou;
}

/// Ganho ou perda da quantidade ainda não vendida: (valor em R$, variação em
/// %).
(double, double)? resultadoAberto(Lote lote, double? precoAtual) {
  if (precoAtual == null || precoAtual == 0 || restante(lote) <= 0) {
    return null;
  }
  return (
    (precoAtual - lote.preco) * restante(lote),
    (precoAtual / lote.preco - 1) * 100,
  );
}
