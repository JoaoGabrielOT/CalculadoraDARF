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

  FiltroLotes filtroLotes = FiltroLotes();
  FiltroVendas filtroVendas = FiltroVendas();

  /// Ids da compra e da venda marcadas na tabela (layout expandido).
  String? loteSelecionado;
  String? vendaSelecionada;

  /// Há uma edição ou exclusão em andamento: as outras ações esperam.
  bool gravando = false;

  /// O mês escolhido no estado do app (o seletor muda por lá).
  String get mes => _estado.mes;

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
      _podarSelecao();
    }
    carregando = true;
    notifyListeners();
    try {
      final nova = await _servicos.carregarMes(mes, amigo: amigo);
      if (geracao != _geracao) return;
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
    unawaited(_buscarPrecos());
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
    final lotes = filtrarLotes(v.dados.lotes, filtroLotes, (t) => precos[t]);
    if (!lotes.any((l) => l.id == loteSelecionado)) loteSelecionado = null;
    final ops = filtrarVendas(v.apuracao.ops, filtroVendas);
    if (!ops.any((o) => o.vendaId == vendaSelecionada)) vendaSelecionada = null;
  }

  /// Cotações das compras em aberto, sem bloquear a tela: cada ticker mostra
  /// "…" até a resposta chegar. Se a busca falha, o que faltava vira "—".
  Future<void> _buscarPrecos() async {
    final atual = visao;
    if (atual == null || atual.erroLeitura != null || _descartado) return;
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
  /// (android/main.py:1304).
  Future<void> novaCompra(BuildContext c) => _unica(() => _novaCompra(c));

  Future<void> _novaCompra(BuildContext c) async {
    final atual = visao;
    if (atual == null || !atual.editavel) return;
    final antes = {for (final l in atual.dados.lotes) l.id};
    final nova = await abrirFormCompra(c, atual);
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
    final r = await abrirFormVenda(c, nova, lote: novoLote);
    if (r != null) _aceitar(r.visao);
  }

  /// A visão que um formulário devolveu vale se ainda é a do mês aberto.
  void _aceitar(VisaoMes nova) {
    if (nova.mes != _estado.mes || _estado.amigo != null) return;
    _definirVisao(nova);
    notifyListeners();
    unawaited(_buscarPrecos());
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
    for (final l in visao?.dados.lotes ?? const <Lote>[]) {
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

  /// Registrar venda; sem [lote] usa a compra marcada, se ainda tiver saldo.
  /// Os avisos (sem compra em aberto, venda retroativa) são do formulário.
  Future<void> registrarVenda(BuildContext c, {Lote? lote}) =>
      _unica(() => _registrarVenda(c, lote: lote));

  Future<void> _registrarVenda(BuildContext c, {Lote? lote}) async {
    final atual = visao;
    if (atual == null || !atual.editavel) return;
    var alvo = lote ?? _lote(loteSelecionado);
    if (alvo != null && restante(alvo) == 0) alvo = null;
    final r = await abrirFormVenda(c, atual, lote: alvo);
    if (r != null) _aceitar(r.visao);
  }

  Future<void> editarLote(BuildContext c, {String? id}) =>
      _unica(() => _editarLote(c, id: id));

  Future<void> _editarLote(BuildContext c, {String? id}) async {
    final atual = visao;
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
    final atual = visao;
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
      atual.mes,
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

  /// Antes de fechar, verifica as metas do mês: uma meta já atingida é
  /// registrada e uma consulta que falhou bloqueia o fechamento.
  Future<void> fecharMes(BuildContext c) async {
    final atual = visao;
    if (atual == null || !atual.editavel || fechando) return;
    final mes = atual.mes;
    fechando = true;
    notifyListeners();
    try {
      await _fechar(c, mes);
    } finally {
      fechando = false;
      notifyListeners();
    }
  }

  bool _mudou(String mes) => _descartado || _estado.mes != mes;

  /// Preço a que a meta vendeu (`execucao.preco_usado`), se registrado.
  String _aPreco(Meta m) {
    final p = m.execucao?['preco_usado'];
    return p is num ? ' a ${brl(p.toDouble())}' : '';
  }

  Future<void> _fechar(BuildContext c, String mes) async {
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
    if (!c.mounted || _mudou(mes)) return;
    if (falha != null) {
      await avisar(
        c,
        'Não foi possível fechar o mês',
        'Falha ao verificar as metas antes de fechar: '
            '${String.fromCharCodes(textoErro(falha).runes.take(120))}',
      );
      return;
    }
    if (preparo != null) {
      final bloqueio = preparo.bloqueio;
      if (bloqueio != null && bloqueio.isNotEmpty) {
        await avisar(c, 'Não foi possível fechar o mês', bloqueio);
        return;
      }
      if (preparo.executadas.isNotEmpty || preparo.invalidas.isNotEmpty) {
        await recarregar();
        if (!c.mounted || _mudou(mes)) return;
        final erroCarga = erro;
        if (visao == null && erroCarga != null) {
          await avisar(c, 'Não foi possível carregar', erroCarga);
          return;
        }
        final linhas = [
          for (final m in preparo.executadas)
            '${m.ticker}: venda de ${m.qtd} registrada pela meta${_aPreco(m)}.',
          for (final m in preparo.invalidas)
            '${m.ticker}: meta inválida. ${m.ultimoErro ?? ''}',
        ];
        await avisar(c, 'Metas verificadas antes de fechar', linhas.join('\n'));
        if (!c.mounted || _mudou(mes)) return;
      }
    }
    await _confirmar(c, mes);
  }

  Future<void> _confirmar(BuildContext c, String mes) async {
    final atual = visao;
    if (atual == null || atual.mes != mes || !atual.editavel) return;
    final sim = await confirmar(
      c,
      'Fechar ${fmtMes(mes)}',
      'Depois de fechado, o mês não pode ser alterado.\n\n'
          'Total da DARF: ${brl(atual.apuracao.darf)}',
      sim: 'Fechar mês',
    );
    if (!sim || !c.mounted || _mudou(mes)) return;
    final Fechamento fechamento;
    try {
      fechamento = await _servicos.fecharMes(mes);
    } catch (e) {
      if (c.mounted) {
        await avisar(c, 'Não foi possível fechar o mês', textoErro(e));
      }
      return;
    }
    _aceitar(fechamento.visao);
    if (c.mounted) await avisar(c, 'Mês fechado', fechamento.mensagem);
  }
}
