// Texto para as telas: item e linhas do cartão de sugestão e do rodapé
// (sugestoes.py:247-324).

import '../ambiente.dart';
import '../datas.dart';
import '../erros.dart';
import '../formatacao.dart';
import '../metas/verificacao.dart';
import '../modelos/barras.dart';
import '../modelos/lote.dart';
import 'patrimonio.dart';
import 'sugestoes.dart';

/// Tudo o que o cartão de uma compra mostra.
class ItemSugestao {
  ItemSugestao({
    required this.lote,
    required this.qtd,
    this.sug,
    this.aval,
    this.alerta,
    this.erro,
    this.precoAtual,
  });

  final Lote lote;
  final int qtd;
  Sugestao? sug;
  Avaliacao? aval;
  AlertaRisco? alerta;
  String? erro;
  double? precoAtual;
}

/// Tudo o que o cartão de uma compra mostra. [diarias]: [Diarias] da consulta,
/// ou a exceção / mensagem (texto) da consulta que falhou. [valorPatrimonio]:
/// valor de `patrimonio()` (opcional).
ItemSugestao montarItem(
  Lote lote,
  int qtd,
  Object diarias, {
  double? valorPatrimonio,
  String? hoje,
}) {
  final item = ItemSugestao(lote: lote, qtd: qtd);
  if (diarias is Exception) {
    item.erro = mensagemErro(diarias);
    return item;
  }
  if (diarias is String) {
    item.erro = diarias;
    return item;
  }
  final d = diarias as Diarias;
  // max(diarias["hoje"], date.today()): datas ISO comparam como texto
  final hojeAmbiente = ambiente.hoje();
  final hojeDiarias = d.hoje;
  hoje ??= hojeDiarias != null && hojeAmbiente.compareTo(hojeDiarias) > 0
      ? hojeAmbiente
      : (hojeDiarias ?? hojeAmbiente);
  item.precoAtual = d.preco;
  final Sugestao sug;
  try {
    sug = sugerir(lote, d.barras, hoje, d.preco);
  } on SemSugestao catch (e) {
    item.erro = e.toString();
    return item;
  }
  item.sug = sug;
  item.aval = avaliar(lote, qtd, sug, d.preco, sug.modo == 'day_trade');
  if (valorPatrimonio != null) {
    item.alerta = alertaRisco(item.aval!.perdaStop, valorPatrimonio);
  }
  return item;
}

/// Linha de texto de um cartão: (rótulo, valor, cor). Cor: nulo (texto
/// normal), `"accent"`, `"danger"`, `"aviso"` ou `"muted"`.
typedef LinhaCard = (String rotulo, String valor, String? cor);

/// Linhas do cartão de sugestão, iguais nas duas telas.
List<LinhaCard> linhasCard(ItemSugestao item) {
  if (item.erro != null && item.erro!.isNotEmpty) {
    return [('Sugestão', item.erro!, 'muted')];
  }
  final sug = item.sug!;
  final av = item.aval!;
  final atual = item.precoAtual;
  final swing = sug.modo == 'swing';
  final linhas = <LinhaCard>[
    (
      'Modo',
      '${swing ? 'Swing' : 'Day trade'} · ATR(14) ${brl(sug.atr14)} · '
          'pregão de ${fmtData(sug.baseData)}',
      null,
    ),
  ];
  if (atual != null && atual != 0) {
    linhas.add((
      'Cotação',
      '${brl(atual)} · compra ${brl(item.lote.preco)}',
      null,
    ));
  }
  linhas.add((
    'Alvo sugerido',
    '${brl(sug.alvo)} (${fmtPct(av.distAlvoPct)} da cotação) · '
        'lucro líquido ${brl(av.lucroAlvo)}',
    'accent',
  ));
  if (swing) {
    linhas.add((
      'Stop inicial',
      '${brl(sug.stopInicial!)} (compra − $multStopSwing×ATR)',
      null,
    ));
    linhas.add((
      'Stop móvel',
      sug.chandelier != null
          ? '${brl(sug.chandelier!)} (máxima de $periodoChandelier pregões − '
                '$multChandelier×ATR, só sobe)'
          : 'indisponível (histórico curto)',
      null,
    ));
  } else {
    linhas.add((
      'Pivôs do dia anterior',
      'suporte ${brl(sug.s1!)} · pivô ${brl(sug.pp!)} · '
          'resistência ${brl(sug.r1!)}',
      null,
    ));
  }
  final perda = av.perdaStop < 0;
  linhas.add((
    'Stop sugerido',
    '${brl(sug.stop)} (${fmtPct(av.distStopPct)} da cotação)'
        '${perda ? ' · perda líquida ${brl(av.perdaStop)}' : ''}',
    perda ? 'danger' : null,
  ));
  if (!perda) {
    linhas.add((
      'Lucro protegido no stop',
      'lucro líquido após imposto ${brl(av.perdaStop)}',
      'accent',
    ));
  }
  final rrTextos = <String>[];
  if (av.rrPreco != null) {
    rrTextos.add('1 : ${fmtDec(av.rrPreco!)} por preço');
  }
  if (av.rrLiquido != null) {
    rrTextos.add('1 : ${fmtDec(av.rrLiquido!)} líquido');
  }
  if (rrTextos.isNotEmpty) {
    linhas.add(('Risco/retorno', rrTextos.join(' · '), null));
  }
  final al = item.alerta;
  if (al != null && al.excede) {
    final pct = al.pct != null
        ? '${fmtDec(al.pct!, 2)}% do patrimônio'
        : 'sem patrimônio para comparar';
    linhas.add((
      'Alerta de risco',
      'A perda no stop (${brl(av.perdaStop.abs())}) é $pct; o limite de '
          '${fmtDec(limiteRisco * 100, 0)}% é ${brl(al.limite)}.',
      'danger',
    ));
  } else if (al != null && al.pct != null) {
    linhas.add((
      'Risco do stop',
      '${fmtDec(al.pct!, 2)}% do patrimônio (limite '
          '${fmtDec(limiteRisco * 100, 0)}%)',
      'muted',
    ));
  }
  for (final aviso in sug.avisos) {
    linhas.add(('Aviso', aviso, 'aviso'));
  }
  return linhas;
}

/// Resumo no pé da tela: patrimônio considerado e resultado do mês contra o
/// limite de 6%. [pat]: `patrimonio()`; [resultado]: `resultadoMes()`.
List<LinhaCard> linhasRodape(Patrimonio? pat, double resultado) {
  final linhas = <LinhaCard>[];
  if (pat != null) {
    final nota = pat.caixaDefinido ? '' : ' (caixa não definido: só posições)';
    linhas.add((
      'Patrimônio considerado',
      '${brl(pat.valor)} = caixa projetado ${brl(pat.caixa)} + '
          'posições ${brl(pat.posicoes)}$nota',
      null,
    ));
    if (pat.semCotacao.isNotEmpty) {
      linhas.add((
        'Sem cotação',
        '${pat.semCotacao.join(', ')} (fora do patrimônio)',
        'aviso',
      ));
    }
    if (pat.valor > 0) {
      final pct = resultado / pat.valor * 100;
      final excede = resultado < 0 && -resultado > pat.valor * limiteMes;
      linhas.add((
        'Resultado do mês',
        '${brl(resultado)} (${fmtPct(pct)} do patrimônio; limite de '
            'perda ${fmtDec(limiteMes * 100, 0)}%)',
        excede ? 'danger' : null,
      ));
      return linhas;
    }
  }
  linhas.add(('Resultado do mês', brl(resultado), null));
  return linhas;
}
