// Janela de metas: diálogo de 900 px no PC (Sugestões e Calculadora à
// esquerda, METAS à direita) e tela cheia com abas no celular
// (calculadora_darf.py:2587-2590, 3304-3350; android/main.py:2442-2562).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../componentes/cartao.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../../../nucleo/nucleo.dart';
import 'aba_calculadora.dart';
import 'aba_sugestoes.dart';
import 'controle_metas.dart';
import 'lista_metas.dart';

export 'controle_metas.dart' show textoVerificacao;

const larguraDialogoMetas = 900.0;
const _larguraColunaEsquerda = 420.0;

/// Abre a janela de metas. Com dados de amigo na tela volta antes para
/// "Meus dados" (py:2587-2590). Com [ticker] (menu da Apuração), as Sugestões
/// abrem com o cartão dele aberto e à vista; [compras] rola até os botões de
/// criar meta das compras dele.
Future<void> abrirMetas(
  BuildContext c, {
  String? ticker,
  bool compras = false,
}) async {
  final foco = ticker == null ? null : FocoMetas(ticker, compras: compras);
  final estado = c.read<EstadoApp>();
  await estado.trocarVisao(null);
  if (!c.mounted) return;
  if (expandido(c)) {
    await showDialog<void>(
      context: c,
      builder: (_) => Dialog(child: TelaMetas(dialogo: true, foco: foco)),
    );
  } else {
    await Navigator.of(c).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TelaMetas(dialogo: false, foco: foco),
      ),
    );
  }
}

class TelaMetas extends StatelessWidget {
  const TelaMetas({super.key, required this.dialogo, this.foco});

  /// Diálogo de 900 px (PC) ou tela cheia com abas (celular).
  final bool dialogo;

  /// Cartão das Sugestões que já abre à vista; null = nenhum.
  final FocoMetas? foco;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleMetas>(
      create: (c) =>
          ControleMetas(c.read<ServicosApp>(), c.read<EstadoApp>(), foco: foco),
      child: dialogo ? const _Dialogo() : const _Cheia(),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso();

  @override
  Widget build(BuildContext context) => Text(
    avisoRegistro,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: CoresApp.de(context).aviso,
    ),
  );
}

class _Dialogo extends StatelessWidget {
  const _Dialogo();

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleMetas>();
    final altura = (MediaQuery.sizeOf(context).height - 80).clamp(400.0, 760.0);
    return SizedBox(
      key: const ValueKey('metas-dialogo'),
      width: larguraDialogoMetas,
      height: altura,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meta de lucro / Preço-alvo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            const _Aviso(),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  SizedBox(
                    width: _larguraColunaEsquerda,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        BotaoSegmentado<ModoMetas>(
                          opcoes: const [
                            (ModoMetas.sugestoes, 'Sugestões'),
                            (ModoMetas.calculadora, 'Calculadora'),
                          ],
                          valor: controle.modo,
                          aoMudar: controle.trocarModo,
                        ),
                        Expanded(
                          child: controle.modo == ModoMetas.calculadora
                              ? const AbaCalculadora()
                              : const PainelSugestoes(),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: ListaMetas()),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cheia extends StatelessWidget {
  const _Cheia();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meta de lucro / Preço-alvo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sugestões'),
              Tab(text: 'Calculadora'),
              Tab(text: 'Metas'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(alignment: Alignment.centerLeft, child: _Aviso()),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: TabBarView(
                    children: [
                      PainelSugestoes(),
                      AbaCalculadora(),
                      ListaMetas(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
