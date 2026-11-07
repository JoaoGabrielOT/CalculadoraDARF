// Atualização do app: o convite com as novidades e o diálogo que baixa e
// instala (calculadora_darf.py:2673-2688, 3240-3303; android/main.py:
// 2769-2844). O download e a conferência são dos serviços; aqui só se mostra
// o progresso e se entrega o caminho devolvido à plataforma.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../../versao.dart';
import '../../componentes/dialogos.dart';
import '../../plataforma/plataforma.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../servicos/eventos.dart';
import '../../tema/cores_app.dart';

const _bytesPorMb = 1024 * 1024;

/// Notas até [limite] caracteres; o que passa vira "…" (py:2680).
String notasCortadas(String notas, int limite) {
  final letras = notas.runes.toList();
  if (letras.length <= limite) return notas;
  return '${String.fromCharCodes(letras.take(limite)).trimRight()}…';
}

/// Pergunta se o usuário quer atualizar e, se quiser, abre o download.
Future<void> oferecerAtualizacao(BuildContext c, InfoAtualizacao info) async {
  // 600 no Windows (py:2679), 500 no Android (android/main.py:2779)
  final windows = c.read<Plataforma>().windows;
  final notas = notasCortadas(info.notas, windows ? 600 : 500);
  var texto =
      'A versão ${info.versao} está disponível. '
      'Você está usando a $versaoApp.';
  if (notas.isNotEmpty) texto += '\n\nNovidades:\n$notas';
  final sim = await confirmar(
    c,
    'Nova versão disponível',
    texto,
    sim: 'Atualizar',
    nao: 'Depois',
  );
  if (!sim || !c.mounted) return;
  await showDialog<void>(
    context: c,
    barrierDismissible: false,
    builder: (_) => DialogoAtualizacao(info: info),
  );
}

class DialogoAtualizacao extends StatefulWidget {
  const DialogoAtualizacao({super.key, required this.info});

  final InfoAtualizacao info;

  @override
  State<DialogoAtualizacao> createState() => _DialogoAtualizacaoState();
}

class _DialogoAtualizacaoState extends State<DialogoAtualizacao> {
  late final ServicosApp _servicos = context.read<ServicosApp>();
  late final Plataforma _plataforma = context.read<Plataforma>();
  StreamSubscription<EventoServico>? _assinatura;

  String _texto = 'Baixando…';

  /// Fração baixada; null = tamanho desconhecido (barra indeterminada).
  double? _fracao = 0;
  bool _cancelado = false;
  bool _falhou = false;

  /// O instalador já foi pedido: não há mais o que cancelar.
  bool _instalando = false;

  @override
  void initState() {
    super.initState();
    _assinatura = _servicos.eventos.listen((e) {
      if (e is EventoProgresso) _progresso(e.baixado, e.total);
    });
    unawaited(_baixar());
  }

  @override
  void dispose() {
    unawaited(_assinatura?.cancel());
    super.dispose();
  }

  void _progresso(int baixado, int total) {
    if (_cancelado || _falhou || _instalando || !mounted) return;
    String mb(int b) =>
        (b / _bytesPorMb).toStringAsFixed(1).replaceAll('.', ',');
    setState(() {
      if (total > 0) {
        _fracao = (baixado / total).clamp(0.0, 1.0);
        _texto = 'Baixando… ${mb(baixado)} de ${mb(total)} MB';
      } else {
        _fracao = null;
        _texto = 'Baixando… ${mb(baixado)} MB';
      }
    });
  }

  Future<void> _baixar() async {
    try {
      final caminho = await _servicos.baixarAtualizacao(widget.info);
      if (_cancelado || !mounted) return;
      setState(() {
        _instalando = true;
        _fracao = 1;
        _texto = _plataforma.windows
            ? 'Instalando. O app será reaberto em alguns segundos…'
            : 'Abrindo o instalador do Android…';
      });
      await _plataforma.instalarAtualizacao(caminho);
    } catch (e) {
      if (_cancelado || !mounted) return;
      setState(() {
        _falhou = true;
        _instalando = false;
        _texto = 'Não foi possível atualizar: ${textoErro(e)}';
      });
    }
  }

  void _cancelar() {
    _cancelado = true;
    unawaited(_servicos.cancelarDownload().catchError((Object _) {}));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    // o Windows reabre o app sozinho: sem botão enquanto instala; o Android
    // abre o instalador e deixa "Fechar"
    final Widget? botao;
    if (_falhou || (_instalando && !_plataforma.windows)) {
      botao = TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      );
    } else if (_instalando) {
      botao = null;
    } else {
      botao = TextButton(onPressed: _cancelar, child: const Text('Cancelar'));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_falhou || (_instalando && !_plataforma.windows)) {
          Navigator.of(context).pop();
        } else if (!_instalando) {
          _cancelar();
        }
      },
      child: AlertDialog(
        title: Text('Atualizando para a versão ${widget.info.versao}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                _texto,
                style: TextStyle(
                  color: _falhou ? cores.queda : cores.textoSuave,
                ),
              ),
              if (!_falhou) LinearProgressIndicator(value: _fracao),
            ],
          ),
        ),
        actions: [?botao],
      ),
    );
  }
}
