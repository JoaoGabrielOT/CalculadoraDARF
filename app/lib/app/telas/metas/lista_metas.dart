// Lista das metas com "Verificar agora" (calculadora_darf.py:3659-3720;
// android/main.py:2514-2530, 2704-2722).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'controle_metas.dart';

/// Cabeçalho (METAS e Verificar agora), linha de status e as metas, da mais
/// nova para a mais antiga (a ordem vem do serviço). Rola sozinha.
class ListaMetas extends StatelessWidget {
  const ListaMetas({super.key});

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleMetas>();
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Text(
                'METAS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: c.textoSuave,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: controle.verificando
                    ? null
                    : () => unawaited(controle.verificarAgora()),
                child: const Text('Verificar agora'),
              ),
            ],
          ),
        ),
        if (controle.textoVerif.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                controle.textoVerif,
                style: TextStyle(fontSize: 12, color: c.textoSuave),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: _Corpo(controle: controle, visao: controle.visao),
        ),
      ],
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({required this.controle, required this.visao});

  final ControleMetas controle;
  final VisaoMetas? visao;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final v = visao;
    if (v == null) {
      final erro = controle.erro;
      if (erro == null) return const Carregando();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(erro, style: TextStyle(color: c.queda)),
            OutlinedButton(
              onPressed: () => unawaited(controle.recarregar()),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }
    if (v.metas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            'Nenhuma meta criada.',
            style: TextStyle(color: c.textoSuave),
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final m in v.metas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CartaoMeta(
              meta: m,
              descricao: v.descricoes[m.id] ?? descricao(m, todas: v.metas),
              aoCancelar: () => unawaited(controle.cancelar(context, m.id)),
            ),
          ),
      ],
    );
  }
}

class _CartaoMeta extends StatelessWidget {
  const _CartaoMeta({
    required this.meta,
    required this.descricao,
    required this.aoCancelar,
  });

  final Meta meta;
  final DescricaoMeta descricao;
  final VoidCallback aoCancelar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cor = switch (descricao.cor) {
      'accent' => c.alta,
      'danger' => c.queda,
      'aviso' => c.aviso,
      _ => c.textoSuave,
    };
    return Cartao(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  descricao.titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                descricao.status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
            ],
          ),
          Text(
            descricao.detalhe,
            style: TextStyle(
              fontSize: 12,
              color: descricao.erro ? c.queda : c.textoSuave,
            ),
          ),
          if (meta.statusOuAtiva == 'ativa')
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.queda,
                  side: BorderSide(color: c.queda),
                ),
                onPressed: aoCancelar,
                child: const Text('Cancelar meta'),
              ),
            ),
        ],
      ),
    );
  }
}
