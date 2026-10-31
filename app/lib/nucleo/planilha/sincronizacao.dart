import 'package:collection/collection.dart';

import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../fechamento.dart';
import '../modelos/com_mod.dart';
import '../modelos/config.dart';
import '../modelos/mes.dart';
import '../modelos/meta.dart';
import '../radar.dart';
import '../repositorio.dart';
import 'celula.dart';
import 'mesclagem.dart';
import 'montagem.dart';
import 'reconstrucao.dart';

// Sincronização sem rede: mescla o que foi lido da planilha com os dados
// locais e devolve as linhas a gravar (nucleo.py:1171-1211;
// calculadora_darf.py:2865-2876; android/main.py:2357-2359).

const _igualdade = DeepCollectionEquality();

/// Instantâneo em JSON, para comparar "antes" e "depois" (no lugar do
/// `json.dumps(sort_keys=True)` do Python).
Object? _foto(Object? json) => copiaProfunda(json);

/// `mesclar_tudo` (nucleo.py:1171-1211): mescla os dados da planilha
/// ([remoto]) com os locais e grava o resultado. Devolve `true` se algo local
/// mudou. [metasR]: metas da planilha (`reconstruirMetas`). [avisos]: recebe os
/// textos para o usuário (venda duplicada de OCO em mês fechado, que precisa de
/// ajuste manual).
bool mesclarTudo(
  Repositorio repo,
  DadosPlanilha remoto,
  Config cfg, {
  List<Meta>? metasR,
  List<String>? avisos,
}) {
  var mudou = false;
  // mês -> (JSON local como carregado, mês mesclado)
  final mesclados = <String, (Object?, Mes)>{};
  final nomes = {...repo.listarMeses(), ...remoto.meses.keys};
  for (final mes in ordenadoPor(nomes, (m) => [m])) {
    final local = repo.existeMes(mes) ? repo.carregar(mes) : null;
    final textoLocal = local == null ? null : _foto(local.toJson());
    mesclados[mes] = (textoLocal, mesclarMes(local, remoto.meses[mes])!);
  }
  final metasL = ordenadoPor(cfg.metas, (m) => [m.criadaEm, m.id]);
  final textoMetas = _foto([for (final m in metasL) m.toJson()]);
  final metas = mesclarMetas(metasL, metasR ?? []);
  final meses = {for (final e in mesclados.entries) e.key: e.value.$2};
  deduplicarAuto(meses);
  resolverOco(meses, metas, avisos: avisos);
  for (final e in mesclados.entries) {
    final (textoLocal, novo) = e.value;
    if (textoLocal == null ||
        !_igualdade.equals(_foto(novo.toJson()), textoLocal)) {
      repo.salvar(novo, carimbar: false);
      mudou = true;
    }
  }
  final excl = {...remoto.excluidos};
  for (final e in cfg.excluidos.entries) {
    excl[e.key] = maxPython(e.value, excl[e.key] ?? 0.0);
  }
  final amigos = mesclarLista<Amigo>(
    cfg.amigos,
    remoto.amigos,
    (a) => a.email,
    excl,
    'amigos',
  );
  final radar = ordenarRadar(
    mesclarLista<ItemRadar>(
      cfg.radar,
      remoto.radar,
      (r) => r.ticker,
      excl,
      'radar',
    ),
  );
  final antes = _foto([
    [for (final a in cfg.amigos) a.toJson()],
    [for (final r in cfg.radar) r.toJson()],
    {...cfg.excluidos},
  ]);
  cfg.amigos = amigos;
  cfg.radar = radar;
  cfg.excluidos = excl;
  final depois = [
    [for (final a in amigos) a.toJson()],
    [for (final r in radar) r.toJson()],
    excl,
  ];
  if (!_igualdade.equals(depois, antes)) mudou = true;
  if (!_igualdade.equals([for (final m in metas) m.toJson()], textoMetas)) {
    mudou = true;
  }
  cfg.metas = metas;
  final caixaR = remoto.caixa;
  if (caixaR != null && caixaR.mod > cfg.caixa.mod) {
    cfg.caixa = caixaR;
    mudou = true;
  }
  repo.gravarConfig(cfg, carimbar: false);
  if (corrigirTipos(repo)) mudou = true;
  return mudou;
}

/// O que a sincronização sem rede produz: se algo local mudou, os avisos para
/// o usuário e as abas a gravar na planilha.
class ResultadoSincronizacao {
  ResultadoSincronizacao({
    required this.mudou,
    required this.avisos,
    required this.linhas,
  });

  final bool mudou;
  final List<String> avisos;
  final Map<String, List<Linha>> linhas;
}

/// Mescla as [abasLidas] (já passadas por `normalizarLeitura`) com os dados
/// locais e monta as linhas de todos os meses locais para gravar de volta
/// (calculadora_darf.py:2865-2876; android/main.py:2357-2359).
ResultadoSincronizacao sincronizarLinhas(
  Repositorio repo,
  Config cfg,
  Map<String, List<Linha>> abasLidas,
) {
  final avisos = <String>[];
  final mudou = mesclarTudo(
    repo,
    reconstruir(abasLidas),
    cfg,
    metasR: reconstruirMetas(abasLidas),
    avisos: avisos,
  );
  final linhas = montarLinhas(repo.carregarMeses().values.toList(), cfg);
  return ResultadoSincronizacao(mudou: mudou, avisos: avisos, linhas: linhas);
}
