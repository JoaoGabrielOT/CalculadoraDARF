import 'dart:async';

import '../../nucleo/nucleo.dart';
import '../google/erros.dart';
import '../google/google.dart';
import '../google/login.dart';
import 'dados_sincronizacao.dart';

enum StatusSync { off, login, sync, ok, pendente, offline, erro }

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
  bool _resync = false;
  bool _conectandoToken = false;
  Timer? _timer;

  StatusSync get status => _status;
  String get ultimoErro => _ultimoErro;
  double get ultimaPuxada => _ultimaPuxada;
  double? get ultimaSync => _ultimaSync;
  bool get rodando => _rodando;

  void _definirStatus(StatusSync s) {
    _status = s;
    aoMudarStatus?.call(s);
  }

  void _avisar(String texto) => aoAvisar?.call(texto);

  /// `pos_login`: acha (ou cria) a planilha da conta e a guarda em cfg.
  Future<String> prepararPlanilha() async {
    final email = conta.email!;
    var sid = await dados.planilhaDe(email);
    if (sid != null && sid.isNotEmpty && !await conta.planilhaExiste(sid)) {
      sid = null;
    }
    if (sid == null || sid.isEmpty) {
      sid = await conta.buscarPlanilha('me') ?? await conta.criarPlanilha();
    }
    await dados.definirPlanilha(email, sid);
    return sid;
  }

  Future<void> conectarComToken() async {
    _conectandoToken = true;
    try {
      _definirStatus(StatusSync.sync);
      try {
        await conta.carregarToken();
      } on Offline {
        _definirStatus(StatusSync.offline);
        return;
      } catch (_) {
        conta.sair();
        _definirStatus(StatusSync.off);
        return;
      }
      await _prepararESincronizar();
    } finally {
      _conectandoToken = false;
    }
  }

  Future<void> conectar(AbrirUrl abrirUrl) async {
    _definirStatus(StatusSync.login);
    try {
      await conta.login(abrirUrl);
    } catch (e) {
      _definirStatus(StatusSync.off);
      final texto = e.toString();
      _avisar(texto.isEmpty ? 'O login não foi concluído.' : texto);
      return;
    }
    _avisar('Conectado como ${conta.email}.');
    await _prepararESincronizar();
  }

  Future<void> _prepararESincronizar() async {
    try {
      await prepararPlanilha();
    } catch (e) {
      await _tratarErro(e);
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
    try {
      _definirStatus(StatusSync.sync);
      final email = conta.email!;
      var sid = await dados.planilhaDe(email);
      if (sid == null || sid.isEmpty) sid = await prepararPlanilha();
      do {
        _resync = false;
        final abas = await conta.ler(sid);
        final r = await dados.mesclar(abas);
        if (r.mudou) aoMudarDados?.call();
        for (final texto in r.avisos) {
          _avisar('Ajuste manual necessário: $texto');
        }
        await conta.escrever(sid, r.linhas);
      } while (_resync);
      await dados.definirPendente(false);
      _ultimaSync = ambiente.agora();
      _ultimaPuxada = ambiente.agora();
      _ultimoErro = '';
      _definirStatus(StatusSync.ok);
    } catch (e) {
      await _tratarErro(e);
    } finally {
      _rodando = false;
    }
  }

  Future<void> _tratarErro(Object e) async {
    if (e is LoginNecessario) {
      conta.sair();
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
    await dados.definirPendente(true);
    if (conta.email == null) return;
    _definirStatus(StatusSync.pendente);
    _timer?.cancel();
    _timer = Timer(atrasoAgendamento, () {
      _timer = null;
      unawaited(sincronizar());
    });
  }

  /// `tick_sync`/`laco`: puxa o que está pendente ou atrasado.
  Future<void> tick() async {
    if (conta.email != null) {
      final atrasada = ambiente.agora() - _ultimaPuxada > 300;
      if ((await dados.pendente() || atrasada) && !_rodando) {
        await sincronizar();
      }
    } else if (conta.temToken() && !_conectandoToken) {
      await conectarComToken();
    }
  }

  void sair() {
    _timer?.cancel();
    _timer = null;
    conta.sair();
    _definirStatus(StatusSync.off);
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
