// Criação e cancelamento de metas (metas.py:199-353, 463-472).

import '../ambiente.dart';
import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../apuracao.dart';
import '../datas.dart';
import '../erros.dart';
import '../formatacao.dart';
import '../modelos/com_mod.dart';
import '../modelos/config.dart';
import '../modelos/lote.dart';
import '../modelos/mes.dart';
import '../modelos/meta.dart';
import '../repositorio.dart';
import 'cadeia.dart';
import 'preco_alvo.dart';

/// `iso(...)` de metas.py: o instante no fuso de Brasília, sem frações.
String _isoBr(DataHora? agora) =>
    (agora ?? ambiente.agoraBr()).noFuso(fusoBrasilia).iso();

/// `_validar_preco`: arredonda a centavos; recusa não finito, zero e negativo.
double _validarPreco(num valor, String rotulo, {String artigo = 'O'}) {
  final v = arredondar(valor.toDouble(), 2);
  if (!v.isFinite) throw ErroValidacao('$rotulo inválido.');
  if (v <= 0) {
    throw ErroValidacao(
      '$artigo ${rotulo.toLowerCase()} deve ser maior que zero.',
    );
  }
  return v;
}

/// Valida a quantidade e a compra (aberta, com saldo livre) de uma nova meta.
/// [ignorar]: metas que não contam como reservadas (a parceira de um OCO).
/// `int(qtd)` do Python trunca; texto, `inf` e `nan` são inválidos.
({int qtd, String mes, Mes dados, Lote lote}) _validarLote(
  Repositorio repo,
  Config cfg,
  String loteId,
  num qtd,
  Map<String, Mes> meses,
  Set<String> ignorar,
) {
  final double inteira;
  if (qtd is int) {
    inteira = qtd.toDouble();
  } else {
    final q = qtd.toDouble();
    if (!q.isFinite) throw ErroValidacao('Quantidade inválida.');
    inteira = q.truncateToDouble();
  }
  if (inteira <= 0) throw ErroValidacao('Quantidade inválida.');
  ElosCadeia? achado;
  for (final e in meses.entries) {
    for (final l in e.value.lotes) {
      if (l.id == loteId) {
        achado = (mes: e.key, dados: e.value, lote: l);
        break;
      }
    }
    if (achado != null) break;
  }
  if (achado == null) throw ErroValidacao('Essa compra não existe mais.');
  if (achado.dados.fechado) {
    throw ErroValidacao('O mês dessa compra está fechado.');
  }
  final lote = achado.lote;
  final saldo = restante(lote);
  final livre =
      saldo - reservado(repo, cfg, loteId, meses: meses, ignorar: ignorar);
  // um int acima do int64 não existe aqui: a comparação em double basta
  if (qtd is int ? qtd > saldo : inteira > saldo) {
    throw ErroValidacao('Quantidade maior que a disponível ($saldo).');
  }
  if (qtd is int ? qtd > livre : inteira > livre) {
    throw ErroValidacao(
      'Quantidade maior que a livre ($livre): o resto já está em outras metas ativas.',
    );
  }
  return (
    qtd: qtd is int ? qtd : inteira.toInt(),
    mes: achado.mes,
    dados: achado.dados,
    lote: lote,
  );
}

List<Meta> _candidatasOco(
  Config cfg,
  String loteId,
  String gatilhoNovo,
  Map<String, Mes> meses,
) {
  final r = raizes(meses);
  final raiz = r[loteId] ?? loteId;
  final ativas = metasAtivas(cfg);
  final saida = <Meta>[];
  for (final m in ativas) {
    if (gatilho(m) == gatilhoNovo || (r[m.loteId] ?? m.loteId) != raiz) {
      continue;
    }
    final oco = m.oco;
    if (oco != null &&
        oco.isNotEmpty &&
        ativas.any((o) => !identical(o, m) && o.oco == oco)) {
      continue; // já tem par ativo
    }
    saida.add(m);
  }
  return ordenadoPor(saida, (m) => [m.criadaEm, m.id]);
}

/// Meta ativa que pode virar o par OCO de uma nova meta com esse gatilho: da
/// mesma compra (ou de uma cópia dela), com o gatilho oposto e sem outro par
/// ativo. Devolve a mais antiga ou nulo.
Meta? parceiraOco(
  Repositorio repo,
  Config cfg,
  String loteId,
  String gatilhoNovo, {
  Map<String, Mes>? meses,
}) {
  final candidatas = _candidatasOco(
    cfg,
    loteId,
    gatilhoNovo,
    meses ?? repo.carregarMeses(),
  );
  return candidatas.isEmpty ? null : candidatas.first;
}

/// Liga a nova meta à parceira como OCO (as duas recebem o mesmo `oco`).
void _parear(Config cfg, Map<String, Mes> meses, Meta meta, String ocoCom) {
  Meta? par;
  for (final m in cfg.metas) {
    if (m.id == ocoCom) {
      par = m;
      break;
    }
  }
  if (par == null || par.status != 'ativa') {
    throw ErroValidacao('A meta escolhida para o OCO não está mais ativa.');
  }
  final id = par.id;
  if (_candidatasOco(
    cfg,
    meta.loteId,
    gatilho(meta),
    meses,
  ).every((c) => c.id != id)) {
    throw ErroValidacao(
      'Essa meta não pode formar um OCO com a nova: precisa ser da mesma '
      'compra, de gatilho oposto e sem outro par.',
    );
  }
  if (par.qtd != meta.qtd) {
    throw ErroValidacao(
      'O OCO exige a mesma quantidade nas duas metas (${par.qtd} un.).',
    );
  }
  final oco = 'oco-${ambiente.novoId()}';
  meta.oco = oco;
  par.oco = oco;
}

/// Valida e registra uma meta ativa (grava a configuração). [ocoCom]: id de
/// uma meta de stop ativa para ligar as duas (OCO: quando uma executa, a outra
/// é cancelada).
Meta criarMeta(
  Repositorio repo,
  Config cfg,
  String loteId,
  num qtd,
  num precoAlvo, {
  num? lucroDesejado,
  DataHora? agora,
  String? ocoCom,
}) {
  double? lucro;
  if (lucroDesejado != null) {
    lucro = arredondar(lucroDesejado.toDouble(), 2);
    if (!lucro.isFinite) throw ErroValidacao('Lucro desejado inválido.');
  }
  final alvo = _validarPreco(precoAlvo, 'Preço-alvo');
  final meses = repo.carregarMeses();
  final v = _validarLote(
    repo,
    cfg,
    loteId,
    qtd,
    meses,
    ocoCom != null && ocoCom.isNotEmpty ? {ocoCom} : const {},
  );
  final meta = Meta(
    id: 'meta-${ambiente.novoId()}',
    ticker: v.lote.ticker,
    tipo: v.lote.tipo,
    loteId: loteId,
    qtd: v.qtd,
    precoAlvo: alvo,
    criadaEm: _isoBr(agora),
    status: 'ativa',
    lucroDesejado: lucro,
  );
  if (ocoCom != null && ocoCom.isNotEmpty) _parear(cfg, meses, meta, ocoCom);
  cfg.metas.add(meta);
  repo.gravarConfig(cfg);
  return meta;
}

/// Registra um stop ativo: a venda automática acontece quando a mínima de uma
/// barra chega ao stop. Com [movel] o stop só sobe (Chandelier Exit calculado
/// pelo app depois da criação). [precoAtual] (opcional) recusa um stop que já
/// estaria disparado.
Meta criarStop(
  Repositorio repo,
  Config cfg,
  String loteId,
  num qtd,
  num precoStop, {
  bool movel = false,
  String? ocoCom,
  double? precoAtual,
  DataHora? agora,
  Map<String, Object?>? sugestao,
}) {
  final stop = _validarPreco(precoStop, 'Stop');
  if (precoAtual != null && stop >= precoAtual) {
    throw ErroValidacao(
      'O stop deve ficar abaixo do preço atual (${brl(precoAtual)}).',
    );
  }
  final meses = repo.carregarMeses();
  final v = _validarLote(
    repo,
    cfg,
    loteId,
    qtd,
    meses,
    ocoCom != null && ocoCom.isNotEmpty ? {ocoCom} : const {},
  );
  final criada = _isoBr(agora);
  final meta = Meta(
    id: 'meta-${ambiente.novoId()}',
    ticker: v.lote.ticker,
    tipo: v.lote.tipo,
    loteId: loteId,
    qtd: v.qtd,
    gatilho: 'stop',
    stopInicial: stop,
    movel: movel,
    stopAtual: stop,
    niveis: [
      Nivel(
        desde: criada.substring(0, 10),
        stop: stop,
        calcEm: criada.substring(0, 10),
      ),
    ],
    criadaEm: criada,
    status: 'ativa',
    sugestao: sugestao != null && sugestao.isNotEmpty
        ? lerMapa(sugestao)
        : null,
  );
  if (ocoCom != null && ocoCom.isNotEmpty) _parear(cfg, meses, meta, ocoCom);
  cfg.metas.add(meta);
  repo.gravarConfig(cfg);
  return meta;
}

/// Cancela uma meta ativa. Se a venda automática já foi registrada, só
/// reconcilia o status e avisa.
void cancelarMeta(Repositorio repo, Config cfg, String metaId) {
  Meta? meta;
  for (final m in cfg.metas) {
    if (m.id == metaId) {
      meta = m;
      break;
    }
  }
  if (meta == null || meta.status != 'ativa') {
    throw ErroValidacao('Só metas ativas podem ser canceladas.');
  }
  if (vendaExistente(repo.carregarMeses(), 'auto-$metaId') != null) {
    reconciliar(repo, cfg, meta);
    repo.gravarConfig(cfg);
    throw ErroValidacao('Essa meta já foi executada.');
  }
  meta.status = 'cancelada';
  meta.ultimoErro = null;
  repo.gravarConfig(cfg);
}

/// `_reconciliar`: a venda automática já existe, só acerta o status da meta.
void reconciliar(Repositorio repo, Config cfg, Meta meta) {
  meta.status = 'executada';
  meta.ultimoErro = null;
  final execucao = meta.execucao;
  if (execucao == null || execucao.isEmpty) {
    final (_, v) = vendaExistente(repo.carregarMeses(), 'auto-${meta.id}')!;
    meta.execucao = {
      'venda_id': v.id,
      'data': v.data,
      'hora': '',
      'preco_usado': v.preco,
      'origem': 'reconciliada',
      'barra_ts': 0,
      'motivo': 'Venda automática já registrada',
      'verificado_em': _isoBr(null),
    };
  }
}
