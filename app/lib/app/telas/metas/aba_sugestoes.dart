// Sugestões de alvo e stop pela volatilidade (calculadora_darf.py:3351-3490;
// android/main.py:2564-2670). Os números (ATR, stop móvel, pivôs, alerta de
// 2% do patrimônio) vêm prontos do serviço; aqui só se desenham.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'controle_metas.dart';

class PainelSugestoes extends StatelessWidget {
  const PainelSugestoes({super.key});

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
                'SUGESTÕES PARA SUAS COMPRAS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: c.textoSuave,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => unawaited(controle.recarregarSugestoes()),
                child: const Text('Atualizar'),
              ),
            ],
          ),
        ),
        if (controle.textoSug.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                controle.textoSug,
                style: TextStyle(fontSize: 12, color: c.textoSuave),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: _Corpo(controle: controle)),
      ],
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({required this.controle});

  final ControleMetas controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final v = controle.sugestoes;
    if (v == null) {
      final erro = controle.erroSug;
      if (erro == null) return const Carregando();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(erro, style: TextStyle(color: c.queda)),
            OutlinedButton(
              onPressed: () => unawaited(controle.recarregarSugestoes()),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }
    if (v.itens.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            'Nenhuma compra em aberto.',
            style: TextStyle(color: c.textoSuave),
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final s in v.itens)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CartaoSugestao(sugestao: s, controle: controle),
          ),
        for (final l in v.rodape) _Linha(l, tamanho: 11),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            avisoSugestao,
            style: TextStyle(fontSize: 10, color: c.textoSuave),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            avisoProventos,
            style: TextStyle(fontSize: 10, color: c.textoSuave),
          ),
        ),
      ],
    );
  }
}

/// Rótulo em caixa alta e valor, na cor que o núcleo indicou.
class _Linha extends StatelessWidget {
  const _Linha(this.linha, {this.tamanho = 12});

  final LinhaCard linha;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final (rotulo, valor, cor) = linha;
    final corTexto = switch (cor) {
      'accent' => c.alta,
      'danger' => c.queda,
      'aviso' => c.aviso,
      'muted' => c.textoSuave,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo.toUpperCase(),
            style: TextStyle(
              fontSize: tamanho - 1,
              fontWeight: FontWeight.bold,
              color: c.textoSuave,
            ),
          ),
          Text(
            valor,
            style: TextStyle(fontSize: tamanho, color: corTexto),
          ),
        ],
      ),
    );
  }
}

class _CartaoSugestao extends StatelessWidget {
  const _CartaoSugestao({required this.sugestao, required this.controle});

  final SugestaoPosicao sugestao;
  final ControleMetas controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final lote = sugestao.posicao.lote;
    final sug = sugestao.item.sug;
    final livre = sugestao.posicao.livre;
    final ocupado = controle.criandoSug;
    void criar(String gatilho, {bool movel = false}) => unawaited(
      controle.criarSugerido(context, sugestao, gatilho, movel: movel),
    );
    return Cartao(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            '${lote.ticker} · ${sugestao.posicao.restante} un. a '
            '${brl(lote.preco)} · compra de ${fmtData(lote.dataCompra)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(
            '$livre un. livres para metas · cálculo para ${sugestao.qtd} un.',
            style: TextStyle(fontSize: 12, color: c.textoSuave),
          ),
          for (final l in linhasCard(sugestao.item)) _Linha(l),
          if (sug != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton(
                    onPressed: ocupado ? null : () => criar('alvo'),
                    child: const Text('Criar meta de alvo'),
                  ),
                  OutlinedButton(
                    onPressed: ocupado || !sug.stopValido
                        ? null
                        : () => criar('stop'),
                    child: const Text('Criar stop fixo'),
                  ),
                  if (sug.modo == 'swing' && sug.movelDisponivel)
                    OutlinedButton(
                      onPressed: ocupado || !sug.stopValido
                          ? null
                          : () => criar('stop', movel: true),
                      child: const Text('Criar stop móvel'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
