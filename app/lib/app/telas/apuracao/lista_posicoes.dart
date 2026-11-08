// Ativos comprados em "Posição em dd/mm/aaaa": por ativo, quantidade, custo e
// preço médio no fim do mês, com as compras expansíveis. Só leitura: ver uma
// posição não gera venda, resultado nem imposto. A cotação atual só aparece
// no corte de hoje, com fonte e hora; num mês passado não há cotação.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'controle_apuracao.dart';
import 'lista_lotes.dart';

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
                  cotacao: p!.corrente ? controle.cotacoes : null,
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
                  _Titulos(corrente: p!.corrente),
                  for (final a in itens)
                    _LinhaAtivo(
                      key: Key('ativo-${a.ticker}'),
                      ativo: a,
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

const _flex = [1.0, .7, .8, 1.3, 1.3];
const _flexAtual = [1.1, 1.5];

class _Titulos extends StatelessWidget {
  const _Titulos({required this.corrente});

  final bool corrente;

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
          t('TIPO', _flex[1], direita: false),
          t('QTD', _flex[2]),
          t('CUSTO', _flex[3]),
          t('PREÇO MÉDIO', _flex[4]),
          if (corrente) ...[
            t('ATUAL', _flexAtual[0]),
            t('VALOR DE MERCADO', _flexAtual[1]),
          ],
        ],
      ),
    );
  }
}

/// Um ativo da posição; toque abre as compras que formam o saldo.
class _LinhaAtivo extends StatefulWidget {
  const _LinhaAtivo({
    super.key,
    required this.ativo,
    required this.cotacao,
    required this.compacto,
  });

  final PosicaoAtivo ativo;

  /// Cotações atuais por ticker; nulo quando o corte não é hoje.
  final Map<String, CotacaoAtual?>? cotacao;
  final bool compacto;

  @override
  State<_LinhaAtivo> createState() => _LinhaAtivoState();
}

class _LinhaAtivoState extends State<_LinhaAtivo> {
  bool _aberto = false;

  String _textoAtual(CotacaoAtual? cot, bool tentou) =>
      cot != null ? brl(cot.preco) : (tentou ? '—' : '…');

  String _textoValor(CotacaoAtual? cot, bool tentou) => cot != null
      ? brl(arredondar(widget.ativo.qtd * cot.preco, 2))
      : (tentou ? '—' : '…');

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = widget.ativo;
    final cotacoes = widget.cotacao;
    final cot = cotacoes?[a.ticker];
    final tentou = cotacoes?.containsKey(a.ticker) ?? false;
    final medio = a.precoMedio;
    final custo = a.custoFiscal ?? a.custoGerencial;
    final compras = _Compras(ativo: a, key: Key('compras-${a.ticker}'));
    final seta = Icon(
      _aberto ? Icons.expand_less : Icons.expand_more,
      size: 20,
      color: c.textoSuave,
    );
    if (widget.compacto) {
      return Cartao(
        padding: const EdgeInsets.all(14),
        child: InkWell(
          onTap: () => setState(() => _aberto = !_aberto),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  const Spacer(),
                  Text(
                    '${a.qtd}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  seta,
                ],
              ),
              Text(
                'Custo ${brl(custo)} · Preço médio '
                '${medio == null ? '—' : brl(medio)}',
                style: TextStyle(fontSize: 12, color: c.textoSuave),
              ),
              if (a.custoPorCompra)
                Text(
                  textoCustoPorCompra,
                  style: TextStyle(fontSize: 11, color: c.textoSuave),
                ),
              if (cotacoes != null)
                Text(
                  'Atual: ${_textoAtual(cot, tentou)} · '
                  'Valor de mercado: ${_textoValor(cot, tentou)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (_aberto) compras,
            ],
          ),
        ),
      );
    }
    Widget col(String texto, double flex, {bool direita = true}) => Expanded(
      flex: (flex * 100).round(),
      child: Text(
        texto,
        textAlign: direita ? TextAlign.right : TextAlign.left,
        overflow: TextOverflow.ellipsis,
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
                col(a.ticker, _flex[0], direita: false),
                col(a.tipo, _flex[1], direita: false),
                col('${a.qtd}', _flex[2]),
                Expanded(
                  flex: (_flex[3] * 100).round(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(brl(custo)),
                      if (a.custoPorCompra)
                        Text(
                          textoCustoPorCompra,
                          style: TextStyle(fontSize: 10, color: c.textoSuave),
                        ),
                    ],
                  ),
                ),
                col(medio == null ? '—' : brl(medio), _flex[4]),
                if (cotacoes != null) ...[
                  col(_textoAtual(cot, tentou), _flexAtual[0]),
                  col(_textoValor(cot, tentou), _flexAtual[1]),
                ],
              ],
            ),
          ),
        ),
        if (_aberto)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 8, 10),
            child: compras,
          ),
      ],
    );
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
