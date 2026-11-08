import 'dart:async';

import '../../nucleo/nucleo.dart';
import '../google/erros.dart';
import '../google/google.dart';
import '../google/login.dart';
import 'dados_sincronizacao.dart';

enum StatusSync { off, login, sync, ok, pendente, offline, erro }

/// Resultado de uma rodada que ficou para trás (a conta mudou ou saiu): é
/// descartado sem mexer no status.
class _Descartado implements Exception {}

/// Ciclo de sincronização com a planilha (calculadora_darf.py:2736-2919;
/// android/main.py:2277-2406). Uma sincronização por vez; pedidos que chegam
/// durante ela refazem o ciclo.
class Sincronizador {
  Sincronizador({
    required this.conta,
    required this.dados,
    this.aoMudarStatus,
    this.aoMudarDados,
    this.aoAvisar,
    this.atrasoAgendamento = const Duration(milliseconds: 1500),
  });

  final ContaGoogle conta;
  final DadosSincronizacao dados;
  final void Function(StatusSync)? aoMudarStatus;
  final void Function()? aoMudarDados;
  final void Function(String)? aoAvisar;
  final Duration atrasoAgendamento;

  StatusSync _status = StatusSync.off;
  String _ultimoErro = '';
  double _ultimaPuxada = 0;
  double? _ultimaSync;
  bool _rodando = false;
  int _concluidas = 0;
  bool _resync = false;
  bool _conectandoToken = false;
  bool _logando = false;
  Completer<void>? _cancelamento;
  Timer? _timer;
  Future<String>? _preparando;

  /// Aumenta a cada `sair()`: rodadas iniciadas antes não mexem mais no estado.
  int _geracao = 0;

  StatusSync get status => _status;
  String get ultimoErro => _ultimoErro;
  double get ultimaPuxada => _ultimaPuxada;
  double? get ultimaSync => _ultimaSync;
  bool get rodando => _rodando;

  /// Rodadas de sincronização concluídas com sucesso desde a criação.
  int get concluidas => _concluidas;

  /// Login ou reconexão com o token em andamento: a UI não deve iniciar outro.
  bool get ocupado => _logando || _conectandoToken;

  /// Encerra o login em andamento (fecha o servidor loopback) com
  /// "O login foi cancelado.".
  Future<void> cancelarLogin() async {
    final c = _cancelamento;
    if (c != null && !c.isCompleted) c.complete();
  }

  // Callbacks da UI nunca derrubam o ciclo.
  void _definirStatus(StatusSync s) {
    _status = s;
    try {
      aoMudarStatus?.call(s);
    } catch (_) {}
  }

  void _avisar(String texto) {
    try {
      aoAvisar?.call(texto);
    } catch (_) {}
  }

  void _verificar(int geracao) {
    if (geracao != _geracao) throw _Descartado();
  }

  /// `pos_login`: acha (ou cria) a planilha da conta e a guarda em cfg. Uma
  /// preparação por vez, para não criar duas planilhas no Drive.
  Future<String> prepararPlanilha() {
    final atual = _preparando;
    if (atual != null) return atual;
    late final Future<String> f;
    f = _preparar().whenComplete(() {
      if (identical(_preparando, f)) _preparando = null;
    });
    return _preparando = f;
  }

  Future<String> _preparar() async {
    final geracao = _geracao;
    final email = conta.email!;
    var sid = await dados.planilhaDe(email);
    if (sid != null && sid.isNotEmpty && !await conta.planilhaExiste(sid)) {
      sid = null;
    }
    if (sid == null || sid.isEmpty) {
      sid = await conta.buscarPlanilha('me') ?? await conta.criarPlanilha();
    }
    // a conta pode ter saído ou trocado enquanto a rede respondia
    if (geracao != _geracao || conta.email != email) throw _Descartado();
    await dados.definirPlanilha(email, sid);
    return sid;
  }

  Future<void> conectarComToken() async {
    if (_logando) return;
    final geracao = _geracao;
    _conectandoToken = true;
    try {
      _definirStatus(StatusSync.sync);
      try {
        await conta.carregarToken();
        _verificar(geracao);
      } on _Descartado {
        return;
      } on LoginNecessario {
        // renovação de uma conta que já saiu, ou de um login novo em curso
        if (geracao != _geracao || _logando) return;
        _sairDaConta();
        _definirStatus(StatusSync.off);
        return;
      } catch (e) {
        await _tratarErro(e, geracao);
        return;
      }
      await _prepararESincronizar(geracao);
    } finally {
      if (geracao == _geracao) _conectandoToken = false;
    }
  }

  Future<void> conectar(AbrirUrl abrirUrl) async {
    if (ocupado) return;
    final geracao = _geracao;
    final cancelamento = _cancelamento = Completer<void>();
    _logando = true;
    _definirStatus(StatusSync.login);
    try {
      await conta.login(abrirUrl, cancelar: cancelamento.future);
    } catch (e) {
      if (geracao != _geracao) return;
      _definirStatus(StatusSync.off);
      final texto = e.toString();
      _avisar(texto.isEmpty ? 'O login não foi concluído.' : texto);
      return;
    } finally {
      if (geracao == _geracao) {
        _logando = false;
        if (identical(_cancelamento, cancelamento)) _cancelamento = null;
      }
    }
    if (geracao != _geracao) {
      // `sair()` veio durante a troca do código: o login acabou de regravar o
      // token. Só não sai se outro login já começou (ele grava por cima).
      if (!_logando) _sairDaConta();
      return;
    }
    _avisar('Conectado como ${conta.email}.');
    await _prepararESincronizar(geracao);
  }

  Future<void> _prepararESincronizar(int geracao) async {
    try {
      await prepararPlanilha();
      _verificar(geracao);
    } catch (e) {
      await _tratarErro(e, geracao);
      return;
    }
    await sincronizar();
  }

  Future<void> sincronizar() async {
    if (conta.email == null) return;
    if (_rodando) {
      _resync = true;
      return;
    }
    _rodando = true;
    final geracao = _geracao;
    try {
      _definirStatus(StatusSync.sync);
      final email = conta.email!;
      var sid = await dados.planilhaDe(email);
      _verificar(geracao);
      if (sid == null || sid.isEmpty) sid = await prepararPlanilha();
      while (true) {
        do {
          _resync = false;
          final abas = await conta.ler(sid);
          _verificar(geracao);
          final r = await dados.mesclar(abas);
          _verificar(geracao);
          if (r.mudou) {
            try {
              aoMudarDados?.call();
            } catch (_) {}
          }
          for (final texto in r.avisos) {
            _avisar('Ajuste manual necessário: $texto');
          }
          await conta.escrever(sid, r.linhas);
          _verificar(geracao);
        } while (_resync);
        await dados.definirPendente(false);
        _verificar(geracao);
        // pedido que chegou enquanto o pendente era limpo não pode se perder
        if (!_resync) break;
      }
      _ultimaSync = ambiente.agora();
      _ultimaPuxada = ambiente.agora();
      _ultimoErro = '';
      _concluidas++;
      _definirStatus(StatusSync.ok);
    } catch (e) {
      await _tratarErro(e, geracao);
    } finally {
      if (geracao == _geracao) _rodando = false;
    }
  }

  Future<void> _tratarErro(Object e, int geracao) async {
    if (e is _Descartado || geracao != _geracao || _logando) return;
    if (e is LoginNecessario) {
      _sairDaConta();
      _definirStatus(StatusSync.off);
      _avisar('Sessão expirada. Conecte sua conta Google novamente.');
    } else if (e is Offline) {
      _definirStatus(StatusSync.offline);
    } else {
      try {
        final email = conta.email;
        if (e is ErroGoogle && e.status == 404 && email != null) {
          await dados.definirPlanilha(email, null);
        }
      } catch (_) {
        // a mensagem do erro original é a que importa
      }
      _ultimoErro = e.toString();
      _definirStatus(StatusSync.erro);
    }
  }

  /// `agendar_sync`: marca pendente e sincroniza depois do atraso.
  Future<void> agendar() async {
    final geracao = _geracao;
    try {
      await dados.definirPendente(true);
      if (conta.email == null) return;
      _definirStatus(StatusSync.pendente);
      _timer?.cancel();
      _timer = Timer(atrasoAgendamento, () {
        _timer = null;
        unawaited(sincronizar());
      });
    } catch (e) {
      if (geracao != _geracao) return;
      _ultimoErro = e.toString();
      _definirStatus(StatusSync.erro);
    }
  }

  /// `tick_sync`/`laco`: puxa o que está pendente ou atrasado.
  Future<void> tick() async {
    if (_logando) return;
    final geracao = _geracao;
    try {
      if (conta.email != null) {
        final atrasada = ambiente.agora() - _ultimaPuxada > 300;
        if ((await dados.pendente() || atrasada) && !_rodando) {
          await sincronizar();
        }
      } else if (conta.temToken() && !_conectandoToken) {
        await conectarComToken();
      }
    } catch (e) {
      if (geracao != _geracao || _logando) return;
      _ultimoErro = e.toString();
      _definirStatus(StatusSync.erro);
    }
  }

  /// `conta.sair()` não pode derrubar o tratamento de erro.
  void _sairDaConta() {
    try {
      conta.sair();
    } catch (_) {}
  }

  void sair() {
    unawaited(cancelarLogin());
    _geracao++;
    _logando = false;
    _cancelamento = null;
    _timer?.cancel();
    _timer = null;
    _rodando = false;
    _resync = false;
    _preparando = null;
    _conectandoToken = false;
    conta.sair();
    _definirStatus(StatusSync.off);
  }

  /// Encerra o ciclo sem sair da conta: cancela o login e o agendamento, e as
  /// rodadas em andamento são descartadas.
  void encerrar() {
    unawaited(cancelarLogin());
    _geracao++;
    _timer?.cancel();
    _timer = null;
  }

  /// Planilha de um amigo, só para leitura.
  Future<DadosPlanilha> lerAmigo(String email) async {
    final sid = await conta.buscarPlanilha(email);
    if (sid == null) {
      throw ErroGoogle(
        '$email ainda não compartilhou a planilha com você. '
        'Peça para ele adicionar ${conta.email} em Amigos.',
      );
    }
    return reconstruir(await conta.ler(sid));
  }
}
