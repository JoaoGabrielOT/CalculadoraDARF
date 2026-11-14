// Login obrigatório da Web: sem token nem e-mail, a casca dá lugar a esta
// tela. Os avisos da fila (partida, volta do login, sessão expirada) aparecem
// aqui, acima do botão.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../estado/estado_app.dart';
import '../../plataforma/plataforma.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../servicos/eventos.dart';
import '../../tema/cores_app.dart';
import '../conta/tela_conta.dart';

enum _Destino { child, carregando, login }

/// Mostra [TelaLoginWeb] quando a conta não tem token nem e-mail; senão
/// [child]. Falha e carregamento do início ficam com [child] (a casca).
class PortaoLoginWeb extends StatelessWidget {
  const PortaoLoginWeb({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final destino = context.select<EstadoApp, _Destino>((e) {
      if (e.falhaInicial != null || e.carregando) return _Destino.child;
      // antes da primeira leitura da conta a tela de login piscaria e
      // tomaria os avisos de quem já tem sessão
      if (!e.contaCarregada) return _Destino.carregando;
      final conta = e.conta;
      return !conta.temToken && conta.email == null
          ? _Destino.login
          : _Destino.child;
    });
    return switch (destino) {
      _Destino.child => child,
      // a leitura é local e rápida: um fundo vazio, sem girar nada
      _Destino.carregando => const Scaffold(),
      _Destino.login => const TelaLoginWeb(),
    };
  }
}

class TelaLoginWeb extends StatefulWidget {
  const TelaLoginWeb({super.key});

  @override
  State<TelaLoginWeb> createState() => _TelaLoginWebState();
}

class _TelaLoginWebState extends State<TelaLoginWeb> {
  late final EstadoApp _estado = context.read<EstadoApp>();
  late final ControleConta _controle = ControleConta(
    context.read<ServicosApp>(),
    _estado,
    context.read<Plataforma>(),
  );

  /// Avisos já tirados da fila, um por título (o mais novo vale).
  final List<EventoAviso> _avisos = [];
  bool _quadroAgendado = false;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    if (estado.avisos.isNotEmpty) _agendarQuadro();
    final cores = CoresApp.de(context);
    final gradiente = cores.fundoGradiente;
    final cena = Scaffold(
      backgroundColor: gradiente == null ? null : Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  const Text(
                    'Calculadora DARF',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    textoLoginWebTitulo,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text(textoLoginWebCorpo),
                  for (final a in _avisos) _QuadroAviso(a),
                  ListenableBuilder(
                    listenable: _controle,
                    builder: (context, _) {
                      final abrindo =
                          estado.conta.status == StatusSync.login ||
                          _controle.conectando;
                      return FilledButton(
                        onPressed: abrindo
                            ? null
                            : () => unawaited(_controle.conectar()),
                        child: Text(
                          abrindo
                              ? 'Abrindo o Google...'
                              : 'Entrar com o Google',
                        ),
                      );
                    },
                  ),
                  Text(
                    textoLoginWebContasAutorizadas,
                    style: TextStyle(fontSize: 12, color: cores.textoSuave),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (gradiente == null) return cena;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradiente),
      child: cena,
    );
  }

  /// Uma só chamada pendente por quadro, como na casca.
  void _agendarQuadro() {
    if (_quadroAgendado) return;
    _quadroAgendado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quadroAgendado = false;
      if (!mounted) return;
      var mudou = false;
      while (true) {
        final aviso = _estado.proximoAviso();
        if (aviso == null) break;
        _avisos
          ..removeWhere((a) => a.titulo == aviso.titulo)
          ..add(aviso);
        mudou = true;
      }
      if (mudou) setState(() {});
    });
  }
}

class _QuadroAviso extends StatelessWidget {
  const _QuadroAviso(this.aviso);

  final EventoAviso aviso;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cores.aviso.withValues(alpha: .12),
        border: Border.all(color: cores.aviso.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              aviso.titulo,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(aviso.texto),
          ],
        ),
      ),
    );
  }
}
