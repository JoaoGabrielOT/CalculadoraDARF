// Vendas do mês: tabela no expandido (calculadora_darf.py:1389-1407, 1578-1590)
// e cartões com menu de item no compacto (android/main.py:851-859, 1019-1049).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/tabela.dart';
import '../../regras/filtros.dart';
import '../../tema/cores_app.dart';
import 'barra_filtros.dart';
import 'controle_apuracao.dart';
import 'lista_lotes.dart' show CabecalhoLista, alturaTabela, estiloPerigo;

/// Vendas do mês; [sliver] como em `ListaLotes`.
class ListaVendas extends StatelessWidget {
  const ListaVendas({super.key, this.sliver = false});

  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final visao = controle.visao;
    if (visao == null) {
      return sliver
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : const SizedBox.shrink();
    }
    final todas = visao.apuracao.ops;
    final f = controle.filtroVendas;
    final itens = agruparVendas(filtrarVendas(todas, f));
    final total = agruparVendas(todas).length;
    final contagem = f.filtrado ? '${itens.length}/$total' : '$total';
    final barra = todas.isEmpty
        ? null
        : BarraFiltrosVendas(filtro: f, aoMudar: controle.definirFiltroVendas);
    final vazioTexto = todas.isEmpty
        ? 'Nenhuma venda registrada neste mês.'
        : 'Nenhuma venda para esse filtro.';
    return sliver
        ? _Compacto(
            controle: controle,
            itens: itens,
            contagem: contagem,
            barra: barra,
            vazio: vazioTexto,
          )
        : _Expandido(
            controle: controle,
            itens: itens,
            contagem: contagem,
            barra: barra,
            vazio: vazioTexto,
          );
  }
}

class _Expandido extends StatefulWidget {
  const _Expandido({
    required this.controle,
    required this.itens,
    required this.contagem,
    required this.barra,
    required this.vazio,
  });

  final ControleApuracao controle;
  final List<GrupoVenda> itens;
  final String contagem;
  final Widget? barra;
  final String vazio;

  @override
  State<_Expandido> createState() => _ExpandidoState();
}

class _ExpandidoState extends State<_Expandido> {
  /// Grupos abertos (id do grupo).
  final _abertos = <String>{};

  @override
  Widget build(BuildContext context) {
    final controle = widget.controle;
    final itens = widget.itens;
    final editavel = controle.visao?.editavel ?? false;
    final livre = editavel && !controle.gravando;
    Color? negativo(BuildContext ctx, GrupoVenda g) =>
        g.op.liquido < 0 ? CoresApp.de(ctx).queda : null;
    String ticker(GrupoVenda g) {
      if (g.filha) return '   ↳ ${g.op.ticker}';
      if (!g.agrupado) return g.op.ticker;
      return '${_abertos.contains(g.op.vendaId) ? '▾' : '▸'} ${g.op.ticker}';
    }

    final colunas = <ColunaTabela<GrupoVenda>>[
      ColunaTabela(
        titulo: 'TICKER',
        largura: .8,
        texto: ticker,
        chave: (g) => g.op.ticker,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'TIPO',
        largura: .6,
        texto: (g) => g.op.tipo,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'VENDA',
        largura: .95,
        alinhamento: TextAlign.center,
        texto: (g) => fmtData(g.op.data),
        chave: (g) => g.op.data,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'QTD',
        largura: .6,
        alinhamento: TextAlign.right,
        texto: (g) => '${g.op.qtd}',
        chave: (g) => g.op.qtd,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'PREÇO',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (g) => brl(g.op.preco),
        chave: (g) => g.op.preco,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'OPERAÇÃO',
        largura: 1.2,
        alinhamento: TextAlign.center,
        texto: (g) => g.op.regime,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'TAXAS B3',
        largura: .9,
        alinhamento: TextAlign.right,
        texto: (g) => brl(g.op.taxas + g.op.corretagem),
        chave: (g) => g.op.taxas + g.op.corretagem,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'LUCRO BRUTO',
        largura: 1.15,
        alinhamento: TextAlign.right,
        texto: (g) => brl(g.op.bruto),
        chave: (g) => g.op.bruto,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'APÓS TAXAS',
        largura: 1.15,
        alinhamento: TextAlign.right,
        texto: (g) => brl(g.op.liquido),
        chave: (g) => g.op.liquido,
        cor: negativo,
      ),
      ColunaTabela(
        titulo: 'IMPOSTO',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (g) => brl(g.op.imposto),
        chave: (g) => g.op.imposto,
        cor: negativo,
      ),
    ];
    final linhasVisiveis = itens.fold<int>(
      0,
      (s, g) => s + 1 + (_abertos.contains(g.op.vendaId) ? g.partes.length : 0),
    );
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          CabecalhoLista(
            titulo: 'Vendas do mês',
            contagemKey: const Key('contagem-vendas'),
            contagem: widget.contagem,
            acoes: [
              OutlinedButton(
                onPressed: livre ? () => controle.editarVenda(context) : null,
                child: const Text('Editar venda'),
              ),
              OutlinedButton(
                style: estiloPerigo(context),
                onPressed: livre ? () => controle.excluirVenda(context) : null,
                child: const Text('Excluir venda'),
              ),
            ],
          ),
          ?widget.barra,
          SizedBox(
            height: alturaTabela(context, linhasVisiveis),
            child: Tabela<GrupoVenda>(
              key: const Key('tabela-vendas'),
              reiniciarOrdem: (
                controle.filtroVendas.ordem,
                controle.filtroVendas.desc,
              ),
              colunas: colunas,
              linhas: itens,
              vazio: widget.vazio,
              id: (g) => g.op.vendaId,
              filhas: (g) => [
                for (final p in g.partes) GrupoVenda(p, [p], filha: true),
              ],
              expandidas: _abertos,
              selecionado: controle.vendaSelecionada,
              aoSelecionar: (g) {
                controle.selecionarVenda(grupoDe(g.op.vendaId));
                if (g.agrupado) {
                  setState(() {
                    if (!_abertos.remove(g.op.vendaId)) {
                      _abertos.add(g.op.vendaId);
                    }
                  });
                }
              },
              aoDuploClique: editavel
                  ? (g) {
                      controle.selecionarVenda(grupoDe(g.op.vendaId));
                      controle.editarVenda(context, id: g.op.vendaId);
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
  final List<GrupoVenda> itens;
  final String contagem;
  final Widget? barra;
  final String vazio;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final editavel = controle.visao?.editavel ?? false;
    final Widget corpo = itens.isEmpty
        ? SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(vazio, style: TextStyle(color: c.textoSuave)),
            ),
          )
        : SliverPadding(
            padding: const EdgeInsets.only(top: 12),
            sliver: SliverList.separated(
              itemCount: itens.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _CartaoVenda(
                key: Key('cartao-venda-${itens[i].op.vendaId}'),
                grupo: itens[i],
                controle: controle,
                editavel: editavel,
              ),
            ),
          );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              CabecalhoLista(
                titulo: 'Vendas do mês',
                contagemKey: const Key('contagem-vendas'),
                contagem: contagem,
              ),
              ?barra,
            ],
          ),
        ),
        corpo,
      ],
    );
  }
}

class _CartaoVenda extends StatefulWidget {
  const _CartaoVenda({
    super.key,
    required this.grupo,
    required this.controle,
    required this.editavel,
  });

  final GrupoVenda grupo;
  final ControleApuracao controle;
  final bool editavel;

  @override
  State<_CartaoVenda> createState() => _CartaoVendaState();
}

class _CartaoVendaState extends State<_CartaoVenda> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final controle = widget.controle;
    final grupo = widget.grupo;
    final o = grupo.op;
    final corLiquido = o.liquido < 0
        ? c.queda
        : (o.liquido > 0 ? c.alta : null);
    final detalhes = grupo.agrupado && _aberto;
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
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
              if (widget.editavel)
                PopupMenuButton<String>(
                  key: Key('menu-venda-${o.vendaId}'),
                  enabled: !controle.gravando,
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
          if (grupo.agrupado)
            TextButton.icon(
              key: Key('expandir-venda-${o.vendaId}'),
              onPressed: () => setState(() => _aberto = !_aberto),
              icon: Icon(detalhes ? Icons.expand_less : Icons.expand_more),
              label: Text(
                detalhes
                    ? 'Ocultar as ${grupo.partes.length} compras'
                    : 'Ver as ${grupo.partes.length} compras',
              ),
            ),
          if (detalhes)
            for (final p in grupo.partes)
              Padding(
                key: Key('parte-venda-${p.vendaId}'),
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${p.qtd} × ${brl(p.preco)} · ${p.regime}',
                        style: TextStyle(fontSize: 12, color: c.textoSuave),
                      ),
                    ),
                    Text(
                      brl(p.liquido),
                      style: TextStyle(
                        fontSize: 12,
                        color: p.liquido < 0 ? c.queda : null,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
