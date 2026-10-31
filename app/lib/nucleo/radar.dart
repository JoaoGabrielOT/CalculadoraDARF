// Lista do radar: ordem, inclusão e filtros (nucleo.py:231-254;
// mercado.py:514-548).

import 'ambiente.dart';
import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'mercado/dados_ativo.dart';
import 'modelos/config.dart';

const filtrosRadar = ['Todos', 'Em alta', 'Em queda', 'Em carteira'];

/// (chave, rótulo).
const ordensRadar = <(String, String)>[
  ('manual', 'Minha ordem'),
  ('alta', 'Maior alta do dia'),
  ('queda', 'Maior queda do dia'),
  ('ticker', 'Ticker (A–Z)'),
  ('risco', 'Menor risco (ATR%)'),
  ('media', 'Mais abaixo da média 6m'),
];

/// Radar na ordem escolhida pelo usuário (campo pos); itens sem pos mantêm a
/// posição relativa.
List<ItemRadar> ordenarRadar(List<ItemRadar> radar) {
  final ordenados = ordenadoPor(radar.indexed, (e) => [e.$2.pos ?? e.$1, e.$1]);
  return [for (final (_, r) in ordenados) r];
}

/// Inclui o ativo no fim do radar (não grava).
ItemRadar? adicionarRadar(Config cfg, String ticker, {String nome = ''}) {
  final radar = cfg.radar;
  if (radar.any((r) => r.ticker == ticker)) return null;
  final pos = radar.isEmpty
      ? 0
      : maxDe([for (final (i, r) in radar.indexed) (r.pos ?? i).toDouble()])
                .toInt() +
            1;
  final item = ItemRadar(
    ticker: ticker,
    nome: nome,
    desde: ambiente.hoje(),
    pos: pos,
  );
  radar.add(item);
  return item;
}

/// Aplica a nova ordem (lista de tickers); a posição vai para a planilha e
/// sincroniza entre aparelhos.
void reordenarRadar(Config cfg, List<String> tickers) {
  final porTicker = {for (final r in cfg.radar) r.ticker: r};
  final novos = [
    for (final t in tickers)
      if (porTicker[t] != null) porTicker[t]!,
    for (final r in ordenarRadar(cfg.radar))
      if (!tickers.contains(r.ticker)) r,
  ];
  for (final (i, r) in novos.indexed) {
    r.pos = i;
  }
  cfg.radar = novos;
}

/// Itens do radar filtrados e ordenados com as cotações em [dados]. Ativos
/// ainda sem cotação ficam no fim das ordenações por número.
List<ItemRadar> filtrarOrdenar(
  List<ItemRadar> itens,
  Map<String, DadosAtivo> dados, {
  String filtro = 'Todos',
  String ordem = 'manual',
  Set<String> custodia = const {},
}) {
  double? varPct(ItemRadar i) => dados[i.ticker]?.variacaoPct;
  double? atrPct(ItemRadar i) => dados[i.ticker]?.atrPct;
  double? vsMedia(ItemRadar i) => dados[i.ticker]?.vsMediaPct;

  if (filtro == 'Em alta') {
    itens = [
      for (final i in itens)
        if ((varPct(i) ?? 0) > 0) i,
    ];
  } else if (filtro == 'Em queda') {
    itens = [
      for (final i in itens)
        if ((varPct(i) ?? 0) < 0) i,
    ];
  } else if (filtro == 'Em carteira') {
    itens = [
      for (final i in itens)
        if (custodia.contains(i.ticker)) i,
    ];
  }
  if (ordem == 'ticker') {
    return ordenadoPor(itens, (i) => [i.ticker]);
  }
  final (double? Function(ItemRadar) campo, bool desc)? chave = switch (ordem) {
    'alta' => (varPct, true),
    'queda' => (varPct, false),
    'risco' => (atrPct, false),
    'media' => (vsMedia, false),
    _ => null,
  };
  if (chave != null) {
    final (campo, desc) = chave;
    final com = [
      for (final i in itens)
        if (campo(i) != null) i,
    ];
    final sem = [
      for (final i in itens)
        if (campo(i) == null) i,
    ];
    return [
      ...ordenadoPor(com, (i) => [campo(i)!], reverso: desc),
      ...sem,
    ];
  }
  return List.of(itens);
}

/// (quantos em alta, quantos em queda, variação média do dia em %) dos ativos
/// com cotação.
(int, int, double?) resumoDia(
  List<String> tickers,
  Map<String, DadosAtivo> dados,
) {
  final vs = [
    for (final t in tickers)
      if (dados[t]?.variacaoPct != null) dados[t]!.variacaoPct!,
  ];
  return (
    vs.where((v) => v > 0).length,
    vs.where((v) => v < 0).length,
    vs.isEmpty ? null : somaPython(vs) / vs.length,
  );
}
