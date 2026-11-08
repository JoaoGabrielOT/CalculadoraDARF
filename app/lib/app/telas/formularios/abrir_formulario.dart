// Abertura dos formulários: diálogo de 420 px no layout expandido, rota em
// tela cheia no compacto. Enter salva e Esc cancela (calculadora_darf.py:164-165).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';

export 'form_compra.dart' show abrirFormCompra;
export 'form_saldo.dart' show abrirFormSaldo;
export 'form_venda.dart' show abrirFormVenda;

const larguraDialogoFormulario = 420.0;

/// Abre o formulário que [construir] monta; `dialogo` diz em qual dos dois
/// formatos ele está. Devolve o que o formulário entregar, ou null se cancelar.
Future<T?> abrirFormulario<T>(
  BuildContext c,
  Widget Function(bool dialogo) construir,
) {
  if (expandido(c)) {
    return showDialog<T>(
      context: c,
      // modal: só Cancelar ou Esc fecham (py:Toplevel); tocar fora não
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: SizedBox(
          width: larguraDialogoFormulario,
          child: construir(true),
        ),
      ),
    );
  }
  return Navigator.of(c).push<T>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => construir(false)),
  );
}

/// Moldura comum: título, conteúdo rolável, erro no rodapé e Cancelar/Salvar.
class QuadroFormulario extends StatelessWidget {
  const QuadroFormulario({
    required this.dialogo,
    required this.titulo,
    required this.children,
    required this.erro,
    required this.salvando,
    required this.aoSalvar,
    this.podeSalvar = true,
    this.indicador = false,
  }) : super(key: const ValueKey('quadro-formulario'));

  final bool dialogo;
  final String titulo;
  final List<Widget> children;
  final String erro;
  final bool salvando;
  final VoidCallback aoSalvar;

  /// Falso desativa o Salvar (formulário ainda inválido).
  final bool podeSalvar;

  /// Mostra um indicador de progresso no Salvar enquanto grava.
  final bool indicador;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    // 48 dp no celular; no PC o ponteiro é preciso.
    final alvo = dialogo ? 40.0 : 48.0;
    final miolo = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, dialogo ? 4 : 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: children,
      ),
    );
    final rodape = Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (erro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(erro, style: TextStyle(color: c.queda)),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: Size(88, alvo)),
                onPressed: salvando ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: Size(110, alvo)),
                onPressed: salvando || !podeSalvar ? null : aoSalvar,
                child: indicador && salvando
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          Text('Salvar'),
                        ],
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
        ],
      ),
    );
    final corpo = dialogo
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Text(
                  titulo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(child: miolo),
              rodape,
            ],
          )
        : Scaffold(
            appBar: AppBar(title: Text(titulo)),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(child: miolo),
                  rodape,
                ],
              ),
            ),
          );
    // Voltar não fecha durante a gravação: o chamador receberia nulo e a tela
    // ficaria desatualizada.
    return PopScope(
      canPop: !salvando,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _salvar,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _salvar,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!salvando) Navigator.of(context).pop();
          },
        },
        child: corpo,
      ),
    );
  }

  void _salvar() {
    if (!salvando && podeSalvar) aoSalvar();
  }
}

/// Salvar dos formulários: bloqueia toques repetidos, mostra o erro do
/// serviço no rodapé (sem fechar) e fecha com o resultado.
mixin SalvarFormulario<W extends StatefulWidget, T> on State<W> {
  String erro = '';
  bool salvando = false;

  /// [acao] devolve null quando recusou; nesse caso já preencheu [erro].
  Future<void> salvarCom(Future<T?> Function() acao) async {
    if (salvando) return;
    setState(() {
      salvando = true;
      erro = '';
    });
    try {
      final r = await acao();
      if (!mounted) return;
      if (r == null) {
        setState(() => salvando = false);
        return;
      }
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        salvando = false;
        // pedido superado não aparece ao usuário
        erro = e is PedidoSuperado ? '' : textoErro(e);
      });
    }
  }
}
