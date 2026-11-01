// Verificação e execução automática de metas (metas.py:23-24, 420-460,
// 463-742).

import 'dart:async';

import '../ambiente.dart';
import '../apuracao.dart';
import '../compat/ordenacao.dart';
import '../datas.dart';
import '../erros.dart';
import '../formatacao.dart';
import '../modelos/barras.dart';
import '../modelos/config.dart';
import '../modelos/lote.dart';
import '../modelos/meta.dart';
import '../planilha/mesclagem.dart';
import '../repositorio.dart';
import 'cadeia.dart';
import 'criacao.dart';
import 'deteccao.dart';
import 'preco_alvo.dart';

/// `historico(ticker, desde)` de metas.py: barras intradiárias desde [desde].
typedef BuscarHistorico = Future<HistoricoIntradiario> Function(
  String ticker,
  DataHora desde,
);

/// `diarias(ticker, desde)` de metas.py: barras diárias desde [desde]
/// (`AAAA-MM-DD`).
typedef BuscarDiarias = Future<Diarias> Function(String ticker, String desde);

/// Resultado da consulta de um ticker: `("ok", resultado)` ou
/// `("erro", mensagem)` no Python.
sealed class ResultadoHistorico {
  const ResultadoHistorico();
}

class HistoricoOk extends ResultadoHistorico {
  const HistoricoOk(this.historico);

  final HistoricoIntradiario historico;
}

class HistoricoErro extends ResultadoHistorico {
  const HistoricoErro(this.mensagem);

  final String mensagem;
}

/// Relatório de `aplicar`: listas de metas, se algo mudou e os avisos para o
/// usuário (venda duplicada de OCO em mês fechado, que exige ajuste manual).
class RelatorioMetas {
  final List<Meta> executadas = [];
  final List<Meta> invalidas = [];
  final List<Meta> reconciliadas = [];
  final List<Meta> aguardando = [];
  final List<Meta> erros = [];
  bool mudou = false;
  final List<String> avisos = [];
}

/// Resultado de `preparar_fechamento`.
class PreparoFechamento {
  String? bloqueio;
  final List<Meta> executadas = [];
  final List<Meta> invalidas = [];
}

/// `mensagem_erro`: o texto que a tela mostra quando a consulta falha.
String mensagemErro(Object e) {
  final nome = e.runtimeType.toString();
  final texto = e.toString();
  if (e is SemDados) return texto;
  if (e is LimiteConsultas || texto.contains('Too Many')) {
    return 'Limite de consultas do Yahoo atingido. Tente em alguns minutos.';
  }
  if (e is ErroConexao ||
      e is TimeoutException ||
      nome.contains('Connection') ||
      nome.contains('Socket') ||
      nome.contains('Timeout') ||
      texto.toLowerCase().contains('resolve')) {
    return 'Sem conexão com a internet.';
  }
  return 'Erro ao consultar o histórico: '
      '${String.fromCharCodes(texto.runes.take(120))}';
}

/// Instante de uma data/hora de meta (`_dt`): sem fuso vale Brasília.
DataHora _dt(String texto) => DataHora.parse(texto);

/// Os primeiros 10 caracteres (por ponto de código), como `s[:10]`.
String _dez(String s) => String.fromCharCodes(s.runes.take(10));

/// Baixa o histórico de cada ticker desde a meta mais antiga. [historico]
/// devolve as barras intradiárias; [diarias] (barras diárias) é buscado
/// também para os tickers com stop móvel e guardado no resultado (nulo se a
/// consulta falhar; o stop então fica como está). Devolve, por ticker, o
/// histórico ou a mensagem de erro.
Future<Map<String, ResultadoHistorico>> buscarHistoricos(
  List<Meta> metas,
  BuscarHistorico historico, {
  BuscarDiarias? diarias,
}) async {
  final desde = <String, DataHora>{};
  final desdeMovel = <String, DataHora>{};
  for (final m in metas) {
    final c = _dt(m.criadaEm);
    final atual = desde[m.ticker];
    desde[m.ticker] = atual != null && atual < c ? atual : c;
    if (gatilho(m) == 'stop' && m.movel == true) {
      final movel = desdeMovel[m.ticker];
      desdeMovel[m.ticker] = movel != null && movel < c ? movel : c;
    }
  }
  final saida = <String, ResultadoHistorico>{};
  for (final MapEntry(key: ticker, value: d) in desde.entries) {
    HistoricoIntradiario res;
    try {
      res = await historico(ticker, d);
    } catch (e) {
      saida[ticker] = HistoricoErro(mensagemErro(e));
      continue;
    }
    if (diarias != null && desdeMovel.containsKey(ticker)) {
      Diarias? dia;
      try {
        dia = await diarias(ticker, desdeMovel[ticker]!.data);
      } catch (_) {
        dia = null;
      }
      res = HistoricoIntradiario(
        barras: res.barras,
        fonte: res.fonte,
        intervalo: res.intervalo,
        diarias: dia,
      );
    }
    saida[ticker] = HistoricoOk(res);
  }
  return saida;
}

/// Altera status/erro da meta; devolve true se algo mudou (`_marcar`).
bool _marcar(Meta meta, String status, [String? erro]) {
  final antesStatus = meta.status;
  final antesErro = meta.ultimoErro;
  meta.status = status;
  meta.ultimoErro = erro != null && erro.isNotEmpty ? erro : null;
  return antesStatus != meta.status || antesErro != meta.ultimoErro;
}

/// Resultado de `_executar`.
enum _Execucao { executada, invalida, aguardando }

/// Registra a venda da meta na barra que disparou o gatilho, ao preço
/// [precoExec] (o preço-alvo, o stop ou a abertura em gap).
_Execucao _executar(
  Repositorio repo,
  Meta meta,
  Barra barra,
  String fonte,
  DataHora agora,
  double precoExec,
  String motivo,
) {
  final rot = gatilho(meta) == 'stop' ? 'Stop' : 'Alvo';
  final vid = 'auto-${meta.id}';
  final meses = repo.carregarMeses();
  final dataIso = barra.dt.data;
  final mes = dataIso.substring(0, 7);
  final elos = cadeia(meses, meta.loteId);
  ElosCadeia? alvo;
  for (final c in elos) {
    if (c.mes == mes) {
      alvo = c;
      break;
    }
  }
  if (elos.isEmpty) {
    _marcar(meta, 'inválida', 'A compra desta meta não existe mais.');
    return _Execucao.invalida;
  }
  if (alvo == null) {
    if (compararTexto(elos.last.mes, mes) < 0) {
      _marcar(
        meta,
        'ativa',
        '$rot atingido em ${fmtData(dataIso)}. Feche o mês anterior para '
            'abrir ${fmtMes(mes)} e registrar a venda.',
      );
      return _Execucao.aguardando;
    }
    _marcar(
      meta,
      'inválida',
      '$rot atingido em ${fmtData(dataIso)}, mas essa compra não estava '
          'aberta nesse mês.',
    );
    return _Execucao.invalida;
  }
  final d = alvo.dados;
  final lote = alvo.lote;
  if (d.fechado) {
    _marcar(
      meta,
      'inválida',
      '$rot atingido em ${fmtData(dataIso)}, mas o mês ${fmtMes(mes)} já foi '
          'fechado. Registre a venda manualmente se ela ocorreu.',
    );
    return _Execucao.invalida;
  }
  if (compararTexto(dataIso, lote.dataCompra) < 0) {
    _marcar(
      meta,
      'inválida',
      'A data do ${rot.toLowerCase()} é anterior à data da compra.',
    );
    return _Execucao.invalida;
  }
  final livre = restante(lote);
  if (livre < meta.qtd) {
    _marcar(
      meta,
      'inválida',
      'Quantidade insuficiente: restam $livre de ${meta.ticker} nessa compra '
          'e a meta vende ${meta.qtd}. Nenhuma venda foi registrada.',
    );
    return _Execucao.invalida;
  }
  lote.vendas.add(
    Venda(id: vid, data: dataIso, qtd: meta.qtd, preco: precoExec),
  );
  repo.salvar(d);
  meta.status = 'executada';
  meta.ultimoErro = null;
  meta.execucao = {
    'venda_id': vid,
    'data': dataIso,
    'hora': barra.dt.horaMinuto,
    'preco_usado': precoExec,
    'origem': fonte,
    'barra_ts': barra.ts,
    'gatilho': gatilho(meta),
    'motivo': motivo,
    'verificado_em': isoBr(agora),
  };
  return _Execucao.executada;
}

/// Outra meta do mesmo grupo OCO (ou nulo).
Meta? _parOco(Config cfg, Meta meta) {
  final oco = meta.oco;
  if (oco == null || oco.isEmpty) return null;
  for (final m in cfg.metas) {
    if (!identical(m, meta) && m.oco == oco) return m;
  }
  return null;
}

/// A parceira de um OCO foi executada: a outra meta é cancelada, sem venda.
void _cancelarPorOco(Meta par, Meta vencedora) {
  final ex = vencedora.execucao ?? const <String, Object?>{};
  final data = ex['data'];
  final quando = data is String && data.isNotEmpty
      ? String.fromCharCodes(fmtData(data).runes.take(5))
      : '?';
  final rot = gatilho(vencedora) == 'stop' ? 'stop' : 'alvo';
  par.status = 'cancelada';
  par.ultimoErro = null;
  par.canceladaPor = vencedora.id;
  par.canceladaDetalhe =
      'Cancelada automaticamente (OCO): $rot executado em $quando';
}

/// Aparelho antigo (12 colunas) reescreve a meta executada sem o "oco" e a
/// parceira ativa, que ainda o tem, não acharia o par e executaria também
/// (venda duplicada). Conservador: uma meta ativa com oco é cancelada como OCO
/// quando uma meta executada de gatilho oposto, da mesma compra e da mesma
/// quantidade, saiu depois da criação dela e o grupo oco dela não tem nenhuma
/// outra meta (é o par que perdeu o campo). Devolve true se cancelou alguma.
bool _cancelarOrfasOco(Repositorio repo, Config cfg) {
  final metas = cfg.metas;
  final executadas = [
    for (final m in metas)
      if (m.status == 'executada' &&
          m.execucao != null &&
          m.execucao!.isNotEmpty)
        m,
  ];
  if (executadas.isEmpty ||
      !metasAtivas(cfg).any((m) => m.oco != null && m.oco!.isNotEmpty)) {
    return false;
  }
  final r = raizes(repo.carregarMeses());
  var mudou = false;
  for (final ex in executadas) {
    final raiz = r[ex.loteId] ?? ex.loteId;
    final dataEx = ex.execucao!['data'];
    final dataExecucao = dataEx is String ? dataEx : '';
    for (final m in metasAtivas(cfg)) {
      final oco = m.oco;
      if (oco == null ||
          oco.isEmpty ||
          gatilho(m) == gatilho(ex) ||
          m.qtd != ex.qtd ||
          (r[m.loteId] ?? m.loteId) != raiz ||
          (ex.oco != null && ex.oco!.isNotEmpty && ex.oco != oco) ||
          compararTexto(_dez(m.criadaEm), dataExecucao) > 0) {
        continue;
      }
      if (metas.any(
        (o) => !identical(o, m) && !identical(o, ex) && o.oco == oco,
      )) {
        continue; // o par de verdade existe: é outro OCO
      }
      _cancelarPorOco(m, ex);
      mudou = true;
    }
  }
  return mudou;
}

/// As duas metas de um OCO têm venda registrada: fica a mais cedo e a outra é
/// desfeita (`resolverOco`), exceto em mês fechado, onde só avisa.
void _resolverVendasDuplicadas(
  Repositorio repo,
  Config cfg,
  RelatorioMetas rel,
) {
  final meses = repo.carregarMeses();
  final avisos = <String>[];
  for (final mes in resolverOco(meses, cfg.metas, avisos: avisos)) {
    repo.salvar(meses[mes]!);
  }
  rel.avisos.addAll(avisos);
}

typedef _Candidata = ({Barra barra, double preco, String motivo});

/// Barra que disparou a meta (com o preço de execução e o motivo) e se o stop
/// móvel subiu.
(_Candidata?, bool) _candidata(
  Meta meta,
  HistoricoIntradiario hist,
  Map<String, Diarias>? diarias,
  DataHora agora,
) {
  var subiu = false;
  if (gatilho(meta) == 'stop') {
    if (meta.movel == true) {
      final dia = hist.diarias ?? diarias?[meta.ticker];
      if (dia != null && dia.barras.isNotEmpty) {
        // o "hoje" do cache pode estar atrasado (consulta de ontem): nunca
        // antes da data do relógio
        final relogio = agora.data;
        final hoje = dia.hoje;
        final cache = hoje != null && hoje.isNotEmpty ? hoje : relogio;
        subiu = atualizarStopMovel(
          meta,
          dia.barras,
          compararTexto(cache, relogio) >= 0 ? cache : relogio,
        );
      }
    }
    final achado = acharBarraStop(
      hist.barras,
      meta.niveis ?? const [],
      _dt(meta.criadaEm),
    );
    if (achado == null) return (null, subiu);
    final (barra, nivel) = achado;
    final (preco, gap) = precoExecucaoStop(barra, nivel);
    var motivo =
        'mínima ${precoTexto(barra.baixa!)} ≤ stop ${precoTexto(nivel)}';
    if (gap) motivo += ' (abertura em gap ${precoTexto(barra.abre!)})';
    return ((barra: barra, preco: preco, motivo: motivo), subiu);
  }
  final alvo = meta.precoAlvo!;
  final barra = acharBarra(hist.barras, alvo, _dt(meta.criadaEm));
  if (barra == null) return (null, subiu);
  return (
    (
      barra: barra,
      preco: alvo,
      motivo: 'máxima ${precoTexto(barra.alta)} ≥ alvo ${precoTexto(alvo)}',
    ),
    subiu,
  );
}

/// Aplica os históricos já baixados às metas ativas (só disco, rápido).
/// [diarias]: `{ticker: barras diárias}` para os stops móveis, quando não
/// vierem dentro de cada histórico.
///
/// Em cada par OCO só uma meta executa: vence a barra mais cedo e, na mesma
/// barra, o stop (conservador); quando uma executa, a outra é cancelada.
RelatorioMetas aplicar(
  Repositorio repo,
  Config cfg,
  Map<String, ResultadoHistorico> historicos, {
  DataHora? agora,
  Map<String, Diarias>? diarias,
}) {
  final instante = agora ?? ambiente.agoraBr();
  final rel = RelatorioMetas();
  if (_cancelarOrfasOco(repo, cfg)) {
    repo.gravarConfig(cfg);
    rel.mudou = true;
  }
  // id da meta -> (meta, barra/preço/motivo, fonte)
  final achadas = <String, (Meta, _Candidata, String)>{};
  for (final meta in metasAtivas(cfg)) {
    // confirma de novo que a meta continua ativa e que a venda ainda não existe
    if (meta.status != 'ativa') continue;
    if (vendaExistente(repo.carregarMeses(), 'auto-${meta.id}') != null) {
      reconciliar(repo, cfg, meta);
      final par = _parOco(cfg, meta);
      if (par != null &&
          (par.status == 'ativa' || par.status == 'executada') &&
          vendaExistente(repo.carregarMeses(), 'auto-${par.id}') != null) {
        if (par.status == 'ativa') reconciliar(repo, cfg, par);
        // as duas vendas existem: fica só a primeira
        _resolverVendasDuplicadas(repo, cfg, rel);
      } else if (par != null && par.status == 'ativa') {
        _cancelarPorOco(par, meta);
      }
      repo.gravarConfig(cfg);
      if (meta.status == 'executada') rel.reconciliadas.add(meta);
      rel.mudou = true;
      continue;
    }
    final par = _parOco(cfg, meta);
    if (par != null && par.status == 'executada') {
      // queda entre a venda e o cancelamento
      _cancelarPorOco(meta, par);
      repo.gravarConfig(cfg);
      rel.mudou = true;
      continue;
    }
    final res = historicos[meta.ticker];
    if (res == null) continue;
    if (res is HistoricoErro) {
      if (_marcar(meta, 'ativa', res.mensagem)) {
        repo.gravarConfig(cfg);
        rel.mudou = true;
      }
      rel.erros.add(meta);
      continue;
    }
    final hist = (res as HistoricoOk).historico;
    final (achado, subiu) = _candidata(meta, hist, diarias, instante);
    if (subiu) {
      repo.gravarConfig(cfg);
      rel.mudou = true;
    }
    if (achado == null) {
      if (_marcar(meta, 'ativa')) {
        repo.gravarConfig(cfg);
        rel.mudou = true;
      }
      continue;
    }
    achadas[meta.id] = (
      meta,
      achado,
      '${hist.fonte} · intervalo ${hist.intervalo}',
    );
  }
  // em cada par OCO que disparou, só vence uma: a barra mais cedo; na mesma
  // barra, o stop
  final perdedoras = <String>{};
  for (final MapEntry(key: mid, value: (meta, cand, _)) in achadas.entries) {
    final par = _parOco(cfg, meta);
    if (par == null || !achadas.containsKey(par.id)) continue;
    final outra = achadas[par.id]!.$2.barra;
    final minha = gatilho(meta) == 'stop' ? 0 : 1;
    final dela = gatilho(par) == 'stop' ? 0 : 1;
    final c = outra.dt.compareTo(cand.barra.dt);
    if (c < 0 || (c == 0 && dela < minha)) perdedoras.add(mid);
  }
  for (final MapEntry(key: mid, value: (meta, cand, fonte))
      in achadas.entries) {
    if (perdedoras.contains(mid) || meta.status != 'ativa') continue;
    final antesStatus = meta.status;
    final antesErro = meta.ultimoErro;
    final resultado = _executar(
      repo,
      meta,
      cand.barra,
      fonte,
      instante,
      cand.preco,
      cand.motivo,
    );
    if (resultado == _Execucao.executada) {
      final par = _parOco(cfg, meta);
      if (par != null && par.status == 'ativa') _cancelarPorOco(par, meta);
    }
    if (resultado != _Execucao.aguardando ||
        antesStatus != meta.status ||
        antesErro != meta.ultimoErro) {
      repo.gravarConfig(cfg);
      rel.mudou = true;
    }
    switch (resultado) {
      case _Execucao.executada:
        rel.executadas.add(meta);
      case _Execucao.invalida:
        rel.invalidas.add(meta);
      case _Execucao.aguardando:
        rel.aguardando.add(meta);
    }
  }
  return rel;
}

var _verificando = false;

/// Há uma verificação rodando (uma por vez no processo). A tela usa isto, com
/// [tentarIniciarVerificacao] e [encerrarVerificacao], para distinguir "em
/// andamento" de "sem metas ativas", que [verificar] devolve igualmente como
/// nulo.
bool get verificacaoEmAndamento => _verificando;

/// Tenta assumir a trava da verificação; false se outra já está rodando.
bool tentarIniciarVerificacao() {
  if (_verificando) return false;
  _verificando = true;
  return true;
}

/// Libera a trava assumida por [tentarIniciarVerificacao].
void encerrarVerificacao() => _verificando = false;

/// Busca o histórico e executa as metas atingidas. Devolve o relatório de
/// [aplicar] ou nulo quando outra verificação já está em andamento ou não há
/// metas ativas. [diarias]: barras diárias para os stops móveis. [releitura]:
/// devolve a config atual do disco; com ela, a config aplicada é a lida depois
/// da busca (que leva segundos), para não desfazer o que o usuário mudou nesse
/// intervalo.
Future<RelatorioMetas?> verificar(
  Repositorio repo,
  Config cfg,
  BuscarHistorico historico, {
  DataHora? agora,
  BuscarDiarias? diarias,
  Config Function()? releitura,
}) async {
  if (!tentarIniciarVerificacao()) return null;
  try {
    final ativas = metasAtivas(cfg);
    if (ativas.isEmpty) return null;
    final historicos = await buscarHistoricos(
      ativas,
      historico,
      diarias: diarias,
    );
    return aplicar(
      repo,
      releitura != null ? releitura() : cfg,
      historicos,
      agora: agora,
    );
  } finally {
    encerrarVerificacao();
  }
}

/// Roda a verificação antes de fechar o mês, para que um alvo já atingido nele
/// seja registrado antes de a meta virar inválida. Bloqueia (não fecha)
/// quando a consulta falhou para alguma meta ativa daquele mês ou quando outra
/// verificação está em andamento.
Future<PreparoFechamento> prepararFechamento(
  Repositorio repo,
  Config cfg,
  String mes,
  BuscarHistorico historico, {
  DataHora? agora,
  BuscarDiarias? diarias,
  Config Function()? releitura,
}) async {
  final meses = repo.carregarMeses();
  final doMes = [
    for (final m in metasAtivas(cfg))
      if (cadeia(meses, m.loteId).any((c) => c.mes == mes)) m,
  ];
  final saida = PreparoFechamento();
  if (doMes.isEmpty) return saida;
  final rel = await verificar(
    repo,
    cfg,
    historico,
    agora: agora,
    diarias: diarias,
    releitura: releitura,
  );
  if (rel == null) {
    saida.bloqueio =
        'Há uma verificação de metas em andamento. Tente fechar o mês em '
        'instantes.';
    return saida;
  }
  final ids = {for (final m in doMes) m.id};
  saida.executadas.addAll(rel.executadas.where((m) => ids.contains(m.id)));
  saida.invalidas.addAll(rel.invalidas.where((m) => ids.contains(m.id)));
  final falhas = [
    for (final m in rel.erros)
      if (ids.contains(m.id) && m.status == 'ativa') m,
  ];
  if (falhas.isNotEmpty) {
    final det = falhas
        .map(
          (m) =>
              '${m.ticker}: ${m.ultimoErro ?? 'erro ao consultar o histórico'}',
        )
        .join('\n');
    saida.bloqueio =
        'Não foi possível confirmar se há metas atingidas neste mês, e fechar '
        'agora poderia invalidá-las. Tente de novo mais tarde.\n\n$det';
  }
  return saida;
}
