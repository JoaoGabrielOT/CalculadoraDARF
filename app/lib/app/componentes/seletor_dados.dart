// Seletor de dados global: meus dados ou os de um amigo
// (calculadora_darf.py:2933-2950). Fica na casca: texto no cabeçalho do PC,
// ícone no AppBar do celular. Desabilitado enquanto os dados do amigo
// carregam.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../estado/estado_app.dart';
import '../servicos/api.dart';
import '../telas/amigos/tela_amigos.dart';
import '../tema/cores_app.dart';
import 'controles.dart';

const rotuloMeusDados = 'Meus dados';

class SeletorDados extends StatefulWidget {
  /// [soIcone] mostra só o ícone, com o texto no tooltip (celular e PC
  /// estreito).
  const SeletorDados({super.key, this.soIcone = false});

  final bool soIcone;

  @override
  State<SeletorDados> createState() => _SeletorDadosState();
}

class _SeletorDadosState extends State<SeletorDados> {
  List<String> _emails = const [];
  int? _versao;
  String? _conta;
  int _geracao = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ouve o estado: a lista muda com a mesclagem e com a conta
    final estado = Provider.of<EstadoApp>(context);
    final versao = estado.versaoDados;
    final conta = estado.conta.email;
    if (versao != _versao || conta != _conta) {
      _versao = versao;
      _conta = conta;
      unawaited(_carregar());
    }
  }

  Future<void> _carregar() async {
    final geracao = ++_geracao;
    try {
      final lista = await context.read<ServicosApp>().amigos();
      if (!mounted || geracao != _geracao) return;
      setState(() => _emails = [for (final a in lista) a.email]);
    } catch (_) {
      // sem a lista só "Meus dados" (e o amigo aberto) aparecem
    }
  }

  void _abrirMenu(EstadoApp estado) {
    final aberto = estado.amigo;
    final emails = aberto == null || _emails.contains(aberto)
        ? _emails
        : [..._emails, aberto];
    unawaited(
      abrirMenuAncorado<String?>(context, [
        itemMenu<String?>(
          null,
          rotuloMeusDados,
          marcado: aberto == null,
          aoTocar: () => unawaited(estado.trocarVisao(null)),
        ),
        for (final e in emails)
          itemMenu<String?>(
            e,
            e,
            marcado: e == aberto,
            aoTocar: () => unawaited(estado.trocarVisao(e)),
          ),
        const PopupMenuDivider(),
        itemMenu<String?>(
          null,
          'Gerenciar amigos…',
          marcado: false,
          aoTocar: () => unawaited(abrirAmigos(context)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    final aberto = estado.amigo;
    final rotulo = aberto ?? rotuloMeusDados;
    final abrir = estado.carregandoAmigo ? null : () => _abrirMenu(estado);
    if (widget.soIcone) {
      return BotaoIcone(
        icone: Icons.group,
        tooltip: rotulo,
        marcado: aberto != null,
        onPressed: abrir,
      );
    }
    return BotaoLeve(
      icone: Icons.group,
      rotulo: rotulo,
      cor: aberto == null ? null : CoresApp.de(context).aviso,
      onPressed: abrir,
    );
  }
}
