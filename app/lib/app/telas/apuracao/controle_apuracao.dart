// Estado da tela de Apuração: o mês exibido, o carregamento sem bloquear a
// interface e o fluxo de Fechar mês (calculadora_darf.py:1733-1770;
// android/main.py:1127-1184).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/dialogos.dart';
import '../../componentes/seletor_mes.dart';
import '../../estado/estado_app.dart';
import '../../plataforma/plataforma.dart';
import '../../regras/filtros.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../formularios/abrir_formulario.dart';

/// O que a seção "Ativos comprados" mostra: a posição no fim do mês
/// escolhido (só leitura) ou os lotes do mês aberto (com as ações de hoje).
enum ModoLista { posicao, carteira }

class ControleApuracao extends ChangeNotifier {
  ControleApuracao(this._servicos, this._estado) {
    _mes = _estado.mes;
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    _estado.addListener(_aoMudarEstado);
    // cotações da carteira a cada 60 s, só com a Apuração à vista e meus
    // dados (calculadora_darf.py:2578-2585)
    _timer = Timer.periodic(intervaloCotacoes, (_) {
      if (_estado.aba == Aba.apuracao && _estado.amigo == null) {
        unawaited(_buscarPrecos());
        unawaited(_buscarCotacoes());
      }
    });
    unawaited(recarregar());
  }

  static const intervaloCotacoes = Duration(seconds: 60);

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late String _mes;
  String? _amigo;
  late int _versao;
  int _geracao = 0;
  bool _descartado = false;
  Timer? _timer;
  int _geracaoPrecos = 0;
  int _geracaoPosicoes = 0;
  int _geracaoCotacoes = 0;
  int _geracaoCarteira = 0;
  ModoLista? _modoEscolhido;
  VisaoMes? _visaoAberto;

  /// O mês na tela; null enquanto o primeiro carregamento (ou o de outro mês
  /// ou visão) não chega, ou quando ele falhou ([erro]).
  VisaoMes? visao;
  bool carregando = false;
  String? erro;

  /// Verifica metas e fecha o mês (os botões ficam desabilitados).
  bool fechando = false;

  /// Lendo e verificando as metas antes de fechar ("Verificando...").
  bool verificando = false;

  /// Texto do cartão de saldo do celular; null até o caixa chegar.
  String? textoSaldo;

  /// Preço atual por ticker em carteira: ausente = ainda não chegou ("…");
  /// nulo = a cotação falhou ("—").
  Map<String, double?> precos = {};

  /// Primeiro mês aberto (o de trabalho); nulo até chegar ou se falhou.
  String? mesAberto;

  /// Posições no fim do mês escolhido; nulo enquanto carrega ([erroPosicoes]
  /// quando falhou).
  VisaoPosicoes? posicoes;
  String? erroPosicoes;

  /// Cotação atual por ticker da posição de hoje: ausente = ainda não
  /// chegou; nulo = a consulta falhou.
  Map<String, CotacaoAtual?> cotacoes = {};

  /// Erro ao ler o mês aberto quando a carteira atual vem de outro mês.
  String? erroCarteira;

  FiltroLotes filtroLotes = FiltroLotes();
  FiltroVendas filtroVendas = FiltroVendas();

  /// Ids da compra e da venda marcadas na tabela (layout expandido).
  String? loteSelecionado;
  String? vendaSelecionada;

  /// Há uma edição ou exclusão em andamento: as outras ações esperam.
  bool gravando = false;

  /// O mês escolhido no estado do app (o seletor muda por lá).
  String get mes => _estado.mes;

  /// Último dia do mês escolhido, ou hoje no mês de hoje.
  String get dataCorte => dataCorteDoMes(mes, ambiente.hoje());

  /// Padrão: a carteira atual no mês aberto, a posição nos demais.
  ModoLista get modoLista =>
      _modoEscolhido ??
      (mesAberto == null || mesAberto == mes
          ? ModoLista.carteira
          : ModoLista.posicao);

  /// Os lotes da lista de compras: os do mês na tela, ou os do mês aberto
  /// quando a carteira atual é pedida de outro mês (nulo enquanto carrega).
  VisaoMes? get visaoLotes {
    final v = visao;
    final aberto = mesAberto;
    if (v == null ||
        modoLista != ModoLista.carteira ||
        aberto == null ||
        v.mes == aberto) {
      return v;
    }
    return _visaoAberto?.mes == aberto ? _visaoAberto : null;
  }

  /// A carteira atual é de outro mês que o da tela, e ainda não chegou.
  bool get carregandoCarteira =>
      visao != null &&
      modoLista == ModoLista.carteira &&
      visaoLotes == null &&
      erroCarteira == null;

  void escolherModo(ModoLista modo) {
    // a escolha vale mesmo igual ao padrão: o padrão muda com o mês aberto
    if (modo == _modoEscolhido) return;
    _modoEscolhido = modo;
    notifyListeners();
    _atualizarModo(recarregarCarteira: true);
  }

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _timer?.cancel();
    _estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    if (_estado.mes == _mes &&
        _estado.amigo == _amigo &&
        _estado.versaoDados == _versao) {
      return;
    }
    if (_estado.mes != _mes || _estado.amigo != _amigo) _modoEscolhido = null;
    _mes = _estado.mes;
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    unawaited(recarregar());
  }

  /// Vale o último pedido: uma resposta antiga é descartada. Não bloqueia a
  /// tela; a visão anterior continua à vista até a nova chegar, exceto quando
  /// o mês ou a visão mudou (aí não há o que mostrar de outro mês).
  Future<void> recarregar() async {
    final geracao = ++_geracao;
    final mes = _estado.mes;
    final amigo = _estado.amigo;
    final atual = visao;
    if (atual != null && (atual.mes != mes || atual.amigo != amigo)) {
      visao = null;
      posicoes = null;
      erroPosicoes = null;
      cotacoes = {};
      _visaoAberto = null;
      erroCarteira = null;
      _geracaoPosicoes++;
      _geracaoCotacoes++;
      _geracaoCarteira++;
      _podarSelecao();
    }
    carregando = true;
    notifyListeners();
    final aberto = _servicos
        .mesInicial(amigo: amigo)
        .then<String?>((m) => m, onError: (_) => null);
    try {
      final nova = await _servicos.carregarMes(mes, amigo: amigo);
      final inicial = await aberto;
      if (geracao != _geracao) return;
      mesAberto = inicial ?? mesAberto;
      _definirVisao(nova);
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      visao = null;
      _podarSelecao();
      erro = e is PedidoSuperado ? null : textoErro(e);
    }
    carregando = false;
    notifyListeners();
    _atualizarModo(recarregarCarteira: true);
    if (amigo == null) unawaited(_carregarSaldo(geracao));
  }

  /// A seleção some quando a compra ou a venda deixa de existir.
  void _definirVisao(VisaoMes nova) {
    visao = nova;
    _podarSelecao();
  }

  /// A seleção só vale para o que está à vista: some se a linha deixou de
  /// existir ou foi escondida pelo filtro (Excluir não age no invisível).
  void _podarSelecao() {
    final v = visao;
    if (v == null) {
      loteSelecionado = vendaSelecionada = null;
      return;
    }
    final lotes = filtrarLotes(
      (visaoLotes ?? v).dados.lotes,
      filtroLotes,
      (t) => precos[t],
    );
    if (!lotes.any((l) => l.id == loteSelecionado)) loteSelecionado = null;
    final ops = filtrarVendas(v.apuracao.ops, filtroVendas);
    if (!ops.any(
      (o) =>
          o.vendaId == vendaSelecionada ||
          grupoDe(o.vendaId) == vendaSelecionada,
    )) {
      vendaSelecionada = null;
    }
  }

  /// Busca o que o modo da lista precisa: as posições e a cotação atual
  /// delas, ou o mês aberto e os preços dos lotes.
  void _atualizarModo({bool recarregarCarteira = false}) {
    if (_descartado || visao == null) return;
    // as posições também alimentam os indicadores do detalhamento
    unawaited(_carregarPosicoes());
    if (modoLista != ModoLista.posicao) {
      if (recarregarCarteira) unawaited(_carregarCarteira());
      unawaited(_buscarPrecos());
    }
  }

  /// Posições no fim do mês na tela (só leitura).
  Future<void> _carregarPosicoes() async {
    final geracao = ++_geracaoPosicoes;
    final amigo = _estado.amigo;
    try {
      final r = await _servicos.posicoes(_estado.mes, amigo: amigo);
      if (geracao != _geracaoPosicoes || _descartado) return;
      posicoes = r;
      erroPosicoes = null;
    } catch (e) {
      if (geracao != _geracaoPosicoes || _descartado || e is PedidoSuperado) {
        return;
      }
      posicoes = null;
      erroPosicoes = textoErro(e);
    }
    notifyListeners();
    unawaited(_buscarCotacoes());
  }

  /// Indicadores por ativo; com o corte de hoje, já com as cotações atuais
  /// que chegaram (a que falhou deixa o mercado e a exposição em "—").
  List<IndicadoresAtivo> get indicadores {
    final p = posicoes;
    if (p == null) return const [];
    if (!p.corrente) return p.indicadores;
    if (!identical(p, _indicadoresDe) ||
        !identical(cotacoes, _indicadoresCotacoes)) {
      _indicadoresDe = p;
      _indicadoresCotacoes = cotacoes;
      _indicadoresCache = comCotacoes(p.indicadores, {
        for (final e in cotacoes.entries) e.key: e.value?.preco,
      });
    }
    return _indicadoresCache;
  }

  VisaoPosicoes? _indicadoresDe;
  Map<String, CotacaoAtual?>? _indicadoresCotacoes;
  List<IndicadoresAtivo> _indicadoresCache = const [];

  /// Tickers cuja cotação atual a lista à vista mostra: os da posição de hoje
  /// ou os da carteira atual; vazio numa posição de mês passado.
  Set<String> get tickersCotacao {
    if (modoLista == ModoLista.posicao) {
      final p = posicoes;
      if (p == null || !p.corrente) return const {};
      return {for (final a in p.posicoes) a.ticker};
    }
    final p = posicoes;
    return {
      for (final l in visaoLotes?.dados.lotes ?? const <Lote>[])
        if (restante(l) > 0) l.ticker,
      // a posição de hoje alimenta os indicadores do detalhamento
      if (p != null && p.corrente)
        for (final a in p.posicoes) a.ticker,
    };
  }

  /// Cotação atual (com fonte e hora) dos ativos à vista. Uma cotação que
  /// falha deixa o ativo sem valor de mercado; a que já chegou fica com a
  /// hora dela.
  Future<void> _buscarCotacoes() async {
    if (visao == null || _descartado) return;
    final tickers = tickersCotacao;
    if (tickers.isEmpty) return;
    final geracao = ++_geracaoCotacoes;
    var r = <String, CotacaoAtual?>{};
    try {
      r = await _servicos.cotacoesAtuais(tickers);
    } catch (e) {
      if (e is PedidoSuperado) return;
    }
    if (geracao != _geracaoCotacoes || _descartado) return;
    cotacoes = {...cotacoes, for (final t in tickers) t: r[t] ?? cotacoes[t]};
    notifyListeners();
  }

  /// Lotes do mês aberto quando a carteira atual é pedida de outro mês.
  Future<void> _carregarCarteira() async {
    final aberto = mesAberto;
    final v = visao;
    if (aberto == null || v == null || v.mes == aberto) return;
    final geracao = ++_geracaoCarteira;
    try {
      final r = await _servicos.carregarMes(aberto, amigo: _estado.amigo);
      if (geracao != _geracaoCarteira || _descartado) return;
      _visaoAberto = r;
      erroCarteira = null;
    } catch (e) {
      if (geracao != _geracaoCarteira || _descartado || e is PedidoSuperado) {
        return;
      }
      _visaoAberto = null;
      erroCarteira = textoErro(e);
    }
    _podarSelecao();
    notifyListeners();
    unawaited(_buscarPrecos());
  }

  /// Cotações das compras em aberto, sem bloquear a tela: cada ticker mostra
  /// "…" até a resposta chegar. Se a busca falha, o que faltava vira "—".
  Future<void> _buscarPrecos() async {
    final atual = visaoLotes;
    if (atual == null ||
        atual.erroLeitura != null ||
        modoLista != ModoLista.carteira ||
        _descartado) {
      return;
    }
    final tickers = {
      for (final l in atual.dados.lotes)
        if (restante(l) > 0) l.ticker,
    };
    if (tickers.isEmpty) return;
    final geracao = ++_geracaoPrecos;
    try {
      final r = await _servicos.precosCarteira(tickers);
      if (geracao != _geracaoPrecos || _descartado) return;
      precos = {...precos, ...r};
    } catch (e) {
      if (geracao != _geracaoPrecos || _descartado || e is PedidoSuperado) {
        return;
      }
      precos = {
        ...precos,
        for (final t in tickers)
          if (!precos.containsKey(t)) t: null,
      };
    }
    notifyListeners();
    unawaited(_buscarCotacoes());
  }

  Future<void> _carregarSaldo(int geracao) async {
    try {
      final r = (await _servicos.caixa()).resumo;
      if (geracao != _geracao) return;
      textoSaldo = r.definido
          ? 'Saldo disponível ${brl(r.disponivel)} · '
                'projetado ${brl(r.projetado)}'
          : 'Definir saldo em conta';
      notifyListeners();
    } catch (_) {
      // sem o caixa o cartão mostra o texto de definir o saldo
    }
  }

  /// "Atualizar" (visão de amigo): baixa os dados dele de novo.
  Future<void> atualizarAmigo() async {
    final amigo = _estado.amigo;
    if (amigo == null) return;
    // baixa de novo; versaoDados não muda, então a tela recarrega aqui
    await _estado.trocarVisao(amigo);
    if (_estado.amigo == amigo) await recarregar();
  }

  /// Grade de meses; os com dados vêm marcados (py:2989-2990).
  Future<void> escolher(BuildContext c) async {
    Set<String> comDados;
    try {
      comDados = (await _servicos.mesesComDados(amigo: _estado.amigo)).toSet();
    } catch (_) {
      comDados = {};
    }
    if (!c.mounted) return;
    final novo = await escolherMes(
      c,
      atual: _estado.mes,
      comDados: comDados,
      maximo: ambiente.hoje().substring(0, 7),
    );
    if (novo != null) _estado.trocarMes(novo);
  }

  /// Nova compra; numa compra nova pergunta se a venda já aconteceu
  /// (android/main.py:1304). Com [ticker] (menu do botão direito), o
  /// formulário já vem com ele e com o preço atual, como no Radar.
  Future<void> novaCompra(BuildContext c, {String? ticker}) =>
      _unica(() => _novaCompra(c, ticker));

  Future<void> _novaCompra(BuildContext c, String? ticker) async {
    final atual = visaoLotes;
    if (atual == null || !atual.editavel) return;
    final antes = {for (final l in atual.dados.lotes) l.id};
    final preco = ticker == null
        ? null
        : (precos[ticker] ?? cotacoes[ticker]?.preco);
    final nova = await abrirFormCompra(
      c,
      atual,
      iniciais: ticker == null
          ? null
          : {
              'ticker': ticker,
              if (preco != null && preco > 0) 'preco': precoTexto(preco),
            },
    );
    if (nova == null) return;
    _aceitar(nova);
    final lote = nova.dados.lotes.where((l) => !antes.contains(l.id));
    if (lote.isEmpty || !c.mounted) return;
    final novoLote = lote.first;
    final vendeu = await confirmar(
      c,
      'Venda',
      'Você já fez a venda de ${novoLote.ticker}?',
      sim: 'Sim, registrar venda',
      nao: 'Ainda não',
    );
    if (!vendeu || !c.mounted) return;
    final r = await abrirFormVenda(
      c,
      nova,
      lote: novoLote,
      fecharMesAberto: _fecharPeloFormulario,
    );
    if (r != null) _aceitar(r.visao);
  }

  /// A visão que um formulário devolveu vale se ainda é a do mês aberto.
  void _aceitar(VisaoMes nova) {
    if (_estado.amigo != null) return;
    if (nova.mes == _estado.mes) {
      _definirVisao(nova);
    } else if (nova.mes == mesAberto && _visaoAberto != null) {
      _visaoAberto = nova;
      _podarSelecao();
    } else {
      return;
    }
    notifyListeners();
    _atualizarModo();
  }

  // --- filtros e seleção das listas

  void definirFiltroLotes(FiltroLotes f) {
    filtroLotes = f;
    _podarSelecao();
    notifyListeners();
  }

  void definirFiltroVendas(FiltroVendas f) {
    filtroVendas = f;
    _podarSelecao();
    notifyListeners();
  }

  void selecionarLote(String? id) {
    loteSelecionado = id;
    notifyListeners();
  }

  void selecionarVenda(String? id) {
    vendaSelecionada = id;
    notifyListeners();
  }

  Lote? _lote(String? id) {
    for (final l in visaoLotes?.dados.lotes ?? const <Lote>[]) {
      if (l.id == id) return l;
    }
    return null;
  }

  (Lote, Venda)? _venda(String? id) {
    for (final l in visao?.dados.lotes ?? const <Lote>[]) {
      for (final v in l.vendas) {
        if (v.id == id) return (l, v);
      }
    }
    // id de grupo (linha agrupada da lista): a primeira venda do grupo
    for (final l in visao?.dados.lotes ?? const <Lote>[]) {
      for (final v in l.vendas) {
        if (grupoDe(v.id) == id) return (l, v);
      }
    }
    return null;
  }

  // --- ações das listas (calculadora_darf.py:1613-1732)

  /// Uma ação de gravação por vez (edição, venda, exclusão).
  Future<void> _unica(Future<void> Function() acao) async {
    if (gravando) return;
    gravando = true;
    notifyListeners();
    try {
      await acao();
    } finally {
      gravando = false;
      notifyListeners();
    }
  }

  /// Registrar venda; sem [lote] nem [ticker] usa a compra marcada, se ainda
  /// tiver saldo. Os avisos (sem compra em aberto, venda retroativa) são do
  /// formulário.
  Future<void> registrarVenda(BuildContext c, {Lote? lote, String? ticker}) =>
      _unica(() => _registrarVenda(c, lote: lote, ticker: ticker));

  Future<void> _registrarVenda(
    BuildContext c, {
    Lote? lote,
    String? ticker,
  }) async {
    final atual = visaoLotes;
    if (atual == null || !atual.editavel) return;
    var alvo = lote ?? (ticker == null ? _lote(loteSelecionado) : null);
    if (alvo != null && restante(alvo) == 0) alvo = null;
    final r = await abrirFormVenda(
      c,
      atual,
      lote: alvo,
      ticker: ticker ?? '',
      fecharMesAberto: _fecharPeloFormulario,
    );
    if (r != null) _aceitar(r.visao);
  }

  Future<void> editarLote(BuildContext c, {String? id}) =>
      _unica(() => _editarLote(c, id: id));

  Future<void> _editarLote(BuildContext c, {String? id}) async {
    final atual = visaoLotes;
    if (atual == null || !atual.editavel) return;
    final lote = _lote(id ?? loteSelecionado);
    if (lote == null) {
      await avisar(
        c,
        'Editar',
        'Selecione uma compra na tabela de ativos comprados.',
      );
      return;
    }
    final nova = await abrirFormCompra(c, atual, editar: lote);
    if (nova != null) _aceitar(nova);
  }

  Future<void> editarVenda(BuildContext c, {String? id}) =>
      _unica(() => _editarVenda(c, id: id));

  Future<void> _editarVenda(BuildContext c, {String? id}) async {
    final atual = visao;
    if (atual == null || !atual.editavel) return;
    final par = _venda(id ?? vendaSelecionada);
    if (par == null) {
      await avisar(c, 'Editar', 'Selecione uma venda na tabela de vendas.');
      return;
    }
    final r = await abrirFormVenda(c, atual, editar: par);
    if (r != null) _aceitar(r.visao);
  }

  Future<void> excluirLote(BuildContext c, {String? id}) =>
      _unica(() => _excluirLote(c, id: id));

  Future<void> _excluirLote(BuildContext c, {String? id}) async {
    final atual = visaoLotes;
    if (atual == null || !atual.editavel) return;
    final lote = _lote(id ?? loteSelecionado);
    if (lote == null) {
      await avisar(
        c,
        'Excluir',
        'Selecione um ativo na tabela de ativos comprados.',
      );
      return;
    }
    final sim = await confirmar(
      c,
      c.read<Plataforma>().windows ? 'Excluir ativo' : 'Excluir compra',
      'Excluir ${lote.ticker}'
      '${lote.vendas.isNotEmpty ? ' e todas as vendas dele?' : '?'}',
      sim: 'Excluir',
      perigo: true,
    );
    if (!sim || !c.mounted) return;
    await _excluir(
      c,
      _estado.mes,
      () => _servicos.excluirCompra(atual.mes, lote.id),
    );
  }

  Future<void> excluirVenda(BuildContext c, {String? id}) =>
      _unica(() => _excluirVenda(c, id: id));

  Future<void> _excluirVenda(BuildContext c, {String? id}) async {
    final atual = visao;
    if (atual == null || !atual.editavel) return;
    final par = _venda(id ?? vendaSelecionada);
    if (par == null) {
      await avisar(c, 'Excluir', 'Selecione uma venda na tabela de vendas.');
      return;
    }
    final sim = await confirmar(
      c,
      'Excluir venda',
      'Excluir esta venda?',
      sim: 'Excluir',
      perigo: true,
    );
    if (!sim || !c.mounted) return;
    await _excluir(
      c,
      atual.mes,
      () => _servicos.excluirVenda(atual.mes, par.$2.id),
    );
  }

  Future<void> _excluir(
    BuildContext c,
    String mes,
    Future<VisaoMes> Function() acao,
  ) async {
    try {
      _aceitar(await acao());
    } catch (e) {
      if (e is PedidoSuperado || _mudou(mes) || !c.mounted) return;
      await avisar(c, 'Não foi possível excluir', textoErro(e));
    }
  }

  // --- radar (menu do botão direito)

  /// Tickers do meu radar; null se a leitura falhou ou na visão de amigo.
  Future<VisaoRadar?> meuRadar() async {
    if (_estado.amigo != null) return null;
    try {
      return await _servicos.radar();
    } catch (_) {
      return null;
    }
  }

  /// Põe [ticker] no meu radar, como o campo de adicionar do Radar.
  Future<void> adicionarRadar(BuildContext c, String ticker) async {
    if (_estado.amigo != null) return;
    try {
      await _servicos.adicionarRadar(ticker);
    } catch (e) {
      if (e is! PedidoSuperado && c.mounted) {
        await avisar(c, 'Radar', textoErro(e));
      }
      return;
    }
    _estado.radarMudou(buscar: true);
    if (c.mounted) {
      ScaffoldMessenger.maybeOf(
        c,
      )?.showSnackBar(SnackBar(content: Text('$ticker adicionado ao Radar.')));
    }
  }

  /// O botão "Fechar mês" da tela está disponível.
  bool get podeFechar {
    final v = visao;
    return v != null && v.editavel && !carregando && !fechando;
  }

  /// Antes de fechar, verifica as metas do mês: uma meta já atingida é
  /// registrada e uma consulta que falhou bloqueia o fechamento. Saldo
  /// inconsistente no custo médio bloqueia antes de tudo (o serviço também
  /// recusa).
  Future<void> fecharMes(BuildContext c) async {
    final atual = visao;
    if (atual == null) return;
    await _fecharMesDe(c, atual);
  }

  /// O botão "Fechar mês" do formulário de venda, quando o mês aberto já
  /// terminou: o mesmo fluxo do [fecharMes], sobre a visão [atual] do
  /// formulário (o mês aberto, mesmo com outro mês na tela). Devolve a visão do
  /// novo mês aberto, ou nulo se cancelou, foi bloqueado ou falhou.
  Future<VisaoMes?> _fecharPeloFormulario(
    BuildContext c,
    VisaoMes atual,
  ) async {
    _metasVenderam = false;
    final fechou = await _fecharMesDe(c, atual);
    final String mes;
    if (fechou) {
      // se o mês inicial falhou depois de fechar, segue para o mês seguinte
      final aberto = mesAberto;
      mes = aberto == null || aberto == atual.mes
          ? proximoMes(atual.mes)
          : aberto;
    } else if (_metasVenderam) {
      // as metas venderam antes da confirmação: a visão do formulário envelheceu
      mes = atual.mes;
    } else {
      return null;
    }
    try {
      return await _servicos.carregarMes(mes);
    } catch (e) {
      if (c.mounted) {
        await avisar(c, 'Não foi possível carregar', textoErro(e));
        // o formulário ficaria num mês já fechado
        if (fechou && c.mounted) Navigator.of(c).pop();
      }
      return null;
    }
  }

  /// Fecha o mês de [atual]; verdadeiro quando o mês foi fechado.
  Future<bool> _fecharMesDe(BuildContext c, VisaoMes atual) async {
    if (!atual.editavel || fechando) return false;
    final inconsistentes = atual.apuracao.inconsistentes;
    if (inconsistentes.isNotEmpty) {
      await avisar(
        c,
        'Não foi possível fechar o mês',
        bloqueioSaldoInconsistente(inconsistentes),
      );
      return false;
    }
    final mes = atual.mes;
    // o fluxo para se o usuário trocar o mês da tela no meio
    final tela = _estado.mes;
    fechando = true;
    notifyListeners();
    try {
      return await _fechar(c, mes, tela);
    } finally {
      fechando = false;
      notifyListeners();
    }
  }

  /// Verdadeiro quando a verificação das metas registrou vendas no último
  /// [_fechar].
  bool _metasVenderam = false;

  bool _mudou(String mes) => _descartado || _estado.mes != mes;

  /// Preço a que a meta vendeu (`execucao.preco_usado`), se registrado.
  String _aPreco(Meta m) {
    final p = m.execucao?['preco_usado'];
    return p is num ? ' a ${brl(p.toDouble())}' : '';
  }

  Future<bool> _fechar(BuildContext c, String mes, String tela) async {
    // As metas são lidas na hora (como o Python lê a config), não do valor
    // em cache do estado, que outro aparelho pode ter deixado velho.
    PreparoFechamento? preparo;
    Object? falha;
    verificando = true;
    notifyListeners();
    try {
      final ativas = (await _servicos.metas()).ativas;
      if (ativas > 0) preparo = await _servicos.prepararFechamento(mes);
    } catch (e) {
      falha = e;
    } finally {
      verificando = false;
      notifyListeners();
    }
    if (!c.mounted || _mudou(tela)) return false;
    if (falha != null) {
      await avisar(
        c,
        'Não foi possível fechar o mês',
        'Falha ao verificar as metas antes de fechar: '
            '${String.fromCharCodes(textoErro(falha).runes.take(120))}',
      );
      return false;
    }
    if (preparo != null) {
      final bloqueio = preparo.bloqueio;
      if (bloqueio != null && bloqueio.isNotEmpty) {
        await avisar(c, 'Não foi possível fechar o mês', bloqueio);
        return false;
      }
      if (preparo.executadas.isNotEmpty) _metasVenderam = true;
      if (preparo.executadas.isNotEmpty || preparo.invalidas.isNotEmpty) {
        await recarregar();
        if (!c.mounted || _mudou(tela)) return false;
        final erroCarga = erro;
        if (visao == null && erroCarga != null) {
          await avisar(c, 'Não foi possível carregar', erroCarga);
          return false;
        }
        final linhas = [
          for (final m in preparo.executadas)
            '${m.ticker}: venda de ${m.qtd} registrada pela meta${_aPreco(m)}.',
          for (final m in preparo.invalidas)
            '${m.ticker}: meta inválida. ${m.ultimoErro ?? ''}',
        ];
        await avisar(c, 'Metas verificadas antes de fechar', linhas.join('\n'));
        if (!c.mounted || _mudou(tela)) return false;
      }
    }
    return _confirmar(c, mes, tela);
  }

  Future<bool> _confirmar(BuildContext c, String mes, String tela) async {
    final VisaoMes? atual;
    if (visao?.mes == mes) {
      atual = visao;
    } else {
      // mês aberto com outro mês na tela (venda): o total vem do disco, já
      // com o que as metas verificadas acabaram de gravar
      try {
        atual = await _servicos.carregarMes(mes);
      } catch (e) {
        if (c.mounted) {
          await avisar(c, 'Não foi possível fechar o mês', textoErro(e));
        }
        return false;
      }
      if (!c.mounted || _mudou(tela)) return false;
    }
    if (atual == null || atual.mes != mes || !atual.editavel) return false;
    final sim = await confirmar(
      c,
      'Fechar ${fmtMes(mes)}',
      'Depois de fechado, o mês não pode ser alterado.\n\n'
          'Total da DARF: ${brl(atual.apuracao.darf)}',
      sim: 'Fechar mês',
    );
    if (!sim || !c.mounted || _mudou(tela)) return false;
    final Fechamento fechamento;
    try {
      fechamento = await _servicos.fecharMes(mes);
    } catch (e) {
      if (c.mounted) {
        await avisar(c, 'Não foi possível fechar o mês', textoErro(e));
      }
      return false;
    }
    // o mês de trabalho mudou: a lista de compras acompanha o novo
    try {
      mesAberto = await _servicos.mesInicial(amigo: _estado.amigo);
      _visaoAberto = null;
    } catch (_) {
      // fica o último conhecido
    }
    _aceitar(fechamento.visao);
    _atualizarModo(recarregarCarteira: true);
    if (c.mounted) await avisar(c, 'Mês fechado', fechamento.mensagem);
    return true;
  }
}
