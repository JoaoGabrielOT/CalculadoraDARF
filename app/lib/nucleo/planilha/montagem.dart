// Linhas que o app grava em cada aba da planilha (nucleo.py:777-834).

import '../apuracao.dart';
import '../compat/json_python.dart';
import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../datas.dart';
import '../modelos/config.dart';
import '../modelos/meta.dart';
import '../modelos/mes.dart';
import '../radar.dart';
import 'celula.dart';

/// Campos da meta que vão no JSON da coluna Detalhes (nucleo.py:777-778).
const camposDetalhes = [
  'oco',
  'stop_inicial',
  'stop_atual',
  'movel',
  'niveis',
  'cancelada_por',
  'cancelada_detalhe',
  'sugestao',
];

/// Linha da aba Metas (14 colunas; nucleo.py:781-795). Na meta de stop o
/// Preço-alvo fica vazio.
Linha linhaMeta(Meta m) {
  final stop = m.gatilho == 'stop';
  final valores = <String, Object?>{
    'oco': m.oco,
    'stop_inicial': m.stopInicial,
    'stop_atual': m.stopAtual,
    'movel': m.movel,
    'niveis': m.niveis == null ? null : [for (final n in m.niveis!) n.toJson()],
    'cancelada_por': m.canceladaPor,
    'cancelada_detalhe': m.canceladaDetalhe,
    'sugestao': m.sugestao,
  };
  final gatilho = stop ? 'stop' : 'alvo';
  final detalhes = <String, Object?>{'id': m.id, 'gatilho': gatilho};
  for (final k in camposDetalhes) {
    final v = valores[k];
    if (v != null && v != '') detalhes[k] = v;
  }
  final execucao = m.execucao;
  return [
    m.id,
    m.ticker,
    m.tipo,
    m.loteId,
    m.qtd,
    stop ? '' : m.precoAlvo,
    m.lucroDesejado ?? '',
    m.criadaEm,
    m.statusOuAtiva,
    m.ultimoErro ?? '',
    execucao != null && execucao.isNotEmpty ? jsonPython(execucao) : '',
    m.mod,
    gatilho,
    jsonPython(detalhes, compacto: true),
  ];
}

/// Coluna Detalhes do Resumo (§5.3): o marcador de custo médio com o próprio
/// mês (protege contra linhas desalinhadas por uma gravação da 1.12); vazia
/// no método por compra.
String detalhesResumo(Mes d) {
  if (d.metodo != metodoCustoMedio) return '';
  final j = d.toJson();
  return jsonPython({
    'mes': d.mes,
    'mod': d.mod,
    for (final k in camposMetodo)
      if (j.containsKey(k)) k: j[k],
  }, compacto: true);
}

/// As oito abas a gravar, a partir dos [meses] já carregados (na ordem em que
/// vão para a planilha) e da configuração [cfg].
Map<String, List<Linha>> montarLinhas(List<Mes> meses, Config cfg) {
  final resumo = <Linha>[];
  final compras = <Linha>[];
  final vendas = <Linha>[];
  final excl = <Linha>[];
  for (final d in meses) {
    final r = apurar(d);
    final m = fmtMes(d.mes);
    resumo.add([
      m,
      d.fechado ? 'Fechado' : 'Aberto',
      arredondar(r.vendasAcoesSt, 2),
      r.isento ? 'Sim' : 'Não',
      arredondar(r.bruto, 2),
      arredondar(r.custos, 2),
      arredondar(r.impSt, 2),
      arredondar(r.impDt, 2),
      arredondar(r.irrf, 2),
      arredondar(r.lucroLiquido, 2),
      arredondar(r.darfAnterior, 2),
      arredondar(r.darf, 2),
      d.mod,
      detalhesResumo(d),
    ]);
    final ops = {for (final o in r.ops) o.vendaId: o};
    final linhasV = <Linha>[];
    for (final l in d.lotes) {
      compras.add([
        m,
        l.ticker,
        l.tipo,
        serial(l.dataCompra),
        l.qtd,
        l.preco,
        arredondar(l.qtd * l.preco, 2),
        vendido(l),
        restante(l),
        statusLote(l),
        l.id,
        l.origem ?? '',
        l.mod,
      ]);
      for (final v in l.vendas) {
        final o = ops[v.id]!;
        linhasV.add([
          m,
          l.ticker,
          l.tipo,
          serial(l.dataCompra),
          l.preco,
          serial(v.data),
          v.qtd,
          v.preco,
          arredondar(o.venda, 2),
          o.regime,
          arredondar(o.taxas + o.corretagem, 2),
          arredondar(o.bruto, 2),
          arredondar(o.liquido, 2),
          arredondar(o.imposto, 2),
          v.id,
          l.id,
          v.mod,
        ]);
      }
    }
    vendas.addAll(ordenadoPor(linhasV, (x) => [x[5]! as int]));
    for (final e in d.excluidos.entries) {
      excl.add(['registro', m, e.key, e.value]);
    }
  }
  for (final e in cfg.excluidos.entries) {
    final i = e.key.indexOf(':');
    if (i < 0) throw FormatException('chave de exclusão sem ":": "${e.key}"');
    excl.add([e.key.substring(0, i), '', e.key.substring(i + 1), e.value]);
  }
  final caixa = cfg.caixa;
  return {
    'Resumo': resumo,
    'Compras': compras,
    'Vendas': vendas,
    'Amigos': [
      for (final a in cfg.amigos) [a.email, serial(a.desde), a.mod],
    ],
    'Radar': [
      for (final (i, r) in ordenarRadar(cfg.radar).indexed)
        [r.ticker, r.nome, serial(r.desde), r.mod, r.pos ?? i],
    ],
    'Caixa': caixa.data.isEmpty
        ? <Linha>[]
        : [
            [arredondar(caixa.saldo, 2), serial(caixa.data), caixa.mod],
          ],
    'Metas': [
      for (final m in ordenadoPor(cfg.metas, (m) => [m.criadaEm, m.id]))
        linhaMeta(m),
    ],
    'Exclusões': excl,
  };
}
