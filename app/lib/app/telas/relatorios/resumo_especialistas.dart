// Bloco "Resumo dos especialistas" da aba Relatórios: um item recolhível por
// ativo, com o consenso no título e uma linha por casa quando aberto. Só usa
// campos do JSON. Cada chave fica no próprio widget, dentro de um invólucro
// sem chave: tickers repetidos não viram chaves duplicadas entre irmãos.

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/destaques.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../tema/cores_app.dart';
import 'especialistas_ativo.dart';
import 'paleta_relatorio.dart';

const textoSemAnalise =
    'Nenhuma análise de especialista disponível para este ativo';

/// Rótulo e leitura (cor) do selo do consenso.
(String, Leitura) _seloConsenso(Consenso c) => switch (c) {
  Consenso.compra => ('Maioria compra', Leitura.positiva),
  Consenso.neutra => ('Maioria manter', Leitura.neutra),
  Consenso.venda => ('Maioria venda', Leitura.negativa),
  Consenso.dividido => ('Opiniões divididas', Leitura.mista),
  Consenso.semDados => ('Sem análise', Leitura.neutra),
};

class ResumoEspecialistas extends StatelessWidget {
  const ResumoEspecialistas(
    this.ativos, {
    super.key,
    required this.aoAbrirLink,
  });

  /// Na ordem de exibição.
  final List<AtivoRelatorio> ativos;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      const Text(
        'Resumo dos especialistas',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      for (final a in ativos) _ItemResumo(a, aoAbrirLink: aoAbrirLink),
    ],
  );
}

class _ItemResumo extends StatelessWidget {
  const _ItemResumo(this.ativo, {required this.aoAbrirLink});

  final AtivoRelatorio ativo;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = ativo;
    // Índice original na chave; itens sem dado visível ficam de fora.
    final itens = [
      for (final (i, x) in a.especialistas.itens.indexed)
        if (_temDado(x)) (i, x),
    ];
    final (rotulo, leitura) = itens.isEmpty
        ? _seloConsenso(Consenso.semDados)
        : _seloConsenso(consensoDe(a.especialistas));
    // Material (não DecoratedBox): o ListTile pinta o fundo no Material.
    return Material(
      color: c.cartao,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(c.raioCartao),
        side: BorderSide(color: c.cartaoBorda),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('resumo-esp-${a.ticker}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                a.ticker,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SeloLeitura(leitura, texto: rotulo),
            ],
          ),
          children: [
            if (itens.isEmpty)
              Text(
                textoSemAnalise,
                style: TextStyle(color: c.textoSuave, fontSize: 13),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  for (final (i, item) in itens)
                    _CasaResumo(a.ticker, i, item, aoAbrirLink: aoAbrirLink),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CasaResumo extends StatelessWidget {
  const _CasaResumo(
    this.ticker,
    this.indice,
    this.item, {
    required this.aoAbrirLink,
  });

  final String ticker;
  final int indice;
  final ItemEspecialista item;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final i = item;
    final voto = votoDoItem(i);
    // O motivo; sem ele, a recomendação.
    final detalhe = i.motivo ?? i.recomendacao;
    return Column(
      key: Key('resumo-casa-$ticker-$indice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (voto != null) seloVoto(voto),
            if (i.casa case final casa?)
              Text(
                casa,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (i.data case final d?)
              Text(
                dataCurta(d),
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
          ],
        ),
        if (detalhe != null)
          Text(detalhe, style: const TextStyle(fontSize: 13, height: 1.35)),
        if (linkSeguro(i.url) != null)
          LinkRelatorio(texto: 'Ver fonte', url: i.url, aoAbrir: aoAbrirLink),
      ],
    );
  }
}

/// Há algo a mostrar: voto, casa, data, motivo, recomendação ou link seguro.
bool _temDado(ItemEspecialista i) =>
    votoDoItem(i) != null ||
    i.casa != null ||
    i.data != null ||
    i.motivo != null ||
    i.recomendacao != null ||
    linkSeguro(i.url) != null;
