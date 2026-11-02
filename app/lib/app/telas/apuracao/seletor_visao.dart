// "Visualizando": meus dados ou os de um amigo (calculadora_darf.py:2933-2950;
// usado também no Caixa e no Radar). Desabilitado enquanto os dados do amigo
// carregam.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../estado/estado_app.dart';
import '../../servicos/api.dart';

const rotuloMeusDados = 'Meus dados';

class SeletorVisao extends StatefulWidget {
  const SeletorVisao({super.key, this.largura = 280});

  final double largura;

  @override
  State<SeletorVisao> createState() => _SeletorVisaoState();
}

class _SeletorVisaoState extends State<SeletorVisao> {
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

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    final aberto = estado.amigo;
    final emails = aberto == null || _emails.contains(aberto)
        ? _emails
        : [..._emails, aberto];
    return SizedBox(
      width: widget.largura,
      child: DropdownButton<String>(
        isExpanded: true,
        value: aberto ?? rotuloMeusDados,
        items: [
          const DropdownMenuItem(
            value: rotuloMeusDados,
            child: Text(rotuloMeusDados),
          ),
          for (final e in emails)
            DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: estado.carregandoAmigo
            ? null
            : (v) => unawaited(
                estado.trocarVisao(v == rotuloMeusDados ? null : v),
              ),
      ),
    );
  }
}
