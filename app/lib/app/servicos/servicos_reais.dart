// Os serviços reais com os timers e o cliente HTTP, comuns ao isolate e à
// Web. Sem package:flutter.

import 'dart:async';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'servicos_locais.dart';

// calculadora_darf.py:1266-1268 e android/main.py:2395.
Duration intervaloSyncPadrao({required bool windows}) =>
    Duration(seconds: windows ? 60 : 30);
const primeiraMetasPadrao = Duration(milliseconds: 2500);
const intervaloMetasPadrao = Duration(seconds: 60);
const primeiraNoticiasPadrao = Duration(seconds: 8);
const intervaloNoticiasPadrao = Duration(seconds: 60);

/// Os timers do app: sincronização (primeiro tick na hora), metas e notícias.
/// Nenhum erro de um passo derruba o timer: a próxima passada tenta de novo.
class TimersServicos {
  TimersServicos({
    required this.sync,
    required this.metas,
    required this.noticias,
    required this.intervaloSync,
    this.primeiraMetas = primeiraMetasPadrao,
    this.intervaloMetas = intervaloMetasPadrao,
    this.primeiraNoticias = primeiraNoticiasPadrao,
    this.intervaloNoticias = intervaloNoticiasPadrao,
  });

  final Future<void> Function() sync;
  final Future<void> Function() metas;
  final Future<void> Function() noticias;
  final Duration intervaloSync;
  final Duration primeiraMetas;
  final Duration intervaloMetas;
  final Duration primeiraNoticias;
  final Duration intervaloNoticias;

  final List<Timer> _timers = [];
  bool _parado = false;

  Future<void> _seguro(Future<void> Function() passo) async {
    try {
      await passo();
    } catch (_) {
      // config ilegível, disco ou rede: o aviso vem pelos eventos e pelas
      // telas; o timer continua
    }
  }

  void _agendar(
    Duration primeira,
    Duration intervalo,
    Future<void> Function() passo,
  ) {
    _timers.add(
      Timer(primeira, () {
        if (_parado) return;
        unawaited(_seguro(passo));
        _timers.add(
          Timer.periodic(intervalo, (_) => unawaited(_seguro(passo))),
        );
      }),
    );
  }

  void iniciar() {
    if (_parado) return;
    unawaited(_seguro(sync));
    _timers.add(Timer.periodic(intervaloSync, (_) => unawaited(_seguro(sync))));
    _agendar(primeiraMetas, intervaloMetas, metas);
    _agendar(primeiraNoticias, intervaloNoticias, noticias);
  }

  void cancelar() {
    _parado = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}

/// Fachada com os timers e o cliente HTTP (no isolate ou, na Web, na thread
/// da interface).
class ServicosReais extends ServicosLocais {
  ServicosReais({
    required super.repo,
    required super.yahoo,
    required super.conta,
    required super.abrirUrl,
    required super.noticias,
    super.atualizador,
    super.fazerBackup,
    required this.cliente,
  });

  final http.Client cliente;
  TimersServicos? timers;
  bool _timersIniciados = false;

  /// Os timers (sincronização no primeiro tick) só começam depois da
  /// partida: o backup da migração vem antes de qualquer sincronização.
  @override
  Future<EstadoInicial> iniciar() async {
    try {
      return await super.iniciar();
    } finally {
      if (!_timersIniciados) {
        _timersIniciados = true;
        timers?.iniciar();
      }
    }
  }

  @override
  Future<void> encerrar() async {
    timers?.cancelar();
    try {
      await super.encerrar();
    } finally {
      cliente.close();
    }
  }
}
