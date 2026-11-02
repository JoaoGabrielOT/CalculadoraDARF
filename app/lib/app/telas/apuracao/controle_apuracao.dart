// Estado da tela de Apuração: o mês exibido, o carregamento sem bloquear a
// interface e o fluxo de Fechar mês (calculadora_darf.py:1733-1770;
// android/main.py:1127-1184).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/dialogos.dart';
import '../../componentes/seletor_mes.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../formularios/abrir_formulario.dart';

class ControleApuracao extends ChangeNotifier {
  ControleApuracao(this._servicos, this._estado) {
    _mes = _estado.mes;
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    _estado.addListener(_aoMudarEstado);
    unawaited(recarregar());
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late String _mes;
  String? _amigo;
  late int _versao;
  int _geracao = 0;
  bool _descartado = false;

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

  /// Preço atual por ticker em carteira, preenchido pela Tarefa 14.
  Map<String, double?> precos = {};

  /// O mês escolhido no estado do app (o seletor muda por lá).
  String get mes => _estado.mes;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
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
    }
    carregando = true;
    notifyListeners();
    try {
      final nova = await _servicos.carregarMes(mes, amigo: amigo);
      if (geracao != _geracao) return;
      visao = nova;
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      visao = null;
      erro = e is PedidoSuperado ? null : textoErro(e);
    }
    carregando = false;
    notifyListeners();
    if (amigo == null) unawaited(_carregarSaldo(geracao));
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
  Future<void> novaCompra(BuildContext c) async {
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
    visao = nova;
    notifyListeners();
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
