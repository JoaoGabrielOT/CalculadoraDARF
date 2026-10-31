// Localização da compra: cadeia de cópias levadas entre meses, reserva por metas
// ativas e compras abertas (metas.py:116-196, 431-432).

import '../apuracao.dart';
import '../compat/ordenacao.dart';
import '../modelos/config.dart';
import '../modelos/lote.dart';
import '../modelos/mes.dart';
import '../modelos/meta.dart';
import '../repositorio.dart';

/// Um elo da cadeia: o mês, os dados do mês e a compra.
typedef ElosCadeia = ({String mes, Mes dados, Lote lote});

/// `_cadeia`: a compra e as cópias levadas para os meses seguintes (origem), em
/// ordem. Para no primeiro id já visto (proteção contra ciclo).
List<ElosCadeia> cadeia(Map<String, Mes> meses, String loteId) {
  final porId = <String, ElosCadeia>{};
  final filho = <String, String>{};
  for (final e in meses.entries) {
    for (final l in e.value.lotes) {
      porId[l.id] = (mes: e.key, dados: e.value, lote: l);
      if (l.origem != null && l.origem!.isNotEmpty) filho[l.origem!] = l.id;
    }
  }
  final saida = <ElosCadeia>[];
  String? atual = loteId;
  while (atual != null &&
      porId.containsKey(atual) &&
      saida.every((c) => c.lote.id != atual)) {
    saida.add(porId[atual]!);
    atual = filho[atual];
  }
  return saida;
}

/// `_venda_existente`: a compra e a venda com esse id, em qualquer mês.
(Lote, Venda)? vendaExistente(Map<String, Mes> meses, String vendaId) {
  for (final d in meses.values) {
    for (final l in d.lotes) {
      for (final v in l.vendas) {
        if (v.id == vendaId) return (l, v);
      }
    }
  }
  return null;
}

/// `_raizes`: `{id da compra: id da compra original}`, seguindo `origem` das
/// cópias levadas na virada de mês.
Map<String, String> raizes(Map<String, Mes> meses) {
  final origem = <String, String>{
    for (final d in meses.values)
      for (final l in d.lotes)
        if (l.origem != null && l.origem!.isNotEmpty) l.id: l.origem!,
  };
  String raiz(String i) {
    final visto = <String>{};
    while (origem.containsKey(i) && !visto.contains(i)) {
      visto.add(i);
      i = origem[i]!;
    }
    return i;
  }

  return {for (final i in origem.keys) i: raiz(i)};
}

/// Metas com `status == "ativa"`.
List<Meta> metasAtivas(Config cfg) => [
  for (final m in cfg.metas)
    if (m.status == 'ativa') m,
];

/// Quantidade da compra já comprometida com metas ativas, somando as metas
/// feitas sobre a compra original ou sobre qualquer cópia dela nos meses
/// seguintes. Um par OCO (alvo + stop) conta uma vez só (a maior quantidade).
/// [ignorar]: ids de metas que não entram na conta.
int reservado(
  Repositorio repo,
  Config cfg,
  String loteId, {
  Map<String, Mes>? meses,
  Set<String> ignorar = const {},
}) {
  final r = raizes(meses ?? repo.carregarMeses());
  final alvo = r[loteId] ?? loteId;
  var total = 0;
  final grupos = <String, int>{};
  for (final m in cfg.metas) {
    if (m.status != 'ativa' ||
        ignorar.contains(m.id) ||
        (r[m.loteId] ?? m.loteId) != alvo) {
      continue;
    }
    final oco = m.oco;
    if (oco != null && oco.isNotEmpty) {
      final atual = grupos[oco] ?? 0;
      grupos[oco] = m.qtd > atual ? m.qtd : atual;
    } else {
      total += m.qtd;
    }
  }
  return total + grupos.values.fold(0, (a, b) => a + b);
}

/// `_lotes_abertos`: compras de meses abertos com saldo, uma por cadeia de
/// cópias (vale a do mês mais recente; se essa já foi toda vendida, a compra
/// não está aberta).
List<ElosCadeia> lotesAbertos(Map<String, Mes> meses) {
  final r = raizes(meses);
  final porRaiz = <String, ElosCadeia>{};
  for (final mes in ordenadoPor(meses.keys, (m) => [m])) {
    final d = meses[mes]!;
    if (d.fechado) continue;
    for (final l in d.lotes) {
      porRaiz[r[l.id] ?? l.id] = (mes: mes, dados: d, lote: l);
    }
  }
  return ordenadoPor(
    porRaiz.values.where((x) => restante(x.lote) > 0),
    (x) => [x.mes, x.lote.ticker, x.lote.id],
  );
}

/// Compra aberta com saldo, a quantidade livre e as metas ativas dela.
typedef PosicaoAberta = ({
  String mes,
  Lote lote,
  int restante,
  int livre,
  List<Meta> ativas,
});

/// `posicoes_abertas`: todas as compras abertas com saldo. Diferente de
/// [lotesParaMeta], não esconde as que estão com a quantidade toda reservada
/// (livre 0).
List<PosicaoAberta> posicoesAbertas(Repositorio repo, Config cfg) {
  final meses = repo.carregarMeses();
  final r = raizes(meses);
  final saida = <PosicaoAberta>[];
  for (final x in lotesAbertos(meses)) {
    final l = x.lote;
    final raiz = r[l.id] ?? l.id;
    final ativas = [
      for (final m in metasAtivas(cfg))
        if ((r[m.loteId] ?? m.loteId) == raiz) m,
    ];
    final saldo = restante(l);
    saida.add((
      mes: x.mes,
      lote: l,
      restante: saldo,
      livre: saldo - reservado(repo, cfg, l.id, meses: meses),
      ativas: ativas,
    ));
  }
  return saida;
}

/// Compra de mês aberto com quantidade livre.
typedef LoteLivre = ({String mes, Lote lote, int livre});

/// `lotes_para_meta`: compras de meses abertos com quantidade livre (sem
/// contar as metas ativas).
List<LoteLivre> lotesParaMeta(Repositorio repo, Config cfg) {
  final saida = <LoteLivre>[];
  final meses = repo.carregarMeses();
  for (final e in meses.entries) {
    if (e.value.fechado) continue;
    for (final l in e.value.lotes) {
      final livre = restante(l) - reservado(repo, cfg, l.id, meses: meses);
      if (livre > 0) saida.add((mes: e.key, lote: l, livre: livre));
    }
  }
  return saida;
}
