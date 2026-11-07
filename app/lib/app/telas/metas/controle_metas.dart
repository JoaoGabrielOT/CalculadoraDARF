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
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late int _versao;
  int _geracao = 0;
  int _geracaoCalculo = 0;
  bool _descartado = false;

  /// Metas, descrições e compras com quantidade livre; null até a primeira
  /// leitura (ou se ela falhou: [erro]). Numa releitura que falha a anterior
  /// fica à vista.
  VisaoMetas? visao;
  bool carregando = false;
  String? erro;

  ModoMetas modo = ModoMetas.sugestoes;

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
    super.dispose();
  }

  void _aoMudarEstado() {
    if (_estado.versaoDados == _versao) return;
    _versao = _estado.versaoDados;
    unawaited(recarregar());
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
