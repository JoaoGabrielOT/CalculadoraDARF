import '../ambiente.dart';
import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../datas.dart';
import '../modelos/com_mod.dart';
import '../modelos/lote.dart';
import '../modelos/mes.dart';
import '../modelos/meta.dart';

// Mesclagem entre aparelhos (nucleo.py:977-1168). Onde o Python monta um
// dicionário novo, as chaves saem na mesma ordem (por isso os objetos novos
// nascem de JSON montado na ordem do Python).

/// `_escolher` (nucleo.py:979-985): o registro alterado por último; [a] vence
/// o empate.
T? escolher<T extends ComMod>(T? a, T? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.mod >= b.mod ? a : b;
}

/// Lado de onde vem o marcador de método (§5.3): o vencedor por `mod`, com
/// uma exceção monotônica quando só um lado tem o custo médio (planilha
/// regravada por uma 1.12, migração concorrente em dois aparelhos): o
/// marcador fica, a menos que o vencedor seja um mês fechado sem marcador
/// (fechado pelo método antigo) e o lado marcado ainda esteja aberto. Com os
/// dois marcados, um lado sem posição inicial (ausente ou vazia) não vence o
/// que tem.
Mes _ladoDoMetodo(Mes vencedor, Mes local, Mes remoto) {
  bool temPosicao(Mes m) => m.posicaoInicial?.isNotEmpty ?? false;
  final marcadoL = local.metodo == metodoCustoMedio;
  if (marcadoL == (remoto.metodo == metodoCustoMedio)) {
    if (!marcadoL || temPosicao(vencedor)) return vencedor;
    final outro = identical(vencedor, local) ? remoto : local;
    return temPosicao(outro) ? outro : vencedor;
  }
  final marcado = marcadoL ? local : remoto;
  if (vencedor.fechado && !marcado.fechado) return vencedor;
  return marcado;
}

/// `mesclar_mes` (nucleo.py:988-1022). Com um lado nulo devolve o outro (a
/// mesma instância); senão devolve objetos novos, sem `retroativo`, e o
/// `resumo` só vem do vencedor quando ele está fechado. O marcador de método
/// segue `_ladoDoMetodo`.
Mes? mesclarMes(Mes? local, Mes? remoto) {
  if (local == null) return remoto;
  if (remoto == null) return local;
  final meta = escolher(local, remoto)!;
  final excl = {...remoto.excluidos};
  for (final e in local.excluidos.entries) {
    excl[e.key] = maxPython(e.value, excl[e.key] ?? 0.0);
  }

  bool apagado(ComMod x, String id) => (excl[id] ?? -1.0) >= x.mod;

  final lotesL = {for (final l in local.lotes) l.id: l};
  final lotesR = {for (final l in remoto.lotes) l.id: l};
  // local por último: vence empates
  final vendas = <String, (String, Venda)>{};
  for (final lado in [remoto.lotes, local.lotes]) {
    for (final l in lado) {
      for (final v in l.vendas) {
        final atual = vendas[v.id];
        final escolhido = atual != null ? escolher(v, atual.$2)! : v;
        vendas[v.id] = (l.id, escolhido);
      }
    }
  }
  final ordem = [
    ...lotesL.keys,
    for (final i in lotesR.keys)
      if (!lotesL.containsKey(i)) i,
  ];
  final lotes = <Map<String, Object?>>[];
  for (final i in ordem) {
    final l = escolher(lotesL[i], lotesR[i])!;
    if (apagado(l, l.id)) continue;
    final novo = l.toJson()..remove('vendas');
    novo['vendas'] = [
      for (final v in ordenadoPor([
        for (final (lid, v) in vendas.values)
          if (lid == i && !apagado(v, v.id)) v,
      ], (v) => [v.data, v.id]))
        v.toJson(),
    ];
    lotes.add(novo);
  }
  final metodo = _ladoDoMetodo(meta, local, remoto).toJson();
  return Mes.fromJson({
    'mes': local.mes,
    'fechado': meta.fechado,
    'darf_anterior': meta.darfAnterior,
    'mod': meta.mod,
    'lotes': lotes,
    'excluidos': excl,
    if (meta.resumo != null && meta.fechado) 'resumo': meta.resumo!.toJson(),
    for (final k in camposMetodo)
      if (metodo.containsKey(k)) k: metodo[k],
  });
}

/// `deduplicar_auto` (nucleo.py:1025-1038): a venda automática `auto-...` só
/// pode existir em um mês; fica a do mês mais antigo. Altera [meses] no lugar
/// e devolve os meses alterados.
Set<String> deduplicarAuto(Map<String, Mes> meses) {
  final vistas = <String>{};
  final alterados = <String>{};
  for (final mes in ordenadoPor(meses.keys, (m) => [m])) {
    for (final l in meses[mes]!.lotes) {
      final antes = l.vendas.length;
      l.vendas = [
        for (final v in l.vendas)
          if (!v.id.startsWith('auto-') || !vistas.contains(v.id)) v,
      ];
      vistas.addAll([
        for (final v in l.vendas)
          if (v.id.startsWith('auto-')) v.id,
      ]);
      if (l.vendas.length != antes) alterados.add(mes);
    }
  }
  return alterados;
}

/// `mesclar_lista` (nucleo.py:1041-1045): amigos e radar pela [chave]; some o
/// item cuja exclusão (`"<prefixo>:<chave>"` em [excl]) é igual ou posterior
/// ao seu `mod`.
List<T> mesclarLista<T extends ComMod>(
  List<T> local,
  List<T> remoto,
  String Function(T) chave,
  Map<String, double> excl,
  String prefixo,
) {
  final itens = {for (final x in remoto) chave(x): x};
  for (final x in local) {
    itens[chave(x)] = escolher(x, itens[chave(x)])!;
  }
  return [
    for (final e in itens.entries)
      if ((excl['$prefixo:${e.key}'] ?? -1.0) < e.value.mod) e.value,
  ];
}

/// `_unir_niveis` (nucleo.py:1048-1055): um nível por data (`desde`), com o
/// maior stop.
List<Nivel> unirNiveis(List<Nivel>? a, List<Nivel>? b) {
  final porData = <String, Nivel>{};
  for (final n in [...?a, ...?b]) {
    final o = porData[n.desde];
    if (o == null || n.stop > o.stop) {
      porData[n.desde] = Nivel(desde: n.desde, stop: n.stop, calcEm: n.calcEm);
    }
  }
  return [
    for (final d in ordenadoPor(porData.keys, (d) => [d])) porData[d]!,
  ];
}

const _camposStop = [
  'gatilho',
  'stop_inicial',
  'stop_atual',
  'movel',
  'niveis',
];

/// Só a versão nova grava estes campos.
const _camposNovos = [
  ..._camposStop,
  'oco',
  'cancelada_por',
  'cancelada_detalhe',
  'sugestao',
];

/// `_completar_meta` (nucleo.py:1061-1076): copia para a [vencedora] os campos
/// novos que ela não tem e a [perdedora] tem. Os do stop só vêm de um stop (e
/// nunca para uma meta com preço-alvo); o motivo do cancelamento só para uma
/// meta cancelada. Sem nada a copiar devolve a própria [vencedora].
Meta completarMeta(Meta vencedora, Meta perdedora) {
  final v = vencedora.toJson();
  final p = perdedora.toJson();
  final extra = <String, Object?>{};
  for (final k in _camposNovos) {
    if (v.containsKey(k) || p[k] == null || p[k] == '') continue;
    if (_camposStop.contains(k) &&
        (p['gatilho'] != 'stop' || v.containsKey('preco_alvo'))) {
      continue;
    }
    if ((k == 'cancelada_por' || k == 'cancelada_detalhe') &&
        vencedora.status != 'cancelada') {
      continue;
    }
    extra[k] = p[k];
  }
  return extra.isEmpty ? vencedora : Meta.fromJson({...v, ...extra});
}

/// `_precedencia` (nucleo.py:1079-1081): status que não se desfaz.
int precedencia(Meta m) => switch (m.status) {
  'executada' => 2,
  'cancelada' => 1,
  _ => 0,
};

/// `mesclar_metas` (nucleo.py:1084-1112): "executada" vence qualquer outro
/// status, "cancelada" vence "ativa" e nos demais casos vale a alteração mais
/// recente. Dois stops móveis não executados ficam com a união dos níveis e o
/// maior stop.
List<Meta> mesclarMetas(List<Meta> local, List<Meta> remoto) {
  final itens = {for (final m in remoto) m.id: m};
  for (final m in local) {
    final o = itens[m.id];
    if (o == null) {
      itens[m.id] = m;
      continue;
    }
    final Meta vencedora;
    final Meta perdedora;
    if (precedencia(m) != precedencia(o)) {
      (vencedora, perdedora) = precedencia(m) > precedencia(o)
          ? (m, o)
          : (o, m);
    } else {
      vencedora = escolher(m, o)!;
      perdedora = identical(vencedora, m) ? o : m;
    }
    itens[m.id] = completarMeta(vencedora, perdedora);
    if (m.gatilho == 'stop' &&
        o.gatilho == 'stop' &&
        m.movel == true &&
        o.movel == true &&
        m.status != 'executada' &&
        o.status != 'executada') {
      final niveis = unirNiveis(m.niveis, o.niveis);
      final json = itens[m.id]!.toJson();
      json['niveis'] = [for (final n in niveis) n.toJson()];
      json['stop_atual'] = maxDe([
        for (final n in niveis) n.stop,
        m.stopAtual!,
        o.stopAtual!,
      ]);
      itens[m.id] = Meta.fromJson(json);
    }
  }
  return ordenadoPor(itens.values, (m) => [m.criadaEm, m.id]);
}

num _numeroOuZero(Object? v) => v is num ? v : 0;

/// `_execucao_antes` (nucleo.py:1115-1129): ordem (-1, 0 ou 1) das execuções
/// de duas metas do mesmo OCO. A data; na mesma data, o horário da barra
/// (`barra_ts` quando as duas têm, senão a hora, se as duas têm); persistindo
/// o empate, o stop vence e por fim o id.
int execucaoAntes(Meta a, Meta b) {
  final ea = a.execucao ?? const <String, Object?>{};
  final eb = b.execucao ?? const <String, Object?>{};
  final ta = _numeroOuZero(ea['barra_ts']);
  final tb = _numeroOuZero(eb['barra_ts']);
  final ha = lerTexto(ea['hora']);
  final hb = lerTexto(eb['hora']);
  var c = compararTexto(lerTexto(ea['data']), lerTexto(eb['data']));
  if (c == 0 && ta > 0 && tb > 0) c = ta.compareTo(tb);
  if (c == 0 && ha.isNotEmpty && hb.isNotEmpty) c = compararTexto(ha, hb);
  if (c == 0) {
    c = (a.gatilho == 'stop' ? 0 : 1).compareTo(b.gatilho == 'stop' ? 0 : 1);
  }
  if (c == 0) c = compararTexto(a.id, b.id);
  return c.sign;
}

/// Fatia `s[de:ate]` do Python (por ponto de código, sem estourar o limite).
String _fatia(String s, int de, int ate) =>
    String.fromCharCodes(s.runes.skip(de).take(ate - de));

/// `resolver_oco` (nucleo.py:1132-1168): se as duas metas de um grupo OCO
/// estão "executada", fica a de execução mais cedo (empate: o stop). A outra
/// vira "cancelada" (com `mod` novo) e a venda automática dela é removida, com
/// registro de exclusão. Venda em mês fechado fica, e o texto vai para
/// [avisos]. Altera [meses] e [metas] no lugar e devolve os meses alterados.
Set<String> resolverOco(
  Map<String, Mes> meses,
  List<Meta> metas, {
  List<String>? avisos,
}) {
  final grupos = <String, List<Meta>>{};
  for (final m in metas) {
    final oco = m.oco;
    if (oco != null && oco.isNotEmpty && m.status == 'executada') {
      grupos.putIfAbsent(oco, () => []).add(m);
    }
  }
  final alterados = <String>{};
  for (final grupo in grupos.values) {
    if (grupo.length < 2) continue;
    final membros = ordenadoCom(grupo, execucaoAntes);
    final vencedora = membros[0];
    for (final perdedora in membros.skip(1)) {
      final ex = vencedora.execucao ?? const <String, Object?>{};
      final data = ex['data'];
      final quando = data is String && data.isNotEmpty
          ? '${_fatia(data, 8, 10)}/${_fatia(data, 5, 7)}'
          : '?';
      var detalhe =
          'Cancelada automaticamente (OCO): '
          '${vencedora.gatilho == 'stop' ? 'stop' : 'alvo'} executado em $quando';
      final vid = 'auto-${perdedora.id}';
      for (final MapEntry(key: mes, value: d) in meses.entries) {
        for (final l in d.lotes) {
          if (!l.vendas.any((v) => v.id == vid)) continue;
          if (d.fechado) {
            detalhe +=
                '. A venda duplicada ficou em ${fmtMes(mes)}, mês fechado, e '
                'precisa de ajuste manual';
            avisos?.add(
              '${perdedora.ticker}: a venda automática duplicada ficou no mês '
              'fechado ${fmtMes(mes)} e não foi removida. Ajuste manual '
              'necessário.',
            );
            continue;
          }
          l.vendas = [
            for (final v in l.vendas)
              if (v.id != vid) v,
          ];
          d.excluidos[vid] = ambiente.agora();
          alterados.add(mes);
        }
      }
      perdedora.status = 'cancelada';
      perdedora.ultimoErro = null;
      perdedora.execucao = null;
      perdedora.canceladaPor = vencedora.id;
      perdedora.canceladaDetalhe = detalhe;
      perdedora.mod = ambiente.agora();
    }
  }
  return alterados;
}
