// Vista do Relatório de Abertura, com as seções a–k do pedido na ordem e a
// paleta fixa do e-mail dentro dos cartões do tema. Os cartões dos ativos são
// preguiçosos (a quantidade muda a cada relatório). Campo de texto ausente: a
// linha some; valor ausente numa linha que precisa existir: "—".

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/destaques.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../componentes/cartao.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'cartao_ativo.dart';
import 'paleta_relatorio.dart';

class VistaRelatorio extends StatelessWidget {
  const VistaRelatorio({
    super.key,
    required this.relatorio,
    required this.aoAbrirLink,
    this.topo = const [],
  });

  final Relatorio relatorio;
  final void Function(Uri) aoAbrirLink;

  /// Mensagens da aba acima do relatório.
  final List<Widget> topo;

  @override
  Widget build(BuildContext context) {
    final r = relatorio;
    final margem = expandido(context) ? 24.0 : 12.0;
    Widget bloco(Widget w) => SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(margem, 0, margem, 16),
        child: w,
      ),
    );
    final edu = r.educacaoRisco;
    // Calculada uma vez: termômetro, destaques, tabela e cartões usam a mesma.
    final ativos = ordenarParaExibicao(r.ativos);
    final destaques = [
      for (final a in ativos)
        if (emDestaque(a)) a,
    ];
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        for (final w in topo) bloco(w),
        bloco(_Cabecalho(r)),
        if (r.avisosTopo.isNotEmpty || r.alertas.isNotEmpty) bloco(_Avisos(r)),
        bloco(const _Legenda()),
        if (r.indicadores.isNotEmpty) bloco(_Indicadores(r.indicadores)),
        if (r.resumo case final s?)
          bloco(
            _Secao(
              key: const Key('secao-e'),
              titulo: 'Resumo',
              child: Cartao(
                child: Text(
                  s,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ),
          ),
        bloco(_Termometro(r.termometro, ativos)),
        if (destaques.isNotEmpty) bloco(_Destaques(destaques)),
        if (r.ativos.isEmpty)
          bloco(
            Text(
              'Nenhum ativo neste relatório.',
              key: const Key('secao-g'),
              style: TextStyle(color: CoresApp.de(context).textoSuave),
            ),
          )
        else ...[
          bloco(_TabelaResumo(ativos)),
          // Cabeçalho de h; os cartões vêm preguiçosos logo abaixo.
          bloco(
            KeyedSubtree(key: const Key('secao-h'), child: _titulo('Ativos')),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: margem),
            sliver: SliverList.builder(
              itemCount: ativos.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CartaoAtivo(ativos[i], aoAbrirLink: aoAbrirLink),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
        ],
        if (edu != null &&
            [
              edu.titulo,
              edu.formula,
              edu.exemplo,
              edu.alerta,
            ].any((s) => s != null))
          bloco(_EducacaoRisco(edu)),
        if (r.aviso case final s?)
          bloco(
            caixaRelatorio(
              key: const Key('secao-j'),
              fundo: PaletaRelatorio.avisoFundo,
              child: Text(
                s,
                style: const TextStyle(
                  color: PaletaRelatorio.textoCaixa,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        if (r.fontesCenario.isNotEmpty)
          bloco(_FontesCenario(r.fontesCenario, aoAbrirLink)),
      ],
    );
  }
}

/// "22 ativos do Radar", "1 ativo da lista reserva"; sem quantidade, null.
String? _textoOrigem(OrigemAtivos? o) {
  final n = o?.quantidade;
  if (n == null) return null;
  final lista = o!.aba?.trim().toLowerCase() == 'reserva'
      ? 'da lista reserva'
      : 'do Radar';
  return '$n ${n == 1 ? 'ativo' : 'ativos'} $lista';
}

Widget _titulo(String s) =>
    Text(s, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));

/// Título curto da seção e o conteúdo embaixo; a [key] marca o início dela.
class _Secao extends StatelessWidget {
  const _Secao({super.key, required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [_titulo(titulo), child],
  );
}

// --- a) cabeçalho

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.r);

  final Relatorio r;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final data = r.dataExtenso ?? (r.data.isEmpty ? null : dataCurta(r.data));
    return Column(
      key: const Key('secao-a'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        if (r.titulo case final t?)
          Text(
            t,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        if (data != null)
          Text(
            data,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        if (_textoOrigem(r.origemAtivos) case final o?)
          Text(o, style: TextStyle(color: c.textoSuave, fontSize: 13)),
        if (r.versaoNova)
          Text(
            'Este relatório usa um formato mais novo que esta versão do app; '
            'algumas partes podem não aparecer.',
            key: const Key('versao-nova'),
            style: TextStyle(color: c.textoSuave, fontSize: 12),
          ),
      ],
    );
  }
}

// --- b) avisos e alertas

class _Avisos extends StatelessWidget {
  const _Avisos(this.r);

  final Relatorio r;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('secao-b'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final s in [...r.avisosTopo, ...r.alertas])
          caixaRelatorio(
            fundo: PaletaRelatorio.ambarFundo,
            child: Text(
              s,
              style: const TextStyle(
                color: PaletaRelatorio.textoCaixa,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

// --- c) legenda

class _Legenda extends StatelessWidget {
  const _Legenda();

  static const _textos = {
    Leitura.positiva:
        'Positiva: notícias e números do dia favoráveis à empresa.',
    Leitura.mista: 'Mista: sinais favoráveis e desfavoráveis ao mesmo tempo.',
    Leitura.neutra: 'Neutra: nada relevante para o preço no dia.',
    Leitura.negativa:
        'Negativa: notícias e números do dia desfavoráveis à empresa.',
  };

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Cartao(
      key: const Key('secao-c'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          for (final MapEntry(key: l, value: s) in _textos.entries)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _Amostra(l),
                ),
                Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
              ],
            ),
          const SizedBox(height: 2),
          Text(
            'A leitura resume as notícias e os dados do dia. Não é previsão '
            'de preço nem recomendação de compra ou venda.',
            style: TextStyle(color: c.textoSuave, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Quadradinho com o fundo e a borda da leitura.
class _Amostra extends StatelessWidget {
  const _Amostra(this.leitura);

  final Leitura leitura;

  @override
  Widget build(BuildContext context) {
    final (cor, fundo) = PaletaRelatorio.coresLeitura(leitura);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: fundo,
        border: Border.all(color: cor, width: 2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// --- d) indicadores

class _Indicadores extends StatelessWidget {
  const _Indicadores(this.indicadores);

  final List<Indicador> indicadores;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return _Secao(
      key: const Key('secao-d'),
      titulo: 'Indicadores',
      child: LayoutBuilder(
        builder: (context, caixa) {
          // Cartões de 240 só quando cabem pelo menos 2 lado a lado no espaço da
          // vista (não da janela); senão, a largura toda.
          final largura = caixa.maxWidth >= 2 * 240 + 12
              ? 240.0
              : caixa.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final ind in indicadores)
                SizedBox(
                  width: largura,
                  child: Cartao(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          ind.nome,
                          style: TextStyle(color: c.textoSuave, fontSize: 12),
                        ),
                        Text(
                          ind.valor,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (ind.variacao case final v?)
                          PilulaDirecao(v, ind.direcao),
                        if (ind.contexto case final s?)
                          Text(
                            s,
                            style: TextStyle(color: c.textoSuave, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// --- f) termômetro

class _Termometro extends StatelessWidget {
  const _Termometro(this.termometro, this.ativos);

  final Termometro termometro;

  /// Na ordem de exibição.
  final List<AtivoRelatorio> ativos;

  @override
  Widget build(BuildContext context) {
    return _Secao(
      key: const Key('secao-f'),
      titulo: 'Termômetro',
      child: Cartao(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            if (ativos.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final a in ativos) _SeloTermometro(a)],
              ),
            // Divergente das leituras: valem os números do JSON.
            Text(textoTermometro(termometro)),
          ],
        ),
      ),
    );
  }
}

/// A chave fica no selo, dentro deste invólucro sem chave: tickers repetidos
/// não viram chaves duplicadas entre irmãos.
class _SeloTermometro extends StatelessWidget {
  const _SeloTermometro(this.ativo);

  final AtivoRelatorio ativo;

  @override
  Widget build(BuildContext context) => SeloLeitura(
    ativo.leitura,
    key: Key('selo-termometro-${ativo.ticker}'),
    texto: ativo.ticker,
  );
}

// --- sinais mais favoráveis (entre f e g)

class _Destaques extends StatelessWidget {
  const _Destaques(this.ativos);

  final List<AtivoRelatorio> ativos;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return _Secao(
      key: const Key('secao-destaques'),
      titulo: 'Sinais mais favoráveis',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.cartao,
          borderRadius: BorderRadius.circular(c.raioCartao),
          border: Border.all(color: PaletaRelatorio.positivaTexto, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              for (final a in ativos) _LinhaDestaque(a),
              Text(
                'Leitura positiva e especialistas indicando compra. Não é '
                'previsão nem recomendação.',
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chave fica na coluna, dentro deste invólucro sem chave: tickers repetidos
/// não viram chaves duplicadas entre irmãos.
class _LinhaDestaque extends StatelessWidget {
  const _LinhaDestaque(this.ativo);

  final AtivoRelatorio ativo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = ativo;
    return Column(
      key: Key('destaque-${a.ticker}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          '★ ${a.ticker}',
          style: const TextStyle(
            color: PaletaRelatorio.positivaTexto,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (a.descricao case final d?)
          Text(d, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        Text(textoPreco(a.preco), style: const TextStyle(fontSize: 13)),
        if (a.especialistas.resumo case final r?)
          Text(r, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

// --- g) tabela-resumo

class _TabelaResumo extends StatelessWidget {
  const _TabelaResumo(this.ativos);

  /// Soma das colunas fixas; abaixo dela a tabela rola na horizontal.
  static const _larguraFixa = 632.0;

  final List<AtivoRelatorio> ativos;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    Widget celula(Widget w) =>
        Padding(padding: const EdgeInsets.fromLTRB(0, 8, 12, 8), child: w);
    final cabecalho = TextStyle(
      color: c.textoSuave,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    const texto = TextStyle(fontSize: 13);
    Table tabela({required bool flex}) => Table(
      columnWidths: flex
          ? const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1.6),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(3),
            }
          : const {
              0: FixedColumnWidth(92),
              1: FixedColumnWidth(160),
              2: FixedColumnWidth(100),
              3: FixedColumnWidth(_larguraFixa - 92 - 160 - 100),
            },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (final s in [
              'Ativo',
              'Último preço',
              'Leitura',
              'Especialistas',
            ])
              celula(Text(s, style: cabecalho)),
          ],
        ),
        for (final a in ativos)
          TableRow(
            decoration: BoxDecoration(
              color: emDestaque(a)
                  ? PaletaRelatorio.positivaTexto.withValues(alpha: 0.12)
                  : null,
              border: Border(top: BorderSide(color: c.linha)),
            ),
            children: [
              celula(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (emDestaque(a)) _EstrelaTabela(a.ticker),
                    Flexible(
                      child: Text(
                        a.ticker,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              celula(Text(textoPreco(a.preco), style: texto)),
              celula(
                Align(
                  alignment: Alignment.centerLeft,
                  child: SeloLeitura(a.leitura),
                ),
              ),
              celula(Text(a.especialistas.resumo ?? '—', style: texto)),
            ],
          ),
      ],
    );
    return _Secao(
      key: const Key('secao-g'),
      titulo: 'Resumo por ativo',
      child: Cartao(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        // O modo vem do espaço da vista, não da janela: no PC, com a barra
        // lateral e a coluna dos anteriores, ela pode ficar estreita.
        child: LayoutBuilder(
          builder: (context, caixa) => caixa.maxWidth >= _larguraFixa
              ? tabela(flex: true)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: tabela(flex: false),
                ),
        ),
      ),
    );
  }
}

/// A chave fica na estrela, dentro deste invólucro sem chave.
class _EstrelaTabela extends StatelessWidget {
  const _EstrelaTabela(this.ticker);

  final String ticker;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Text(
      '★',
      key: Key('estrela-tabela-$ticker'),
      style: const TextStyle(
        color: PaletaRelatorio.positivaTexto,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// --- i) educação de risco

class _EducacaoRisco extends StatelessWidget {
  const _EducacaoRisco(this.e);

  final EducacaoRisco e;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(color: PaletaRelatorio.azulTexto, fontSize: 13);
    return caixaRelatorio(
      key: const Key('secao-i'),
      fundo: PaletaRelatorio.azulFundo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          if (e.titulo case final s?)
            Text(
              s,
              style: estilo.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          if (e.formula case final s?)
            Text(s, style: estilo.copyWith(fontWeight: FontWeight.w600)),
          if (e.exemplo case final s?) Text(s, style: estilo),
          if (e.alerta case final s?)
            Text(
              s,
              style: estilo.copyWith(
                color: PaletaRelatorio.negativaTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// --- k) fontes do cenário

class _FontesCenario extends StatelessWidget {
  const _FontesCenario(this.fontes, this.aoAbrirLink);

  final List<Fonte> fontes;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) {
    return _Secao(
      key: const Key('secao-k'),
      titulo: 'Fontes do cenário',
      child: Wrap(
        spacing: 14,
        runSpacing: 2,
        children: [
          for (final f in fontes)
            LinkRelatorio(texto: f.nome, url: f.url, aoAbrir: aoAbrirLink),
        ],
      ),
    );
  }
}
