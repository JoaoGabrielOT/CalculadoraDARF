// Estado da janela de metas: a lista, o "Verificar agora" e a calculadora de
// preço-alvo (calculadora_darf.py:3304-3350, 3491-3720; android/main.py:
// 2442-2562, 2672-2768). Preços, impostos e projeções vêm dos serviços; aqui
// só se lê o que o usuário digitou e se mostra o resultado.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/dialogos.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import 'calculo_sugestao.dart';

/// Quantidade, preço de saída e lucro desejado digitados num ativo.
class CamposAtivo {
  final qtd = TextEditingController();
  final preco = TextEditingController();
  final lucro = TextEditingController();

  void dispose() {
    qtd.dispose();
    preco.dispose();
    lucro.dispose();
  }
}

/// O que a coluna esquerda mostra (`seg_modo`).
enum ModoMetas { sugestoes, calculadora }

/// Texto da linha de status do "Verificar agora". [hora] é "HH:MM".
String textoVerificacao(ResultadoVerificacao r, String hora) => switch (r) {
  VerificacaoConcluida() => 'Verificado às $hora.',
  VerificacaoEmAndamento() => 'Verificação já em andamento.',
  SemMetasAtivas() => 'Não há metas ativas para verificar.',
  // o Python mostrava "em andamento" (Android) ou "sem conexão" (Windows)
  VerificacaoFalhou(:final mensagem) => 'Não foi possível verificar: $mensagem',
};

const textoMetaCriada =
    'Meta criada. O app vai registrar a venda quando o preço-alvo for '
    'atingido.';

class ControleMetas extends ChangeNotifier {
  ControleMetas(this._servicos, this._estado) {
    _versao = _estado.versaoDados;
    _estado.addListener(_aoMudarEstado);
    unawaited(recarregar());
    unawaited(recarregarSugestoes());
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late int _versao;
  int _geracao = 0;
  int _geracaoCalculo = 0;
  int _geracaoSug = 0;
  bool _descartado = false;

  /// Metas, descrições e compras com quantidade livre; null até a primeira
  /// leitura (ou se ela falhou: [erro]). Numa releitura que falha a anterior
  /// fica à vista.
  VisaoMetas? visao;
  bool carregando = false;
  String? erro;

  ModoMetas modo = ModoMetas.sugestoes;

  // --- sugestões
  /// Cartões e rodapé; null até a primeira leitura. Numa releitura que falha
  /// a anterior fica à vista.
  VisaoSugestoes? sugestoes;
  bool carregandoSug = false;
  String? erroSug;

  /// "Atualizado às HH:MM." depois de cada leitura.
  String textoSug = '';

  /// Criando a meta de um cartão: desabilita os botões.
  bool criandoSug = false;

  // filtros, ordenação e o que foi digitado em cada ativo; nada disso pede
  // dados novos ao serviço (só desligar "Só posições abertas" busca o radar)
  Horizonte horizonte = Horizonte.swing;
  bool soPosicoes = true;
  FiltroDados filtroDados = FiltroDados.todos;
  OrdemSugestao ordem = OrdemSugestao.rr;
  final _entradas = <String, EntradasAtivo>{};
  final _campos = <String, CamposAtivo>{};

  EntradasAtivo entradasDe(String ticker) =>
      _entradas[ticker] ?? const EntradasAtivo();

  /// Campos de texto do ativo; ficam aqui para sobreviver à rolagem da lista.
  CamposAtivo camposDe(String ticker) =>
      _campos.putIfAbsent(ticker, CamposAtivo.new);

  /// Lê os campos do ativo (vazio ou inválido = sem valor) e refaz as contas.
  void aplicarCampos(String ticker) {
    final c = camposDe(ticker);
    T? tentar<T>(T Function(String) ler, String texto) {
      try {
        return ler(texto);
      } on FormatException {
        return null;
      }
    }

    _entradas[ticker] = EntradasAtivo(
      qtd: tentar(parseQtd, c.qtd.text),
      preco: tentar(parseNum, c.preco.text),
      lucro: tentar(parseValor, c.lucro.text),
    );
    notifyListeners();
  }

  void definirHorizonte(Horizonte h) {
    if (h == horizonte) return;
    horizonte = h;
    notifyListeners();
  }

  void definirFiltroDados(FiltroDados f) {
    if (f == filtroDados) return;
    filtroDados = f;
    notifyListeners();
  }

  void definirOrdem(OrdemSugestao o) {
    if (o == ordem) return;
    ordem = o;
    notifyListeners();
  }

  /// Desligado, os tickers do radar entram e só então são pedidos.
  void alternarSoPosicoes() {
    soPosicoes = !soPosicoes;
    notifyListeners();
    if (!soPosicoes) unawaited(recarregarSugestoes());
  }

  /// Ativos filtrados e ordenados, com o cenário de cada um.
  List<ResultadoAtivo> get listaSugestoes => prepararLista(
    sugestoes?.ativos ?? const [],
    horizonte: horizonte,
    soPosicoes: soPosicoes,
    dados: filtroDados,
    ordem: ordem,
    entradas: entradasDe,
    hoje: ambiente.hoje(),
    agoraBr: ambiente.agoraBr(),
  );

  /// Quantidade livre de uma compra para metas (0 se não há ou sumiu).
  int livreDe(String loteId) {
    for (final l in visao?.lotes ?? const <LoteLivre>[]) {
      if (l.lote.id == loteId) return l.livre;
    }
    return 0;
  }

  // --- verificar agora
  bool verificando = false;
  String textoVerif = '';

  // --- calculadora
  final qtd = TextEditingController();
  final lucro = TextEditingController();
  final preco = TextEditingController();

  /// Id da compra escolhida; null = nenhuma compra em aberto.
  String? loteId;

  /// Preço-alvo calculado e a projeção no preço que está no campo.
  PrecoAlvo? calculo;
  Projecao? projecao;

  /// Nota abaixo das linhas quando não há cálculo ("Informe a quantidade…").
  String notaVazia = '';

  /// Mensagem sob o campo de preço; [mensagemOk] diz se é a de sucesso.
  String mensagem = '';
  bool mensagemOk = false;
  bool criando = false;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _estado.removeListener(_aoMudarEstado);
    qtd.dispose();
    lucro.dispose();
    preco.dispose();
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _aoMudarEstado() {
    if (_estado.versaoDados == _versao) return;
    _versao = _estado.versaoDados;
    unawaited(recarregar());
    if (modo == ModoMetas.sugestoes) unawaited(recarregarSugestoes());
  }

  /// Compra escolhida, com a quantidade livre.
  LoteLivre? get loteEscolhido {
    final id = loteId;
    for (final l in visao?.lotes ?? const <LoteLivre>[]) {
      if (l.lote.id == id) return l;
    }
    return null;
  }

  void trocarModo(ModoMetas m) {
    if (m == modo) return;
    modo = m;
    notifyListeners();
    if (m == ModoMetas.sugestoes) unawaited(recarregarSugestoes());
  }

  // --- sugestões (py:3370-3412)

  /// Vale o último pedido (`carregar_sugestoes`). A falha mostra o erro só
  /// se não houver cartões à vista.
  Future<void> recarregarSugestoes() async {
    final geracao = ++_geracaoSug;
    carregandoSug = true;
    textoSug = 'Carregando sugestões…';
    notifyListeners();
    try {
      final nova = await _servicos.sugestoesMetas(incluirRadar: !soPosicoes);
      if (geracao != _geracaoSug) return;
      sugestoes = nova;
      erroSug = null;
      textoSug = nova.ativos.isEmpty
          ? ''
          : 'Atualizado às ${horaMinuto(ambiente.agora())}.';
    } catch (e) {
      if (geracao != _geracaoSug) return;
      erroSug = e is PedidoSuperado && sugestoes != null ? null : textoErro(e);
      textoSug = '';
    }
    carregandoSug = false;
    notifyListeners();
  }

  /// "Criar meta de alvo e stop" de uma compra: usa o alvo e o stop do
  /// cenário de mercado, sobre a quantidade livre da compra, e só depois da
  /// confirmação. O stop nasce ligado (OCO) ao alvo.
  Future<void> criarMetasDoCenario(
    BuildContext c,
    ResultadoAtivo r,
    CompraNaPosicao compra,
  ) async {
    if (criandoSug) return;
    final cen = r.cenario;
    if (cen == null ||
        !cen.oportunidade ||
        r.ativo.estado != EstadoDados.ok ||
        cen.alvo == null ||
        cen.stop == null) {
      return;
    }
    final alvo = cen.alvo!;
    final stop = cen.stop!;
    final qtd = livreDe(compra.loteId);
    if (qtd <= 0) {
      await avisar(
        c,
        'Meta',
        'Não há quantidade livre nesta compra: cancele uma meta ativa antes.',
      );
      return;
    }
    final sim = await confirmar(
      c,
      'Criar meta de alvo e stop',
      'Serão criadas duas vendas automáticas de $qtd un. de '
          '${r.ativo.ticker} (compra de ${fmtData(compra.dataCompra)}): alvo '
          'a ${brl(alvo)} e stop a ${brl(stop)}, ligadas em OCO (quando uma '
          'executar, a outra é cancelada).'
          '\n\n'
          'A venda só é registrada quando '
          'o preço for atingido. Alvo e stop vêm do cenário de mercado, uma '
          'estimativa sem probabilidade associada.',
      sim: 'Criar metas',
      nao: 'Voltar',
    );
    if (!sim || !c.mounted) return;
    criandoSug = true;
    notifyListeners();
    try {
      final Meta meta;
      try {
        meta = await _servicos.criarMetaAlvo(compra.loteId, qtd, alvo);
      } catch (e) {
        if (e is! PedidoSuperado && c.mounted) {
          await avisar(c, 'Meta', textoErro(e));
        }
        return;
      }
      try {
        await _servicos.criarStop(
          compra.loteId,
          qtd,
          stop,
          ocoCom: meta.id,
          precoAtual: r.ativo.cotacao?.preco ?? cen.ancora,
        );
      } catch (e) {
        if (e is! PedidoSuperado && c.mounted) {
          await avisar(
            c,
            'Meta',
            'A meta de alvo foi criada, mas o stop não: ${textoErro(e)}',
          );
        }
      }
    } finally {
      criandoSug = false;
      notifyListeners();
    }
    await recarregar();
    unawaited(verificarAgora());
  }

  /// Vale o último pedido. Se a compra escolhida sumiu ou mudou de
  /// quantidade livre, volta à primeira e refaz a conta (`carregar_opcoes`).
  Future<void> recarregar() async {
    final geracao = ++_geracao;
    carregando = true;
    notifyListeners();
    try {
      final nova = await _servicos.metas();
      if (geracao != _geracao) return;
      final anterior = loteEscolhido;
      visao = nova;
      erro = null;
      final lotes = nova.lotes;
      if (lotes.isEmpty) {
        loteId = null;
        limparResultado();
      } else {
        final atual = loteEscolhido;
        if (atual == null ||
            anterior == null ||
            atual.livre != anterior.livre) {
          loteId = atual?.lote.id ?? lotes.first.lote.id;
          await escolherLote(loteId);
        }
      }
    } catch (e) {
      if (geracao != _geracao) return;
      // com a lista à vista o erro some junto com o pedido superado; sem
      // nada à vista ele aparece
      erro = e is PedidoSuperado && visao != null ? null : textoErro(e);
    }
    if (geracao != _geracao) return;
    carregando = false;
    notifyListeners();
  }

  // --- verificar agora (py:3700-3720)

  /// Verifica as metas ativas. Uma falha mostra o erro e libera o botão.
  Future<void> verificarAgora() async {
    if (verificando) return;
    verificando = true;
    textoVerif = 'Verificando o histórico de preços…';
    notifyListeners();
    try {
      final r = await _servicos.verificarMetas();
      textoVerif = textoVerificacao(r, horaMinuto(ambiente.agora()));
      if (r is VerificacaoConcluida) _estado.avisarRelatorioMetas(r.relatorio);
    } catch (e) {
      textoVerif = e is PedidoSuperado
          ? ''
          : 'Não foi possível verificar: ${textoErro(e)}';
    }
    verificando = false;
    notifyListeners();
    if (modo == ModoMetas.sugestoes) unawaited(recarregarSugestoes());
    await recarregar();
  }

  // --- lista

  /// Pergunta e cancela a meta [id] (py:3685-3697).
  Future<void> cancelar(BuildContext c, String id) async {
    final sim = await confirmar(
      c,
      'Cancelar meta',
      'A venda automática não será mais registrada para esta meta.',
      sim: 'Cancelar meta',
      nao: 'Voltar',
      perigo: true,
    );
    if (!sim || !c.mounted) return;
    try {
      await _servicos.cancelarMeta(id);
    } catch (e) {
      if (!c.mounted) return;
      await avisar(c, 'Meta', textoErro(e));
    }
    if (modo == ModoMetas.sugestoes) unawaited(recarregarSugestoes());
    await recarregar();
  }

  // --- calculadora

  /// Escolheu uma compra: a quantidade passa a ser a livre e a conta refaz.
  Future<void> escolherLote(String? id) async {
    loteId = id;
    final sel = loteEscolhido;
    if (sel != null) qtd.text = '${sel.livre}';
    await calcular();
  }

  void limparResultado([String nota = '']) {
    calculo = null;
    projecao = null;
    notaVazia = nota;
    notifyListeners();
  }

  /// Preço-alvo para o lucro desejado (`calcular`). O pedido mais novo vence.
  Future<void> calcular() async {
    final geracao = ++_geracaoCalculo;
    mensagem = '';
    final sel = loteEscolhido;
    if (sel == null) return limparResultado();
    final int q;
    final double l;
    try {
      q = parseQtd(qtd.text);
      l = parseValor(lucro.text);
    } on FormatException {
      return limparResultado(
        'Informe a quantidade e o lucro líquido desejado.',
      );
    }
    if (q > sel.livre) {
      return limparResultado('Quantidade maior que a livre (${sel.livre}).');
    }
    try {
      final r = await _servicos.calcularPrecoAlvo(sel.lote.id, q, l);
      if (geracao != _geracaoCalculo) return;
      calculo = r;
      projecao = r;
      notaVazia = '';
      preco.text = precoTexto(r.preco);
      notifyListeners();
    } catch (e) {
      if (geracao != _geracaoCalculo) return;
      if (e is PedidoSuperado) return;
      limparResultado(textoErro(e));
    }
  }

  /// O usuário editou o preço-alvo: projeta o resultado nesse preço
  /// (`projetar_preco`).
  Future<void> projetarPreco() async {
    final r = calculo;
    final sel = loteEscolhido;
    if (r == null || sel == null) return;
    final double p;
    try {
      p = parseNum(preco.text);
    } on FormatException {
      return;
    }
    final geracao = ++_geracaoCalculo;
    try {
      final nova = await _servicos.projetarPreco(sel.lote.id, r.qtd.toInt(), p);
      if (geracao != _geracaoCalculo) return;
      projecao = nova;
      notifyListeners();
    } catch (e) {
      if (geracao != _geracaoCalculo || e is PedidoSuperado) return;
      mensagem = textoErro(e);
      mensagemOk = false;
      notifyListeners();
    }
  }

  /// "Criar venda automática com este preço" (`criar`).
  Future<void> criar() async {
    if (criando) return;
    final sel = loteEscolhido;
    mensagemOk = false;
    final int q;
    final double p;
    if (sel == null) {
      return _erro('Não há compra em aberto para criar a meta.');
    }
    try {
      q = parseQtd(qtd.text);
    } on FormatException {
      return _erro('Quantidade inválida.');
    }
    try {
      p = parseNum(preco.text);
    } on FormatException {
      return _erro('Preço-alvo inválido.');
    }
    double? l;
    try {
      l = parseValor(lucro.text);
    } on FormatException {
      l = null;
    }
    criando = true;
    notifyListeners();
    try {
      await _servicos.criarMetaAlvo(sel.lote.id, q, p, lucroDesejado: l);
    } catch (e) {
      criando = false;
      if (e is PedidoSuperado) return notifyListeners();
      return _erro(textoErro(e));
    }
    criando = false;
    await recarregar();
    mensagem = textoMetaCriada;
    mensagemOk = true;
    notifyListeners();
    unawaited(verificarAgora());
  }

  void _erro(String texto) {
    mensagem = texto;
    mensagemOk = false;
    notifyListeners();
  }
}
