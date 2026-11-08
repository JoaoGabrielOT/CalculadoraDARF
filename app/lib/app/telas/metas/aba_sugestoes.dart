// Sugestões de saída por ativo (entrega 2.1, §9.5): lista agrupada por
// ativo, com filtros de horizonte, posições abertas e dados, e a ordenação.
// Os números vêm do núcleo (`calculo_sugestao.dart`); aqui só se desenham.
// Nada é gravado sem a confirmação do diálogo de "Criar meta de alvo e stop".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../tema/cores_app.dart';
import 'calculo_sugestao.dart';
import 'cartao_ativo.dart';
import 'controle_metas.dart';

const _rotulosOrdem = {
  OrdemSugestao.rr: 'R/R',
  OrdemSugestao.distancia: 'Distância até o alvo',
  OrdemSugestao.liquidez: 'Liquidez',
  OrdemSugestao.ticker: 'Ticker',
};

const _rotulosDados = {
  FiltroDados.todos: 'Todos',
  FiltroDados.comDados: 'Com dados',
  FiltroDados.semDados: 'Sem dados ou desatualizados',
};

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
                'SUGESTÕES DE SAÍDA POR ATIVO',
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
    final lista = controle.listaSugestoes;
    final vazia = v.ativos.isEmpty
        ? (controle.soPosicoes
              ? "Nenhuma compra em aberto. Desligue 'Só posições abertas' "
                    'para ver o radar.'
              : 'Nenhuma compra em aberto nem ticker no radar.')
        : controle.horizonte == Horizonte.dayTrade
        ? 'Nenhum ativo com compra de hoje para o filtro escolhido.'
        : 'Nenhum ativo para o filtro escolhido.';
    return ListView(
      children: [
        _Filtros(controle: controle),
        const SizedBox(height: 8),
        if (lista.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(vazia, style: TextStyle(color: c.textoSuave)),
          ),
        for (final r in lista)
          Padding(
            key: ValueKey('sug-${r.ativo.ticker}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: CartaoAtivo(resultado: r, controle: controle),
          ),
        for (final (rotulo, valor, cor) in v.rodape)
          LinhaValor(rotulo, valor, cor, tamanho: 11),
        for (final aviso in [avisoSugestao, avisoProventos, avisoGap])
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              aviso,
              style: TextStyle(fontSize: 10, color: c.textoSuave),
            ),
          ),
      ],
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({required this.controle});

  final ControleMetas controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    Widget lista<T>(
      String chave,
      String rotulo,
      T valor,
      Map<T, String> opcoes,
      ValueChanged<T> aoMudar,
    ) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Text(rotulo, style: TextStyle(fontSize: 12, color: c.textoSuave)),
        DropdownButton<T>(
          key: ValueKey(chave),
          value: valor,
          isDense: true,
          items: [
            for (final e in opcoes.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) aoMudar(v);
          },
        ),
      ],
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BotaoSegmentado<Horizonte>(
          opcoes: const [
            (Horizonte.swing, 'Swing'),
            (Horizonte.dayTrade, 'Day trade'),
          ],
          valor: controle.horizonte,
          aoMudar: controle.definirHorizonte,
        ),
        ChipFiltro(
          rotulo: 'Só posições abertas',
          selecionado: controle.soPosicoes,
          aoTocar: controle.alternarSoPosicoes,
        ),
        lista(
          'filtro-dados',
          'Dados',
          controle.filtroDados,
          _rotulosDados,
          controle.definirFiltroDados,
        ),
        lista(
          'ordem-sugestoes',
          'Ordenar por',
          controle.ordem,
          _rotulosOrdem,
          controle.definirOrdem,
        ),
      ],
    );
  }
}
