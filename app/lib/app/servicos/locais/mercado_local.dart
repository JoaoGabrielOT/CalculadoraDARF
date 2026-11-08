// Mercado, radar e metas sobre o repositório local. Cada mutação relê o
// disco pela guarda `lerConfigParaGravar` e é síncrona do começo ao fim (sem
// `await` entre ler e gravar); as consultas ao Yahoo ficam fora dela.

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../../nucleo/nucleo.dart' as nc;
import '../api.dart';
import '../eventos.dart';
import 'apuracao_local.dart' show AmigoCarregado;
import 'config_segura.dart';

final _tickerValido = RegExp(r'^[A-Z0-9]{4,7}$');

bool _erroDeLeitura(Object e) =>
    e is FormatException ||
    e is TypeError ||
    e is RangeError ||
    e is ErroNucleo;

/// Texto da falha: erros de validação (config ilegível) pelo próprio texto,
/// os de rede e mercado pelo `mensagemErro` do núcleo.
String _mensagemFalha(Object e) =>
    e is ErroValidacao ? e.mensagem : mensagemErro(e);

class MercadoLocal {
  MercadoLocal({
    required this.repo,
    required this.yahoo,
    required this.agendarSync,
    required this.emitir,
    this.amigo,
  }) : _cotacoes = CacheCotacoes(yahoo.cotacao);

  final Repositorio repo;
  final ServicoYahoo yahoo;
  final void Function() agendarSync;
  final void Function(EventoServico) emitir;

  /// Amigo carregado pela conta; nulo quando não há.
  final AmigoCarregado? Function()? amigo;

  final CacheCotacoes _cotacoes;

  void _gravou() {
    agendarSync();
    emitir(const EventoDadosMudaram());
  }

  DadosPlanilha _dadosAmigo(String email) {
    final a = amigo?.call();
    if (a == null || a.email != email) {
      throw ErroValidacao('Os dados de $email não estão carregados.');
    }
    return a.dados;
  }

  Lote _acharLote(String loteId) {
    for (final mes in repo.carregarMeses().values) {
      for (final l in mes.lotes) {
        if (l.id == loteId) return l;
      }
    }
    throw ErroValidacao('Essa compra não existe mais.');
  }

  // --- radar

  /// Tickers com compra em aberto; um mês ilegível não derruba o radar.
  Set<String> _custodia() {
    try {
      return custodiaAtual(repo);
    } catch (e) {
      if (_erroDeLeitura(e)) return {};
      rethrow;
    }
  }

  Future<VisaoRadar> radar({String? amigo}) async {
    final meus = {for (final r in lerConfigParaGravar(repo).radar) r.ticker};
    if (amigo != null) {
      return VisaoRadar(
        itens: nc.ordenarRadar(_dadosAmigo(amigo).radar),
        custodia: {},
        meus: meus,
        amigo: amigo,
      );
    }
    return VisaoRadar(
      itens: nc.ordenarRadar(lerConfigParaGravar(repo).radar),
      custodia: _custodia(),
      meus: meus,
    );
  }

  Future<ItemRadar> adicionarRadar(String ticker) async {
    var t = ticker.trim().toUpperCase();
    if (t.endsWith('.SA')) t = t.substring(0, t.length - 3);
    if (!_tickerValido.hasMatch(t)) throw ErroValidacao('Ticker inválido.');
    final cfg = lerConfigParaGravar(repo);
    final item = nc.adicionarRadar(cfg, t);
    if (item == null) throw ErroValidacao('$t já está no radar.');
    repo.gravarConfig(cfg);
    _gravou();
    return item;
  }

  Future<int> importarRadar(List<ItemRadar> itens) async {
    final cfg = lerConfigParaGravar(repo);
    var novos = 0;
    for (final i in itens) {
      if (nc.adicionarRadar(cfg, i.ticker, nome: i.nome) != null) novos++;
    }
    if (novos > 0) {
      repo.gravarConfig(cfg);
      _gravou();
    }
    return novos;
  }

  Future<void> removerRadar(String ticker) async {
    final cfg = lerConfigParaGravar(repo);
    final antes = cfg.radar.length;
    cfg.radar = [
      for (final r in cfg.radar)
        if (r.ticker != ticker) r,
    ];
    if (cfg.radar.length == antes) return;
    repo.gravarConfig(cfg);
    _gravou();
  }

  Future<void> reordenarRadar(List<String> tickers) async {
    final cfg = lerConfigParaGravar(repo);
    nc.reordenarRadar(cfg, tickers);
    repo.gravarConfig(cfg);
    _gravou();
  }

  // --- cotações

  Future<void> limparCacheCotacoes() async => yahoo.limpar();

  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) async {
    final DadosAtivo dados;
    try {
      dados = await yahoo.dados(ticker, nomeConhecido: nome);
    } catch (e) {
      return CotacaoErro(ticker, mensagemErro(e));
    }
    _preencherNome(dados);
    return CotacaoOk(dados);
  }

  /// Item do radar sem nome recebe o que o Yahoo devolveu (calculadora_darf.py:
  /// 2554-2560). Com a config ilegível nada é gravado.
  void _preencherNome(DadosAtivo d) {
    if (d.nome.isEmpty) return;
    final Config cfg;
    try {
      cfg = lerConfigParaGravar(repo);
    } on ErroValidacao {
      return;
    }
    for (final r in cfg.radar) {
      if (r.ticker == d.ticker && r.nome.isEmpty) {
        r.nome = d.nome;
        repo.gravarConfig(cfg);
        _gravou();
        return;
      }
    }
  }

  Future<Grafico> grafico(String ticker, String periodo) =>
      yahoo.grafico(ticker, periodo);

  Future<(double, String)> precoVenda(String ticker, String dia) =>
      yahoo.precoVenda(ticker, dia);

  /// Último preço conhecido: nulo = tentou e falhou; ausente = nunca tentou
  /// (a atualização ainda está em curso).
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) async {
    await _cotacoes.atualizar(tickers);
    return {
      for (final t in tickers)
        if (_cotacoes.tentou(t)) t: _cotacoes.preco(t),
    };
  }

  /// Último preço de cada ticker, com fonte e a hora da consulta que o
  /// trouxe; nulo = nunca veio preço. Passa pelo mesmo cache de
  /// [precosCarteira] (60 s; o preço anterior fica se a consulta falha, como
  /// num 429).
  Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers) async {
    await _cotacoes.atualizar(tickers);
    // outra atualização em curso (a dos preços da carteira): espera
    for (var i = 0; i < 200 && _cotacoes.rodando; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (_cotacoes.pendentes(tickers).isNotEmpty) {
      await _cotacoes.atualizar(tickers);
    }
    return {
      for (final t in tickers)
        t: switch ((_cotacoes.preco(t), _cotacoes.hora(t))) {
          (final p?, final h?) when p > 0 => CotacaoAtual(
            preco: p,
            hora: DataHora.deTimestamp(h, fusoBrasilia),
            fonte: 'Yahoo',
          ),
          _ => null,
        },
    };
  }

  // --- metas

  Future<VisaoMetas> metas() async {
    final cfg = lerConfigParaGravar(repo);
    final metas = ordenadoPor(cfg.metas, (m) => [m.criadaEm], reverso: true);
    return VisaoMetas(
      metas: metas,
      descricoes: {for (final m in metas) m.id: nc.descricao(m, todas: metas)},
      lotes: lotesParaMeta(repo, cfg),
      ativas: metasAtivas(cfg).length,
    );
  }

  Future<VisaoSugestoes> sugestoesMetas() async {
    final cfg = lerConfigParaGravar(repo);
    final posicoes = posicoesAbertas(repo, cfg);
    if (posicoes.isEmpty) return const VisaoSugestoes(itens: [], rodape: []);
    final tickers = ordenadoPor({
      for (final p in posicoes) p.lote.ticker,
    }, (t) => [t]);
    final resultados = <String, Object>{};
    for (final t in tickers) {
      try {
        resultados[t] = await yahoo.barrasDiarias(t);
      } catch (e) {
        resultados[t] = e is Exception ? e : mensagemErro(e);
      }
    }
    final cotacoes = {
      for (final MapEntry(key: t, value: r) in resultados.entries)
        if (r is Diarias && r.preco != null) t: r.preco!,
    };
    final (pat, resultado) = resumoPatrimonio(repo, cfg, cotacoes);
    return VisaoSugestoes(
      itens: [
        for (final p in posicoes)
          () {
            final qtd = p.livre > 0 ? p.livre : p.restante;
            return SugestaoPosicao(
              posicao: p,
              qtd: qtd,
              item: montarItem(
                p.lote,
                qtd,
                resultados[p.lote.ticker]!,
                valorPatrimonio: pat.valor,
              ),
            );
          }(),
      ],
      rodape: linhasRodape(pat, resultado),
    );
  }

  Future<PrecoAlvo> calcularPrecoAlvo(
    String loteId,
    int qtd,
    double lucro,
  ) async {
    final lote = _acharLote(loteId);
    // compra de hoje: a venda é day trade (py:3614; android/main.py:2505)
    return nc.calcularPrecoAlvo(
      lote,
      qtd,
      lucro,
      dayTrade: lote.dataCompra == ambiente.hoje(),
    );
  }

  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) async {
    final lote = _acharLote(loteId);
    return nc.projetar(
      lote,
      qtd,
      preco,
      dayTrade: lote.dataCompra == ambiente.hoje(),
    );
  }

  Future<Meta?> parceiraOco(String loteId, String gatilho) async =>
      nc.parceiraOco(repo, lerConfigParaGravar(repo), loteId, gatilho);

  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) async {
    final cfg = lerConfigParaGravar(repo);
    final meta = nc.criarMeta(
      repo,
      cfg,
      loteId,
      qtd,
      precoAlvo,
      lucroDesejado: lucroDesejado,
      ocoCom: ocoCom,
    );
    _gravou();
    return meta;
  }

  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) async {
    final cfg = lerConfigParaGravar(repo);
    final meta = nc.criarStop(
      repo,
      cfg,
      loteId,
      qtd,
      precoStop,
      movel: movel,
      ocoCom: ocoCom,
      precoAtual: precoAtual,
      sugestao: sugestao,
    );
    _gravou();
    return meta;
  }

  Future<void> cancelarMeta(String metaId) async {
    final cfg = lerConfigParaGravar(repo);
    try {
      nc.cancelarMeta(repo, cfg, metaId);
    } on ErroValidacao catch (e) {
      // o núcleo já reconciliou e gravou antes de avisar
      if (e.mensagem == 'Essa meta já foi executada.') _gravou();
      rethrow;
    }
    _gravou();
  }

  /// Busca o histórico e aplica as metas atingidas. Uma falha nunca vira
  /// "em andamento": a trava é liberada e o resultado é [VerificacaoFalhou].
  Future<ResultadoVerificacao> verificarMetas() async {
    if (!tentarIniciarVerificacao()) return const VerificacaoEmAndamento();
    try {
      final ativas = metasAtivas(lerConfigParaGravar(repo));
      if (ativas.isEmpty) return const SemMetasAtivas();
      final historicos = await buscarHistoricos(
        ativas,
        yahoo.historico,
        diarias: yahoo.diarias,
      );
      // a busca leva segundos: aplica sobre a config de agora
      final rel = aplicar(repo, lerConfigParaGravar(repo), historicos);
      if (rel.mudou) _gravou();
      return VerificacaoConcluida(rel);
    } catch (e) {
      return VerificacaoFalhou(_mensagemFalha(e));
    } finally {
      encerrarVerificacao();
    }
  }

  /// Verificação do timer: avisa a interface quando algo mudou.
  Future<void> verificacaoAutomatica() async {
    final r = await verificarMetas();
    if (r is VerificacaoConcluida && r.relatorio.mudou) {
      emitir(EventoMetas(r.relatorio));
    }
  }

  Future<PreparoFechamento> prepararFechamento(String mes) async {
    final cfg = lerConfigParaGravar(repo);
    final antes = jsonPython(cfg.toJson());
    final preparo = await nc.prepararFechamento(
      repo,
      cfg,
      mes,
      yahoo.historico,
      diarias: yahoo.diarias,
      releitura: () => lerConfigParaGravar(repo),
    );
    if (jsonPython(lerConfigParaGravar(repo).toJson()) != antes) _gravou();
    return preparo;
  }
}
