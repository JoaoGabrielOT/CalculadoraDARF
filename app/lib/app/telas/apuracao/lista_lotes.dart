// Ativos comprados: tabela no expandido (calculadora_darf.py:1360-1407,
// 1541-1576) e cartões com menu de item no compacto (android/main.py:
// 828-846, 957-1017).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/tabela.dart';
import '../../regras/filtros.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'barra_filtros.dart';
import 'controle_apuracao.dart';
import 'menu_contexto.dart';

/// Altura da tabela: até 8 linhas à vista, na altura real delas (sem faixa
/// vazia nem última linha cortada); com mais, o corpo rola e só monta as
/// linhas visíveis (`Tabela` com altura limitada é lazy). Vazia: espaço para
/// o aviso.
double alturaTabela(BuildContext context, int linhas) {
  if (linhas == 0) return 120;
  final a = alturasTabela(context);
  return a.cabecalho + math.min(linhas, 8) * a.linha;
}

/// Título da lista, contagem ("N" ou "visíveis/total" com filtro) e ações.
class CabecalhoLista extends StatelessWidget {
  const CabecalhoLista({
    super.key,
    required this.titulo,
    required this.contagemKey,
    required this.contagem,
    this.acoes = const [],
  });

  final String titulo;
  final Key contagemKey;
  final String contagem;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.chipFundo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              contagem,
              key: contagemKey,
              style: TextStyle(color: c.textoSuave, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ...acoes,
      ],
    );
  }
}

/// Botão de perigo (Excluir): texto e borda no vermelho do tema.
ButtonStyle estiloPerigo(BuildContext context) {
  final c = CoresApp.de(context);
  return OutlinedButton.styleFrom(
    foregroundColor: c.queda,
    side: BorderSide(color: c.queda),
  );
}

/// "Cotação atual · Yahoo · dd/mm hh:mm": fonte e hora da consulta, no fuso de
/// Brasília.
String textoSeloCotacao(CotacaoAtual c) {
  final h = c.hora.noFuso(fusoBrasilia);
  final d = h.data;
  return 'Cotação atual · ${c.fonte} · '
      '${d.substring(8, 10)}/${d.substring(5, 7)} ${h.horaMinuto}';
}

/// Selo da cotação atual dos ativos à vista ([ControleApuracao.tickersCotacao]):
/// vale a hora da consulta mais antiga, para nenhum valor parecer mais novo do
/// que é. Sem cotação, diz o estado em vez de mostrar valor.
class SeloCotacaoAtual extends StatelessWidget {
  const SeloCotacaoAtual({super.key});

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final tickers = controle.tickersCotacao;
    if (tickers.isEmpty) return const SizedBox.shrink();
    final chegadas = [
      for (final t in tickers)
        if (controle.cotacoes[t] != null) controle.cotacoes[t]!,
    ];
    if (chegadas.isNotEmpty) {
      final antiga = ordenadoCom(chegadas, (a, b) => a.hora.compareTo(b.hora));
      return Selo(texto: textoSeloCotacao(antiga.first));
    }
    final tentou = tickers.every(controle.cotacoes.containsKey);
    return Text(
      tentou ? 'cotação atual indisponível' : 'carregando cotação atual…',
      style: TextStyle(color: CoresApp.de(context).textoSuave, fontSize: 12),
    );
  }
}

/// Posição no fim do mês ou carteira atual (lotes do mês aberto). Na carteira
/// de outro mês que o da tela, diz de qual mês vêm os lotes.
class SeletorLista extends StatelessWidget {
  const SeletorLista({super.key});

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final c = CoresApp.de(context);
    final aberto = controle.mesAberto;
    final modo = controle.modoLista;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        BotaoSegmentado<ModoLista>(
          key: const Key('seletor-posicao'),
          opcoes: [
            (ModoLista.posicao, 'Posição em ${fmtData(controle.dataCorte)}'),
            (ModoLista.carteira, 'Carteira atual'),
          ],
          valor: modo,
          aoMudar: controle.escolherModo,
        ),
        if (modo == ModoLista.carteira &&
            aberto != null &&
            aberto != controle.mes)
          Text(
            'Lotes do mês aberto (${fmtMes(aberto)})',
            style: TextStyle(color: c.textoSuave, fontSize: 11),
          ),
        if (modo == ModoLista.carteira) const SeloCotacaoAtual(),
      ],
    );
  }
}

/// A carteira atual de outro mês ainda não chegou (ou falhou).
class _CarteiraPendente extends StatelessWidget {
  const _CarteiraPendente({required this.controle});

  final ControleApuracao controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const CabecalhoLista(
          titulo: 'Ativos comprados',
          contagemKey: Key('contagem-lotes'),
          contagem: '…',
        ),
        const SeletorLista(),
        Text(
          controle.erroCarteira ?? 'Carregando a carteira atual…',
          style: TextStyle(color: c.textoSuave),
        ),
      ],
    );
  }
}

/// Ativos comprados. [sliver] (celular) devolve um sliver com os cartões
/// montados sob demanda; sem ele, o cartão com tabela do layout expandido.
class ListaLotes extends StatelessWidget {
  const ListaLotes({super.key, this.sliver = false});

  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final visao = controle.visaoLotes;
    if (visao == null) {
      if (controle.visao == null) {
        return sliver
            ? const SliverToBoxAdapter(child: SizedBox.shrink())
            : const SizedBox.shrink();
      }
      final pendente = _CarteiraPendente(controle: controle);
      return sliver
          ? SliverToBoxAdapter(child: pendente)
          : Cartao(child: pendente);
    }
    final todos = visao.dados.lotes;
    final f = controle.filtroLotes;
    final itens = filtrarLotes(todos, f, (t) => controle.precos[t]);
    final contagem = f.filtrado
        ? '${itens.length}/${todos.length}'
        : '${todos.length}';
    final barra = todos.isEmpty
        ? null
        : BarraFiltrosLotes(
            filtro: f,
            aoMudar: controle.definirFiltroLotes,
            segmentada: !sliver,
          );
    return sliver
        ? _Compacto(
            controle: controle,
            itens: itens,
            vazio: todos.isEmpty,
            contagem: contagem,
            barra: barra,
          )
        : _Expandido(
            controle: controle,
            itens: itens,
            vazio: todos.isEmpty,
            contagem: contagem,
            barra: barra,
          );
  }
}

/// Preço atual de uma compra: "…" até chegar, "—" sem cotação ou vendida.
String _textoAtual(Lote l, Map<String, double?> precos) {
  if (restante(l) == 0) return '—';
  final p = precos[l.ticker];
  if (p != null && p != 0) return brl(p);
  return precos.containsKey(l.ticker) ? '—' : '…';
}

double? _precoAberto(Lote l, Map<String, double?> precos) =>
    restante(l) > 0 ? precos[l.ticker] : null;

String _setaResultado((double, double)? res) => res != null && res.$1 > 0.004
    ? '▲ '
    : res != null && res.$1 < -0.004
    ? '▼ '
    : '';

Color? _corResultado(CoresApp c, (double, double)? res) =>
    res == null || res.$1.abs() <= 0.004
    ? null
    : (res.$1 > 0 ? c.alta : c.queda);

class _Expandido extends StatelessWidget {
  const _Expandido({
    required this.controle,
    required this.itens,
    required this.vazio,
    required this.contagem,
    required this.barra,
  });

  final ControleApuracao controle;
  final List<Lote> itens;
  final bool vazio;
  final String contagem;
  final Widget? barra;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final editavel = controle.visaoLotes?.editavel ?? false;
    final livre = editavel && !controle.gravando;
    final precos = controle.precos;
    Color? mudo(BuildContext ctx, Lote l) =>
        restante(l) == 0 ? CoresApp.de(ctx).textoSuave : null;
    final colunas = <ColunaTabela<Lote>>[
      ColunaTabela(
        titulo: 'TICKER',
        largura: .9,
        texto: (l) => l.ticker,
        chave: (l) => l.ticker,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'TIPO',
        largura: .7,
        texto: (l) => l.tipo,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'COMPRA',
        largura: 1,
        alinhamento: TextAlign.center,
        texto: (l) => fmtData(l.dataCompra),
        chave: (l) => l.dataCompra,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'QTD',
        largura: .6,
        alinhamento: TextAlign.right,
        texto: (l) => '${l.qtd}',
        chave: (l) => l.qtd,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'PREÇO',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (l) => brl(l.preco),
        chave: (l) => l.preco,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'ATUAL',
        largura: 1,
        alinhamento: TextAlign.right,
        texto: (l) => _textoAtual(l, precos),
        chave: (l) {
          final p = _precoAberto(l, precos);
          return p == null || p == 0 ? double.negativeInfinity : p;
        },
        cor: mudo,
      ),
      // logo depois do preço atual: o resultado fica à vista sem rolar
      ColunaTabela(
        titulo: 'GANHO/PERDA',
        largura: 1.75,
        alinhamento: TextAlign.right,
        texto: (l) {
          final res = resultadoAberto(l, _precoAberto(l, precos));
          return '${_setaResultado(res)}${fmtResultado(res)}';
        },
        chave: (l) =>
            resultadoAberto(l, _precoAberto(l, precos))?.$1 ??
            double.negativeInfinity,
        cor: (ctx, l) => _corResultado(
          CoresApp.de(ctx),
          resultadoAberto(l, _precoAberto(l, precos)),
        ),
      ),
      ColunaTabela(
        titulo: 'TOTAL',
        largura: 1.15,
        alinhamento: TextAlign.right,
        texto: (l) => brl(l.qtd * l.preco),
        chave: (l) => l.qtd * l.preco,
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'VENDIDA',
        largura: .75,
        alinhamento: TextAlign.right,
        texto: (l) => '${vendido(l)}',
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'RESTANTE',
        largura: .95,
        alinhamento: TextAlign.right,
        texto: (l) => '${restante(l)}',
        chave: (l) => restante(l),
        cor: mudo,
      ),
      ColunaTabela(
        titulo: 'SITUAÇÃO',
        largura: 1.2,
        alinhamento: TextAlign.center,
        texto: statusLote,
        cor: mudo,
      ),
    ];
    final vazioTexto = vazio
        ? 'Nenhum ativo neste mês. Clique em  +  Novo ativo  para começar.'
        : 'Nenhum ativo para esse filtro.';
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          CabecalhoLista(
            titulo: 'Ativos comprados',
            contagemKey: const Key('contagem-lotes'),
            contagem: contagem,
            acoes: [
              FilledButton(
                onPressed: livre ? () => controle.novaCompra(context) : null,
                child: const Text('+  Novo ativo'),
              ),
              OutlinedButton(
                onPressed: livre
                    ? () => controle.registrarVenda(context)
                    : null,
                child: const Text('Registrar venda'),
              ),
              OutlinedButton(
                onPressed: livre ? () => controle.editarLote(context) : null,
                child: const Text('Editar'),
              ),
              OutlinedButton(
                style: estiloPerigo(context),
                onPressed: livre ? () => controle.excluirLote(context) : null,
                child: const Text('Excluir'),
              ),
            ],
          ),
          const SeletorLista(),
          ?barra,
          Text(
            'Clique nos títulos das colunas para ordenar',
            style: TextStyle(color: c.textoSuave, fontSize: 11),
          ),
          SizedBox(
            height: alturaTabela(context, itens.length),
            child: Tabela<Lote>(
              key: const Key('tabela-lotes'),
              reiniciarOrdem: (
                controle.filtroLotes.ordem,
                controle.filtroLotes.desc,
              ),
              colunas: colunas,
              linhas: itens,
              vazio: vazioTexto,
              id: (l) => l.id,
              selecionado: controle.loteSelecionado,
              aoSelecionar: (l) => controle.selecionarLote(l.id),
              aoClicarDireito: (l, posicao) {
                controle.selecionarLote(l.id);
                unawaited(
                  abrirMenuApuracao(
                    context,
                    posicao,
                    alvo: AlvoMenu(
                      ticker: l.ticker,
                      cabecalho: '${l.ticker} · ${l.qtd} un. · ${brl(l.preco)}',
                      lote: l,
                    ),
                  ),
                );
              },
              aoDuploClique: editavel
                  ? (l) {
                      controle.selecionarLote(l.id);
                      controle.registrarVenda(context, lote: l);
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
    required this.vazio,
    required this.contagem,
    required this.barra,
  });

  final ControleApuracao controle;
  final List<Lote> itens;
  final bool vazio;
  final String contagem;
  final Widget? barra;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final editavel = controle.visaoLotes?.editavel ?? false;
    final cabecalho = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Row(
          children: [
            Expanded(
              child: CabecalhoLista(
                titulo: 'Ativos comprados',
                contagemKey: const Key('contagem-lotes'),
                contagem: contagem,
              ),
            ),
            if (editavel)
              OutlinedButton.icon(
                onPressed: controle.gravando
                    ? null
                    : () => controle.registrarVenda(context),
                icon: const Icon(Icons.sell),
                label: const Text('Registrar venda'),
              ),
          ],
        ),
        const SeletorLista(),
        ?barra,
      ],
    );
    final Widget corpo;
    if (itens.isNotEmpty) {
      corpo = SliverPadding(
        padding: const EdgeInsets.only(top: 12),
        sliver: SliverList.separated(
          itemCount: itens.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _CartaoLote(
            key: Key('cartao-lote-${itens[i].id}'),
            lote: itens[i],
            controle: controle,
            editavel: editavel,
          ),
        ),
      );
    } else if (vazio) {
      corpo = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            spacing: 10,
            children: [
              Icon(Icons.inventory_2_outlined, size: 40, color: c.textoSuave),
              const Text(
                'Nenhuma compra neste mês',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                'Cadastre a primeira compra para começar.',
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
              if (editavel)
                FilledButton.icon(
                  onPressed: controle.gravando
                      ? null
                      : () => controle.novaCompra(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova compra'),
                ),
            ],
          ),
        ),
      );
    } else {
      corpo = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: Text(
              'Nenhum ativo para esse filtro.',
              style: TextStyle(color: c.textoSuave),
            ),
          ),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: cabecalho),
        corpo,
      ],
    );
  }
}

class _CartaoLote extends StatelessWidget {
  const _CartaoLote({
    super.key,
    required this.lote,
    required this.controle,
    required this.editavel,
  });

  final Lote lote;
  final ControleApuracao controle;
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final l = lote;
    final st = statusLote(l);
    final corStatus = st == 'Vendido'
        ? c.textoSuave
        : (st == 'Vendido parcial' ? c.aviso : c.alta);
    Widget atual = const SizedBox.shrink();
    if (restante(l) > 0) {
      final preco = controle.precos[l.ticker];
      final res = resultadoAberto(l, preco);
      if (preco != null && preco != 0) {
        atual = Wrap(
          spacing: 6,
          children: [
            Text(
              'Atual: ${brl(preco)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_setaResultado(res)}${fmtResultado(res)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _corResultado(c, res),
              ),
            ),
          ],
        );
      } else {
        atual = Text(
          controle.precos.containsKey(l.ticker)
              ? 'Atual: sem cotação'
              : 'Atual: carregando…',
          style: TextStyle(fontSize: 12, color: c.textoSuave),
        );
      }
    }
    return Cartao(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
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
                      l.ticker,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Pilula(texto: l.tipo),
                  ],
                ),
                Text(
                  // espaço inseparável: o preço não quebra entre "R$" e o valor
                  '${fmtData(l.dataCompra)} · ${l.qtd} × '
                  '${brl(l.preco).replaceAll(' ', ' ')}',
                  style: TextStyle(fontSize: 12, color: c.textoSuave),
                ),
                atual,
                Text(
                  st,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: corStatus,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [
              Text(
                brl(l.qtd * l.preco),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Restante: ${restante(l)}',
                style: TextStyle(fontSize: 12, color: c.textoSuave),
              ),
            ],
          ),
          if (editavel)
            PopupMenuButton<String>(
              key: Key('menu-lote-${l.id}'),
              enabled: !controle.gravando,
              tooltip: 'Ações de ${l.ticker}',
              onSelected: (v) => switch (v) {
                'vender' => controle.registrarVenda(context, lote: l),
                'editar' => controle.editarLote(context, id: l.id),
                _ => controle.excluirLote(context, id: l.id),
              },
              itemBuilder: (_) => [
                if (restante(l) > 0)
                  const PopupMenuItem(
                    value: 'vender',
                    child: Text('Registrar venda'),
                  ),
                const PopupMenuItem(
                  value: 'editar',
                  child: Text('Editar compra'),
                ),
                PopupMenuItem(
                  value: 'excluir',
                  child: Text(
                    'Excluir compra',
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
