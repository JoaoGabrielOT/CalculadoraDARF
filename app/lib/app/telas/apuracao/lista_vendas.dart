// Vendas do mês: tabela no expandido (calculadora_darf.py:1389-1407, 1578-1590)
// e cartões com menu de item no compacto (android/main.py:851-859, 1019-1049).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/tabela.dart';
import '../../regras/filtros.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'barra_filtros.dart';
import 'controle_apuracao.dart';
import 'lista_lotes.dart' show CabecalhoLista, alturaTabela, estiloPerigo;

class ListaVendas extends StatelessWidget {
  const ListaVendas({super.key});

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final visao = controle.visao;
    if (visao == null) return const SizedBox.shrink();
    final todas = visao.apuracao.ops;
    final f = controle.filtroVendas;
    final itens = filtrarVendas(todas, f);
    final contagem = f.filtrado
        ? '${itens.length}/${todas.length}'
        : '${todas.length}';
    final barra = todas.isEmpty
        ? null
        : BarraFiltrosVendas(filtro: f, aoMudar: controle.definirFiltroVendas);
    final vazioTexto = todas.isEmpty
        ? 'Nenhuma venda registrada neste mês.'
        : 'Nenhuma venda para esse filtro.';
    return expandido(context)
        ? _Expandido(
            controle: controle,
            itens: itens,
            contagem: contagem,
            barra: barra,
            vazio: vazioTexto,
          )
        : _Compacto(
            controle: controle,
            itens: itens,
            contagem: contagem,
            barra: barra,
            vazio: vazioTexto,
          );
  }
}

class _Expandido extends StatelessWidget {
  const _Expandido({
    required this.controle,
    required this.itens,
    required this.contagem,
    required this.barra,
    required this.vazio,
  });

  final ControleApuracao controle;
  final List<Operacao> itens;
  final String contagem;
  final Widget? barra;
  final String vazio;

  @override
  Widget build(BuildContext context) {
    final editavel = controle.visao?.editavel ?? false;
    Color? negativo(BuildContext ctx, Operacao o) =>
        o.liquido < 0 ? CoresApp.de(ctx).queda : null;
    final colunas = <ColunaTabela<Operacao>>[
      ColunaTabela(
        titulo: 'TICKER',
        largura: .8,
        texto: (o) => o.ticker,
        chave: (o) => o.ticker,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'TIPO',
        largura: .6,
        texto: (o) => o.tipo,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'VENDA',
        largura: .95,
        alinhamento: TextAlign.center,
        texto: (o) => fmtData(o.data),
        chave: (o) => o.data,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'QTD',
        largura: .6,
        alinhamento: TextAlign.right,
        texto: (o) => '${o.qtd}',
        chave: (o) => o.qtd,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'PREÇO',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (o) => brl(o.preco),
        chave: (o) => o.preco,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'OPERAÇÃO',
        largura: 1.2,
        alinhamento: TextAlign.center,
        texto: (o) => o.regime,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'TAXAS B3',
        largura: .9,
        alinhamento: TextAlign.right,
        texto: (o) => brl(o.taxas + o.corretagem),
        chave: (o) => o.taxas + o.corretagem,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'LUCRO BRUTO',
        largura: 1.15,
        alinhamento: TextAlign.right,
        texto: (o) => brl(o.bruto),
        chave: (o) => o.bruto,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'APÓS TAXAS',
        largura: 1.15,
        alinhamento: TextAlign.right,
        texto: (o) => brl(o.liquido),
        chave: (o) => o.liquido,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'IMPOSTO',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (o) => brl(o.imposto),
        chave: (o) => o.imposto,
        cor: negativo,
      ),
    ];
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          CabecalhoLista(
            titulo: 'Vendas do mês',
            contagemKey: const Key('contagem-vendas'),
            contagem: contagem,
            acoes: [
              OutlinedButton(
                onPressed: editavel
                    ? () => controle.editarVenda(context)
                    : null,
                child: const Text('Editar venda'),
              ),
              OutlinedButton(
                style: estiloPerigo(context),
                onPressed: editavel
                    ? () => controle.excluirVenda(context)
                    : null,
                child: const Text('Excluir venda'),
              ),
            ],
          ),
          ?barra,
          SizedBox(
            height: alturaTabela(itens.length),
            child: Tabela<Operacao>(
              key: const Key('tabela-vendas'),
              colunas: colunas,
              linhas: itens,
              vazio: vazio,
              id: (o) => o.vendaId,
              selecionado: controle.vendaSelecionada,
              aoSelecionar: (o) => controle.selecionarVenda(o.vendaId),
              aoDuploClique: editavel
                  ? (o) {
                      controle.selecionarVenda(o.vendaId);
                      controle.editarVenda(context, id: o.vendaId);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Compacto extends StatelessWidget {
  const _Compacto({
    required this.controle,
    required this.itens,
    required this.contagem,
    required this.barra,
    required this.vazio,
  });

  final ControleApuracao controle;
  final List<Operacao> itens;
  final String contagem;
  final Widget? barra;
  final String vazio;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final editavel = controle.visao?.editavel ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        CabecalhoLista(
          titulo: 'Vendas do mês',
          contagemKey: const Key('contagem-vendas'),
          contagem: contagem,
        ),
        ?barra,
        if (itens.isEmpty)
          Text(vazio, style: TextStyle(color: c.textoSuave))
        else
          Column(
            spacing: 12,
            children: [
              for (final o in itens)
                _CartaoVenda(
                  key: Key('cartao-venda-${o.vendaId}'),
                  op: o,
                  controle: controle,
                  editavel: editavel,
                ),
            ],
          ),
      ],
    );
  }
}

class _CartaoVenda extends StatelessWidget {
  const _CartaoVenda({
    super.key,
    required this.op,
    required this.controle,
    required this.editavel,
  });

  final Operacao op;
  final ControleApuracao controle;
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final o = op;
    final corLiquido = o.liquido < 0
        ? c.queda
        : (o.liquido > 0 ? c.alta : null);
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      o.ticker,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Pilula(texto: o.regime),
                  ],
                ),
                Text(
                  '${fmtData(o.data)} · ${o.qtd} × ${brl(o.preco)}',
                  style: TextStyle(fontSize: 12, color: c.textoSuave),
                ),
                Text(
                  'Taxas B3: ${brl(o.taxas + o.corretagem)}',
                  style: TextStyle(fontSize: 12, color: c.textoSuave),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [
              Text(
                brl(o.liquido),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: corLiquido,
                ),
              ),
              Text(
                'Imposto: ${brl(o.imposto)}',
                style: TextStyle(fontSize: 12, color: c.textoSuave),
              ),
            ],
          ),
          if (editavel)
            PopupMenuButton<String>(
              key: Key('menu-venda-${o.vendaId}'),
              tooltip: 'Ações da venda de ${o.ticker}',
              onSelected: (v) => v == 'editar'
                  ? controle.editarVenda(context, id: o.vendaId)
                  : controle.excluirVenda(context, id: o.vendaId),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Text('Editar venda'),
                ),
                PopupMenuItem(
                  value: 'excluir',
                  child: Text(
                    'Excluir venda',
                    style: TextStyle(color: c.queda),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
