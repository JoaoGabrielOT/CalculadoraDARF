// Ativos comprados em "Posição em dd/mm/aaaa": por ativo, quantidade, preço
// médio, cotação e resultado em aberto; aberto, os cartões, o realizado e as
// compras em "Mais detalhes". Só leitura: ver uma posição não gera venda,
// resultado nem imposto. A cotação atual só aparece no corte de hoje, com
// fonte e hora; num mês passado não há cotação.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/sinal.dart';
import '../../regras/apresentacao.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'controle_apuracao.dart';
import 'lista_lotes.dart';
import 'painel_indicadores.dart';

const textoCotacaoHistorica = 'cotação histórica não disponível';
const textoCustoPorCompra = 'custo por compra';

/// A seção "Ativos comprados": a posição no fim do mês ou a carteira atual,
/// conforme o seletor.
class ListaAtivos extends StatelessWidget {
  const ListaAtivos({super.key, this.sliver = false});

  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final modo = context.select<ControleApuracao, ModoLista>(
      (c) => c.modoLista,
    );
    if (modo == ModoLista.carteira) return ListaLotes(sliver: sliver);
    return ListaPosicoes(sliver: sliver);
  }
}

class ListaPosicoes extends StatelessWidget {
  const ListaPosicoes({super.key, this.sliver = false});

  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    if (controle.visao == null) {
      return sliver
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : const SizedBox.shrink();
    }
    final p = controle.posicoes;
    final itens = p?.posicoes ?? const <PosicaoAtivo>[];
    final cabecalho = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        CabecalhoLista(
          titulo: 'Ativos comprados',
          contagemKey: const Key('contagem-posicoes'),
          contagem: p == null ? '…' : '${itens.length}',
        ),
        const SeletorLista(),
        _Cotacao(controle: controle),
      ],
    );
    final Widget aviso = Text(
      controle.erroPosicoes ??
          (p == null
              ? 'Carregando a posição…'
              : 'Nenhum ativo em aberto em ${fmtData(p.dataCorte)}.'),
      style: TextStyle(color: CoresApp.de(context).textoSuave),
    );
    if (sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: cabecalho),
          if (itens.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(child: aviso),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 12),
              sliver: SliverList.separated(
                itemCount: itens.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _LinhaAtivo(
                  key: Key('ativo-${itens[i].ticker}'),
                  ativo: itens[i],
                  indicadores: _indicadorDe(controle, itens[i].ticker),
                  corrente: p!.corrente,
                  cotacao: p.corrente ? controle.cotacoes : null,
                  compacto: true,
                ),
              ),
            ),
        ],
      );
    }
    return Cartao(
      key: const Key('lista-posicoes'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          cabecalho,
          if (itens.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: aviso,
            )
          else
            // largura limitada: com a área rolando na horizontal (< 1200 px)
            // as colunas não se perdem além da borda
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Titulos(),
                  for (final a in itens)
                    _LinhaAtivo(
                      key: Key('ativo-${a.ticker}'),
                      ativo: a,
                      indicadores: _indicadorDe(controle, a.ticker),
                      corrente: p!.corrente,
                      cotacao: p.corrente ? controle.cotacoes : null,
                      compacto: false,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

IndicadoresAtivo? _indicadorDe(ControleApuracao controle, String ticker) {
  for (final i in controle.indicadores) {
    if (i.ticker == ticker) return i;
  }
  return null;
}

/// Situação da cotação: histórica não existe; a atual leva fonte e hora.
class _Cotacao extends StatelessWidget {
  const _Cotacao({required this.controle});

  final ControleApuracao controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final p = controle.posicoes;
    if (p == null) return const SizedBox.shrink();
    if (!p.corrente) {
      return Text(
        textoCotacaoHistorica,
        style: TextStyle(color: c.textoSuave, fontSize: 12),
      );
    }
    return const SeloCotacaoAtual();
  }
}

const _flex = [1.0, .6, 1.0, 1.0, 1.9];

class _Titulos extends StatelessWidget {
  const _Titulos();

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    Widget t(String texto, double flex, {bool direita = true}) => Expanded(
      flex: (flex * 100).round(),
      child: Text(
        texto,
        textAlign: direita ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: c.textoSuave,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 8, 0),
      child: Row(
        children: [
          t('TICKER', _flex[0], direita: false),
          t('QTD', _flex[1]),
          t('PREÇO MÉDIO', _flex[2]),
          t('COTAÇÃO', _flex[3]),
          t('RESULTADO EM ABERTO', _flex[4]),
        ],
      ),
    );
  }
}

/// Um ativo da posição: a linha resume quantidade, preço médio, cotação e o
/// resultado em aberto; o toque abre os cartões, o realizado e, em "Mais
/// detalhes", as compras e a lista longa dos indicadores.
class _LinhaAtivo extends StatefulWidget {
  const _LinhaAtivo({
    super.key,
    required this.ativo,
    required this.cotacao,
    required this.compacto,
    required this.indicadores,
    required this.corrente,
  });

  final PosicaoAtivo ativo;
  final IndicadoresAtivo? indicadores;
  final bool corrente;

  /// Cotações atuais por ticker; nulo quando o corte não é hoje.
  final Map<String, CotacaoAtual?>? cotacao;
  final bool compacto;

  @override
  State<_LinhaAtivo> createState() => _LinhaAtivoState();
}

class _LinhaAtivoState extends State<_LinhaAtivo> {
  bool _aberto = false;
  bool _detalhes = false;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = widget.ativo;
    final ind = widget.indicadores;
    final cotacoes = widget.cotacao;
    final preco = cotacoes?[a.ticker]?.preco;
    // "…" só enquanto a cotação de hoje não voltou; sem ela, "—"
    final esperando =
        cotacoes != null && preco == null && !cotacoes.containsKey(a.ticker);
    final semValor = esperando ? '…' : '—';
    final medio = a.precoMedio;
    final custo = ind?.custoRemanescente ?? a.custoFiscal ?? a.custoGerencial;
    final valor = valorAtual(a.qtd, preco);
    final emAberto = valor == null ? null : arredondar(valor - custo, 2);
    final textoAberto = emAberto == null
        ? semValor
        : textoResultado(emAberto, pctSobre(emAberto, custo));
    final corAberto = c.doValor(emAberto);
    final textoCotacao = preco == null ? semValor : brl(preco);
    final seta = Icon(
      _aberto ? Icons.expand_less : Icons.expand_more,
      size: 20,
      color: c.textoSuave,
    );
    final expandido = _Expandido(
      ativo: a,
      indicadores: ind,
      corrente: widget.corrente,
      cotacoes: cotacoes ?? const {},
      compacto: widget.compacto,
      custo: custo,
      valor: valor == null ? semValor : brl(valor),
      emAberto: textoAberto,
      corAberto: corAberto,
      detalhes: _detalhes,
      alternarDetalhes: () => setState(() => _detalhes = !_detalhes),
    );
    final corpo = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: _aberto ? expandido : const SizedBox(width: double.infinity),
    );
    if (widget.compacto) {
      return Cartao(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _aberto = !_aberto),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Text(
                        a.ticker,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Pilula(texto: a.tipo),
                      Expanded(
                        child: Text(
                          textoAberto,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: corAberto,
                          ),
                        ),
                      ),
                      seta,
                    ],
                  ),
                  Text(
                    '${a.qtd} un. · PM ${medio == null ? '—' : brl(medio)}'
                    ' · cotação $textoCotacao',
                    style: TextStyle(fontSize: 12, color: c.textoSuave),
                  ),
                ],
              ),
            ),
            corpo,
          ],
        ),
      );
    }
    Widget col(String texto, double flex, {bool direita = true, Color? cor}) =>
        Expanded(
          flex: (flex * 100).round(),
          child: Text(
            texto,
            textAlign: direita ? TextAlign.right : TextAlign.left,
            style: cor == null
                ? null
                : TextStyle(color: cor, fontWeight: FontWeight.bold),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: c.linha),
        InkWell(
          onTap: () => setState(() => _aberto = !_aberto),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                SizedBox(width: 24, child: seta),
                Expanded(
                  flex: (_flex[0] * 100).round(),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        a.ticker,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        a.tipo,
                        style: TextStyle(fontSize: 11, color: c.textoSuave),
                      ),
                    ],
                  ),
                ),
                col('${a.qtd}', _flex[1]),
                col(medio == null ? '—' : brl(medio), _flex[2]),
                col(textoCotacao, _flex[3]),
                col(textoAberto, _flex[4], cor: corAberto),
              ],
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(32, 0, 8, 0), child: corpo),
      ],
    );
  }
}

/// O ativo aberto: quatro cartões (2×2 no celular), o realizado do mês e o
/// acumulado e, em "Mais detalhes", as compras e o restante dos indicadores.
class _Expandido extends StatelessWidget {
  const _Expandido({
    required this.ativo,
    required this.indicadores,
    required this.corrente,
    required this.cotacoes,
    required this.compacto,
    required this.custo,
    required this.valor,
    required this.emAberto,
    required this.corAberto,
    required this.detalhes,
    required this.alternarDetalhes,
  });

  final PosicaoAtivo ativo;
  final IndicadoresAtivo? indicadores;
  final bool corrente;
  final Map<String, CotacaoAtual?> cotacoes;
  final bool compacto;
  final double custo;
  final String valor;
  final String emAberto;
  final Color? corAberto;
  final bool detalhes;
  final VoidCallback alternarDetalhes;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = ativo;
    final i = indicadores;
    final pe = i?.pontoEquilibrio;
    String dica(String id) => i == null ? '' : formulaIndicador(i, id);
    final cartoes = [
      _MiniCartao('Investido', brl(custo), dica: dica('custo')),
      _MiniCartao('Valor atual', valor, dica: 'Quantidade × cotação atual.'),
      _MiniCartao(
        'Em aberto',
        emAberto,
        cor: corAberto,
        dica: dica('naoRealizado'),
      ),
      _MiniCartao(
        'Equilíbrio',
        pe == null ? '—' : brl(pe),
        dica: dica('equilibrio'),
      ),
    ];
    Widget linha(List<Widget> filhos) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [for (final f in filhos) Expanded(child: f)],
      ),
    );
    final grade = Column(
      key: Key('cartoes-${a.ticker}'),
      spacing: 8,
      children: compacto
          ? [linha(cartoes.sublist(0, 2)), linha(cartoes.sublist(2))]
          : [linha(cartoes)],
    );
    final suave = TextStyle(fontSize: 12, color: c.textoSuave);
    Widget realizado(String rotulo, String texto, double v, {String? info}) =>
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(rotulo, style: suave),
                  if (info != null)
                    Tooltip(
                      message: info,
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: c.textoSuave,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              texto,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: c.doValor(v),
              ),
            ),
          ],
        );
    final rent = i?.rentabilidadeRealizada;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          grade,
          if (i != null) ...[
            realizado(
              'Realizado no mês',
              textoResultado(i.resultadoMes, rent == null ? null : rent * 100),
              i.resultadoMes,
              info:
                  'Resultado: ${rotuloMetodo(i)}. Custo remanescente: '
                  '${i.custoPorCompra ? 'por compra' : 'fiscal'}.',
            ),
            realizado(
              'Acumulado desde ${i.desde}',
              textoResultado(i.resultadoAcumulado, null),
              i.resultadoAcumulado,
            ),
          ],
          InkWell(
            key: Key('detalhes-${a.ticker}'),
            onTap: alternarDetalhes,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                spacing: 4,
                children: [
                  Icon(
                    detalhes ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: c.textoSuave,
                  ),
                  Text(
                    'Mais detalhes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: c.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: !detalhes
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      Text(
                        'Tipo: ${a.tipo}'
                        '${a.custoPorCompra ? ' · $textoCustoPorCompra' : ''}',
                        style: suave,
                      ),
                      _Compras(ativo: a, key: Key('compras-${a.ticker}')),
                      if (i != null)
                        PainelIndicadores(
                          indicadores: i,
                          corrente: corrente,
                          cotacoes: cotacoes,
                          ocultar: idsResumo,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Cartão pequeno: rótulo e valor à direita, com a fórmula na dica.
class _MiniCartao extends StatelessWidget {
  const _MiniCartao(this.titulo, this.valor, {this.cor, this.dica = ''});

  final String titulo;
  final String valor;
  final Color? cor;
  final String dica;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final conteudo = DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.textoSuave.withValues(alpha: .07), c.cartao),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Text(titulo, style: TextStyle(fontSize: 11, color: c.textoSuave)),
            Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
    return dica.isEmpty ? conteudo : Tooltip(message: dica, child: conteudo);
  }
}

/// As compras que formam o saldo do ativo, pela data em que foram feitas.
class _Compras extends StatelessWidget {
  const _Compras({super.key, required this.ativo});

  final PosicaoAtivo ativo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        for (final x in ativo.compras)
          Text(
            '${fmtData(x.dataCompra)} · ${x.restante} de ${x.qtdOriginal} × '
            '${brl(x.preco)}',
            style: TextStyle(fontSize: 12, color: c.textoSuave),
          ),
      ],
    );
  }
}
