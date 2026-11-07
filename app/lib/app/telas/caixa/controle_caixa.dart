// Estado da tela Caixa: o caixa carregado sem bloquear a interface, o filtro
// dos lançamentos e a virada do dia (calculadora_darf.py:1878-1984;
// android/main.py:1549-1626).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../formularios/abrir_formulario.dart';

/// Situação dos lançamentos na tabela (py:1881-1884).
enum FiltroAgenda {
  todos('Todos'),
  aLiquidar('A liquidar'),
  liquidados('Liquidados');

  const FiltroAgenda(this.rotulo);

  final String rotulo;

  bool aceita(LancamentoCaixa l) => switch (this) {
    todos => true,
    aLiquidar => l.status == 'Pendente',
    liquidados => l.status == 'Liquidado',
  };
}

class ControleCaixa extends ChangeNotifier {
  ControleCaixa(this._servicos, this._estado) {
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    _estado.addListener(_aoMudarEstado);
    // virada do dia: o que liquidou passa a Liquidado e entra no saldo
    // (py:1980-1984)
    _timer = Timer.periodic(intervaloVirada, (_) {
      if (ambiente.hoje() != _dia) unawaited(recarregar());
    });
    unawaited(recarregar());
  }

  static const intervaloVirada = Duration(seconds: 60);

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late String? _amigo;
  late int _versao;
  late String _dia;
  String? _dono; // de quem é a [visao]
  int _geracao = 0;
  bool _descartado = false;
  Timer? _timer;

  /// O caixa na tela; null enquanto o primeiro carregamento (ou o de outra
  /// visão) não chega, ou quando ele falhou ([erro]).
  VisaoCaixa? visao;
  bool carregando = false;
  String? erro;
  FiltroAgenda filtro = FiltroAgenda.todos;

  /// O formulário de saldo está aberto: não abre outro por cima.
  bool editando = false;

  /// O e-mail do amigo cujo caixa está na tela; null = meu caixa.
  String? get amigo => _estado.amigo;

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
    if (_estado.amigo == _amigo && _estado.versaoDados == _versao) return;
    _amigo = _estado.amigo;
    _versao = _estado.versaoDados;
    unawaited(recarregar());
  }

  /// Vale o último pedido: uma resposta antiga é descartada. Ao trocar de
  /// visão o caixa anterior sai da tela; no mesmo dono ele fica até o novo
  /// chegar.
  Future<void> recarregar() async {
    final geracao = ++_geracao;
    final alvo = _estado.amigo;
    _dia = ambiente.hoje();
    if (_dono != alvo) visao = null;
    carregando = true;
    notifyListeners();
    try {
      final nova = await _servicos.caixa(amigo: alvo);
      if (geracao != _geracao) return;
      visao = nova;
      _dono = alvo;
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      visao = null;
      erro = e is PedidoSuperado ? null : textoErro(e);
    }
    carregando = false;
    notifyListeners();
  }

  void definirFiltro(FiltroAgenda f) {
    if (f == filtro) return;
    filtro = f;
    notifyListeners();
  }

  /// Lançamentos da agenda (já na ordem da liquidação) pelo filtro.
  List<LancamentoCaixa> get lancamentos => [
    for (final g in visao?.agenda ?? const <GrupoAgenda>[])
      for (final l in g.itens)
        if (filtro.aceita(l)) l,
  ];

  /// Definir, aporte ou retirada; só no meu caixa.
  Future<void> editarSaldo(
    BuildContext c, [
    ModoSaldo modo = ModoSaldo.definir,
  ]) async {
    final atual = visao;
    if (atual == null || _estado.amigo != null || editando) return;
    editando = true;
    notifyListeners();
    try {
      final nova = await abrirFormSaldo(c, atual.resumo, modo);
      // a visão devolvida vale se ainda é o meu caixa
      if (nova != null && _estado.amigo == null) {
        ++_geracao;
        visao = nova;
        erro = null;
        carregando = false;
      }
    } finally {
      editando = false;
      notifyListeners();
    }
  }
}
