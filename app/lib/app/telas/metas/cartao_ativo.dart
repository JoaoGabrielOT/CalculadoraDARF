// Cartão de um ativo nas sugestões. Recolhido: ativo, quantidade e cotação,
// a barra stop · atual · alvo, os selos (alvo, stop, R/R) e uma linha
// discreta com horizonte, fonte, data e hora (nenhum alvo sem elas). Sem
// oportunidade, uma linha cinza. Aberto: as abas Mercado | Meta financeira |
// Equilíbrio, a simulação de saída, "Como calculei" e as compras com os
// botões de criar as metas.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../servicos/api.dart';
import '../../componentes/cartao.dart';
import '../../componentes/sinal.dart';
import '../../regras/apresentacao.dart';
import '../../tema/cores_app.dart';
import 'calculo_sugestao.dart';
import 'controle_metas.dart';

/// Espera entre teclas antes de refazer as contas.
const esperaDigitacao = Duration(milliseconds: 300);

String _dataHora(DataHora h) {
  final l = h.noFuso(fusoBrasilia);
  return '${fmtData(l.data)} ${l.horaMinuto}';
}

/// Rótulo em caixa alta e valor, na cor que o núcleo indicou.
class LinhaValor extends StatelessWidget {
  const LinhaValor(
    this.rotulo,
    this.valor,
    this.cor, {
    super.key,
    this.tamanho = 12,
  });

  final String rotulo;
  final String valor;
  final String? cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
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

enum _Aba { mercado, meta, equilibrio }

/// Há o que sugerir: oportunidade com alvo e stop.
bool _comOportunidade(ResultadoAtivo r) =>
    r.cenario != null && r.cenario!.oportunidade && r.temCenario;

/// Preço atual do ativo: a cotação ou, sem ela, a âncora do cenário.
double? _precoAtual(ResultadoAtivo r) =>
    r.ativo.cotacao?.preco ?? r.cenario?.ancora;

class CartaoAtivo extends StatefulWidget {
  const CartaoAtivo({
    super.key,
    required this.resultado,
    required this.controle,
  });

  final ResultadoAtivo resultado;
  final ControleMetas controle;

  @override
  State<CartaoAtivo> createState() => _CartaoAtivoState();
}

class _CartaoAtivoState extends State<CartaoAtivo> {
  Timer? _espera;
  bool _aberto = false;
  _Aba? _aba;
  final _compras = GlobalKey();

  @override
  void initState() {
    super.initState();
    // o ativo do foco (menu da Apuração) já abre, e a lista rola até ele
    final foco = widget.controle.foco;
    if (foco == null || foco.ticker != widget.resultado.ativo.ticker) return;
    _aberto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final alvo = foco.compras ? _compras.currentContext : null;
      unawaited(Scrollable.ensureVisible(alvo ?? context));
    });
  }

  void _digitou() {
    _espera?.cancel();
    _espera = Timer(esperaDigitacao, () {
      if (mounted) widget.controle.aplicarCampos(widget.resultado.ativo.ticker);
    });
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = widget.resultado;
    final ticker = r.ativo.ticker;
    final campos = widget.controle.camposDe(ticker);
    final oportunidade = _comOportunidade(r);
    final abas = [
      if (oportunidade) (_Aba.mercado, 'Mercado'),
      (_Aba.meta, 'Meta financeira'),
      (_Aba.equilibrio, 'Equilíbrio'),
    ];
    // a aba escolhida some se a oportunidade sumir (troca de horizonte)
    final aba = abas.any((a) => a.$1 == _aba) ? _aba! : abas.first.$1;
    final conteudoAba = switch (aba) {
      _Aba.mercado => _Mercado(r: r, campos: campos, aoMudar: _digitou),
      _Aba.meta => _Meta(r: r, campos: campos, aoMudar: _digitou),
      _Aba.equilibrio => _Equilibrio(r: r),
    };
    final aberto = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (!oportunidade && r.cenario != null)
          _SemOportunidade(motivo: r.cenario!.motivo),
        BotaoSegmentado<_Aba>(
          key: ValueKey('abas-$ticker'),
          opcoes: abas,
          valor: aba,
          aoMudar: (v) => setState(() => _aba = v),
        ),
        conteudoAba,
        _Expansivel(
          chave: 'como-$ticker',
          titulo: 'Como calculei',
          filhos: _comoCalculei(context, r),
        ),
        if (r.posicao != null)
          _Bloco('Compras (gerencial)', key: _compras, [
            for (final compra in r.posicao!.compras)
              _LinhaCompra(
                resultado: r,
                compra: compra,
                controle: widget.controle,
              ),
          ]),
      ],
    );
    return Cartao(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('abrir-$ticker'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _aberto = !_aberto),
              child: Row(
                children: [
                  Expanded(child: oportunidade ? _Resumo(r) : _LinhaCinza(r)),
                  Icon(
                    _aberto
                        ? Icons.expand_less
                        : (oportunidade
                              ? Icons.expand_more
                              : Icons.chevron_right),
                    color: c.textoSuave,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _aberto
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10, right: 4),
                      child: aberto,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _nota(
  BuildContext context,
  String texto, {
  Color? cor,
  double tamanho = 12,
  bool negrito = false,
}) {
  final c = CoresApp.de(context);
  return Text(
    texto,
    style: TextStyle(
      fontSize: tamanho,
      color: cor ?? c.textoSuave,
      fontWeight: negrito ? FontWeight.w600 : null,
    ),
  );
}

Widget _par(BuildContext context, String rotulo, String valor, {Color? cor}) {
  final c = CoresApp.de(context);
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Wrap(
      spacing: 6,
      children: [
        Text(rotulo, style: TextStyle(fontSize: 12, color: c.textoSuave)),
        Text(valor, style: TextStyle(fontSize: 12, color: cor)),
      ],
    ),
  );
}

/// "100 un." ou "só no radar".
String _textoPosicao(ResultadoAtivo r) {
  final p = r.posicao;
  return p != null && p.qtd > 0 ? '${p.qtd} un.' : 'só no radar';
}

/// Situação dos dados (falha, sem dados, desatualizado) num rótulo colorido.
Widget? _pilulaEstado(BuildContext context, SugestaoAtivo a) {
  if (a.estado == EstadoDados.ok) return null;
  final c = CoresApp.de(context);
  final cor = switch (a.estado) {
    EstadoDados.falha => c.queda,
    EstadoDados.desatualizado => c.aviso,
    _ => c.textoSuave,
  };
  return Pilula(
    texto: switch (a.estado) {
      EstadoDados.semDados => 'Sem dados',
      EstadoDados.desatualizado => 'Desatualizado',
      _ => 'Falha',
    },
    cor: cor,
    // fundo próprio: o do chip some no tema Terminal
    fundo: Color.alphaBlend(cor.withValues(alpha: .18), c.cartao),
  );
}

/// Aviso de dados antigos com a data da última barra e a hora da cotação.
Widget? _avisoDesatualizado(BuildContext context, SugestaoAtivo a) {
  if (a.estado != EstadoDados.desatualizado) return null;
  final ultimaBarra = a.barras.isEmpty ? null : a.barras.last.data;
  return _nota(
    context,
    'Dados desatualizados: ${ultimaBarra == null ? '' : 'última barra de ${fmtData(ultimaBarra)}'}'
    '${a.cotacao == null ? '' : '; cotação de ${_dataHora(a.cotacao!.hora)}'}.',
    cor: CoresApp.de(context).aviso,
  );
}

/// Horizonte, fonte e a hora da cotação (ou a data da última barra).
String _textoOrigem(ResultadoAtivo r) {
  final a = r.ativo;
  final ultimaBarra = a.barras.isEmpty ? null : a.barras.last.data;
  return [
    'Horizonte: ${textoHorizonte[r.horizonte]}',
    'Yahoo',
    if (a.cotacao != null)
      'cotação ${_dataHora(a.cotacao!.hora)}'
    else if (ultimaBarra != null)
      'última barra ${fmtData(ultimaBarra)}',
  ].join(' · ');
}

/// Resumo com oportunidade: ativo, barra, selos e a origem dos números.
class _Resumo extends StatelessWidget {
  const _Resumo(this.r);

  final ResultadoAtivo r;

  @override
  Widget build(BuildContext context) {
    final a = r.ativo;
    final cen = r.cenario!;
    final atual = _precoAtual(r);
    final pctAlvo = variacaoPct(atual, cen.alvo);
    final pctStop = variacaoPct(atual, cen.stop);
    final estado = _pilulaEstado(context, a);
    final aviso = _avisoDesatualizado(context, a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              a.ticker,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            _nota(
              context,
              [
                _textoPosicao(r),
                if (atual != null) 'cotação ${brl(atual)}',
              ].join(' · '),
            ),
            ?estado,
          ],
        ),
        ?aviso,
        _BarraAlvo(stop: cen.stop!, atual: atual, alvo: cen.alvo!),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Selo(
              texto: '${setaDe(sinalDe(pctAlvo))}Alvo ${pctCurto(pctAlvo)}',
              alta: _altaDe(pctAlvo),
            ),
            Selo(
              texto: '${setaDe(sinalDe(pctStop))}Stop ${pctCurto(pctStop)}',
              alta: _altaDe(pctStop),
            ),
            Selo(texto: 'R/R ${fmtDec(cen.rr!, 2)}'),
          ],
        ),
        _nota(context, _textoOrigem(r), tamanho: 11),
      ],
    );
  }
}

bool? _altaDe(double? v) => switch (sinalDe(v)) {
  Sinal.alta => true,
  Sinal.queda => false,
  Sinal.neutro => null,
};

/// Sem oportunidade, sem dados ou com falha: uma linha cinza com o motivo
/// curto.
class _LinhaCinza extends StatelessWidget {
  const _LinhaCinza(this.r);

  final ResultadoAtivo r;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = r.ativo;
    final semDados =
        a.estado == EstadoDados.falha || a.estado == EstadoDados.semDados;
    final estado = _pilulaEstado(context, a);
    final aviso = _avisoDesatualizado(context, a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              a.ticker,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.textoSuave,
              ),
            ),
            _nota(context, _textoPosicao(r)),
            ?estado,
            if (semDados)
              _nota(
                context,
                a.mensagem ?? 'Sem dados.',
                cor: a.estado == EstadoDados.falha ? c.queda : null,
              )
            else
              _nota(context, textoSemOportunidade),
          ],
        ),
        ?aviso,
      ],
    );
  }
}

/// Barra horizontal Stop ●━━◆━━● Alvo, com o marcador da cotação atual
/// proporcional entre os dois (limitado às pontas).
class _BarraAlvo extends StatelessWidget {
  const _BarraAlvo({
    required this.stop,
    required this.atual,
    required this.alvo,
  });

  final double stop;
  final double? atual;
  final double alvo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final pos = posicaoMarcador(stop: stop, atual: atual, alvo: alvo);
    Widget ponto(Color cor) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
    );
    return Semantics(
      label:
          'Stop ${brl(stop)}, cotação ${atual == null ? 'indisponível' : brl(atual!)}, '
          'alvo ${brl(alvo)}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            SizedBox(
              height: 14,
              child: LayoutBuilder(
                builder: (context, caixa) {
                  final w = caixa.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned(
                        left: 5,
                        right: 5,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [
                                c.queda.withValues(alpha: .55),
                                c.alta.withValues(alpha: .55),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(left: 0, child: ponto(c.queda)),
                      Positioned(right: 0, child: ponto(c.alta)),
                      if (pos != null)
                        Positioned(
                          key: const ValueKey('marcador-atual'),
                          left: 7 + pos * (w - 14) - 6,
                          child: Transform.rotate(
                            angle: 0.785398,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: c.texto,
                                border: Border.all(color: c.cartao, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Row(
              children: [
                Text(
                  'Stop ${brl(stop)}',
                  style: TextStyle(fontSize: 11, color: c.queda),
                ),
                const Spacer(),
                Text(
                  'Alvo ${brl(alvo)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: c.alta),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Número em destaque das abas: rótulo pequeno e valor.
class _Numero extends StatelessWidget {
  const _Numero(this.rotulo, this.valor, {this.cor});

  final String rotulo;
  final String valor;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return DecoratedBox(
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
            Text(rotulo, style: TextStyle(fontSize: 11, color: c.textoSuave)),
            Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grade de números: duas colunas, cada linha na altura do maior.
Widget _grade(List<Widget> itens) => Column(
  spacing: 8,
  children: [
    for (var i = 0; i < itens.length; i += 2)
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Expanded(child: itens[i]),
            Expanded(
              child: i + 1 < itens.length ? itens[i + 1] : const SizedBox(),
            ),
          ],
        ),
      ),
  ],
);

/// A saída de toda a posição a [preco] (o cenário "100%"), se houver.
CenarioSaida? _saidaTotal(ResultadoAtivo r, double? preco) {
  final cons = r.consolidado;
  if (cons == null || preco == null) return null;
  for (final s in cons.cenarios) {
    if (s.qtd == cons.qtd && s.preco == preco) return s;
  }
  return null;
}

String _textoSaida(CenarioSaida s) =>
    textoResultado(s.resultado, s.resultadoPct);

/// Aba Mercado: vender em, ganho no alvo, resultado no stop e prazo, mais a
/// simulação de saída.
class _Mercado extends StatelessWidget {
  const _Mercado({
    required this.r,
    required this.campos,
    required this.aoMudar,
  });

  final ResultadoAtivo r;
  final CamposAtivo campos;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cen = r.cenario!;
    final ticker = r.ativo.ticker;
    final faixa =
        cen.faixaMin != null &&
            cen.faixaMax != null &&
            cen.faixaMin != cen.faixaMax
        ? '${brl(cen.faixaMin!)} a ${brl(cen.faixaMax!)}'
        : brl(cen.alvo!);
    final noAlvo = _saidaTotal(r, cen.alvo);
    final noStop = _saidaTotal(r, cen.stop);
    // sem posição (radar): por ação, bruto
    final ganho = noAlvo != null
        ? _textoSaida(noAlvo)
        : '${textoResultado(cen.potencial, null)} por ação';
    final stop = noStop != null
        ? _textoSaida(noStop)
        : '${textoResultado(cen.risco == null ? null : -cen.risco!, null)} '
              'por ação';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        _grade([
          _Numero('Vender em', faixa),
          _Numero(
            'Ganho estimado no alvo',
            ganho,
            cor: c.doValor(noAlvo?.resultado ?? cen.potencial),
          ),
          _Numero(
            'No stop',
            stop,
            cor: c.doValor(
              noStop?.resultado ?? (cen.risco == null ? null : -cen.risco!),
            ),
          ),
          _Numero('Prazo', textoHorizonte[cen.horizonte] ?? '—'),
        ]),
        if (noAlvo != null)
          _nota(
            context,
            'Vendendo toda a posição; líquido de taxas B3 e IR estimado.',
            tamanho: 11,
          ),
        if (r.posicao != null)
          _Expansivel(
            chave: 'simular-$ticker',
            titulo: 'Simular saída da posição',
            filhos: [
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: _Campo(
                      chave: 'qtd-$ticker',
                      rotulo: 'Quantidade',
                      controlador: campos.qtd,
                      aoMudar: aoMudar,
                    ),
                  ),
                  Expanded(
                    child: _Campo(
                      chave: 'preco-$ticker',
                      rotulo: 'Saída (R\$)',
                      controlador: campos.preco,
                      aoMudar: aoMudar,
                    ),
                  ),
                ],
              ),
              ..._saidas(context, r),
            ],
          ),
      ],
    );
  }
}

/// Aba Meta financeira: o lucro desejado e o preço que o entrega.
class _Meta extends StatelessWidget {
  const _Meta({required this.r, required this.campos, required this.aoMudar});

  final ResultadoAtivo r;
  final CamposAtivo campos;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    if (r.posicao == null) return _nota(context, 'Sem posição em aberto.');
    final meta = r.meta;
    final avisos = r.cenario?.avisos ?? const <String>[];
    final naMeta = _saidaTotal(r, meta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        _Campo(
          chave: 'lucro-${r.ativo.ticker}',
          rotulo: 'Lucro líquido de IR desejado (R\$)',
          controlador: campos.lucro,
          aoMudar: aoMudar,
        ),
        if (r.erroMeta != null) _nota(context, r.erroMeta!, cor: c.queda),
        if (meta != null) ...[
          _grade([
            _Numero('Preço-alvo', '${brl(meta)} por ação'),
            if (naMeta != null)
              _Numero(
                '${naMeta.rotulo} (${naMeta.qtd} un.)',
                _textoSaida(naMeta),
                cor: c.doValor(naMeta.resultado),
              ),
          ]),
          _nota(
            context,
            'Simulação sobre a posição inteira (${r.posicao!.qtd} un.); não é recomendação.',
            tamanho: 11,
          ),
        ],
        if (avisos.contains(textoMetaAcima))
          _nota(context, textoMetaAcima, cor: c.aviso, negrito: true),
      ],
    );
  }
}

/// Aba Equilíbrio: o preço que zera o custo.
class _Equilibrio extends StatelessWidget {
  const _Equilibrio({required this.r});

  final ResultadoAtivo r;

  @override
  Widget build(BuildContext context) {
    final pe = r.pontoEquilibrio;
    final p = r.posicao;
    if (pe == null) {
      return _nota(context, 'Indisponível (sem posição em aberto).');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        _grade([
          _Numero('Preço que zera o custo', '${brl(pe)} por ação'),
          if (p?.precoMedio != null)
            _Numero('Custo médio', brl(p!.precoMedio!)),
        ]),
        _nota(
          context,
          'Preço de venda que zera o custo: custo médio das compras e taxa '
          'B3 da venda, no tick para cima.',
          tamanho: 11,
        ),
      ],
    );
  }
}

/// "› Como calculei": as peças do cenário, a liquidez, a origem dos dados e
/// os avisos.
List<Widget> _comoCalculei(BuildContext context, ResultadoAtivo r) {
  final c = CoresApp.de(context);
  final cen = r.cenario;
  if (cen == null) {
    return [
      _nota(
        context,
        r.ativo.mensagem ?? 'Sem dados para o cenário.',
        cor: r.ativo.estado == EstadoDados.falha ? c.queda : null,
      ),
    ];
  }
  const sufixo = 'por ação, sem taxas';
  return [
    _nota(context, _textoOrigem(r)),
    if (cen.ancora != null)
      _par(context, 'Âncora (${cen.rotuloAncora}):', brl(cen.ancora!)),
    if (cen.alvo != null)
      _par(context, 'Alvo (${cen.rotuloAlvo}):', brl(cen.alvo!)),
    if (cen.faixaMin != null &&
        cen.faixaMax != null &&
        cen.faixaMin != cen.faixaMax)
      _par(
        context,
        'Faixa do alvo:',
        '${brl(cen.faixaMin!)} a ${brl(cen.faixaMax!)}',
      ),
    if (cen.stop != null) _par(context, 'Stop:', brl(cen.stop!)),
    if (cen.potencial != null)
      _par(context, 'Potencial ($sufixo):', brl(cen.potencial!)),
    if (cen.risco != null) _par(context, 'Risco ($sufixo):', brl(cen.risco!)),
    if (cen.rr != null) _par(context, 'R/R:', fmtDec(cen.rr!, 2)),
    _par(
      context,
      'Volume financeiro médio (20 pregões):',
      cen.vfm == null ? 'indisponível' : 'R\$ ${fmtVolume(cen.vfm)}',
    ),
    if (cen.baseData != null)
      _par(context, 'Último pregão fechado usado:', fmtData(cen.baseData!)),
    for (final a in cen.avisos)
      if (a != textoMetaAcima)
        _nota(context, a, cor: c.aviso, tamanho: 12, negrito: true),
  ];
}

List<Widget> _saidas(BuildContext context, ResultadoAtivo r) {
  final cons = r.consolidado;
  if (cons == null || cons.cenarios.isEmpty) {
    return [_nota(context, 'Sem preço de saída para simular.')];
  }
  final c = CoresApp.de(context);
  return [
    _nota(
      context,
      'Líquido de taxas B3 e IR estimado; % sobre o custo das unidades.',
      tamanho: 11,
    ),
    for (final s in cons.cenarios)
      _par(
        context,
        '${s.rotulo} (${s.qtd} un. a ${brl(s.preco)}):',
        _textoSaida(s),
        cor: c.doValor(s.resultado),
      ),
  ];
}

class _SemOportunidade extends StatelessWidget {
  const _SemOportunidade({this.motivo});

  final String? motivo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          textoSemOportunidade,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: c.aviso,
          ),
        ),
        if (motivo != null) _nota(context, motivo!),
      ],
    );
  }
}

/// Seção recolhível "› título" dentro do cartão aberto.
class _Expansivel extends StatefulWidget {
  const _Expansivel({
    required this.chave,
    required this.titulo,
    required this.filhos,
  });

  final String chave;
  final String titulo;
  final List<Widget> filhos;

  @override
  State<_Expansivel> createState() => _ExpansivelState();
}

class _ExpansivelState extends State<_Expansivel> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey(widget.chave),
          onTap: () => setState(() => _aberto = !_aberto),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              spacing: 4,
              children: [
                Icon(
                  _aberto ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: c.textoSuave,
                ),
                Text(
                  widget.titulo,
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
          child: _aberto
              ? Padding(
                  padding: const EdgeInsets.only(left: 22, top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: widget.filhos,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco(this.titulo, this.filhos, {super.key});

  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: c.textoSuave,
          ),
        ),
        ...filhos,
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo({
    required this.chave,
    required this.rotulo,
    required this.controlador,
    required this.aoMudar,
  });

  final String chave;
  final String rotulo;
  final TextEditingController controlador;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey(chave),
      controller: controlador,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(labelText: rotulo, isDense: true),
      onChanged: (_) => aoMudar(),
    );
  }
}

class _LinhaCompra extends StatelessWidget {
  const _LinhaCompra({
    required this.resultado,
    required this.compra,
    required this.controle,
  });

  final ResultadoAtivo resultado;
  final CompraNaPosicao compra;
  final ControleMetas controle;

  @override
  Widget build(BuildContext context) {
    final cen = resultado.cenario;
    final pode =
        cen != null &&
        cen.oportunidade &&
        resultado.ativo.estado == EstadoDados.ok &&
        !controle.criandoSug;
    // o stop avulso só precisa de stop abaixo do preço atual e dados em dia
    final stop = cen?.stop;
    final preco = resultado.ativo.cotacao?.preco ?? cen?.ancora;
    final podeStop =
        stop != null &&
        resultado.comDados &&
        (preco == null || stop < preco) &&
        !controle.criandoSug;
    final movel = infoStopMovel(resultado, compra, ambiente.hoje()) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compra de ${fmtData(compra.dataCompra)} · ${compra.restante} un. a ${brl(compra.preco)} · '
            'custo gerencial ${brl(compra.restante * compra.preco)}',
            style: const TextStyle(fontSize: 12),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: pode
                      ? () => unawaited(
                          controle.criarMetasDoCenario(
                            context,
                            resultado,
                            compra,
                          ),
                        )
                      : null,
                  child: const Text('Criar meta de alvo e stop'),
                ),
                OutlinedButton(
                  onPressed: podeStop
                      ? () => unawaited(
                          controle.criarStopAvulso(context, resultado, compra),
                        )
                      : null,
                  child: const Text('Criar stop fixo'),
                ),
                if (resultado.horizonte == Horizonte.swing)
                  OutlinedButton(
                    onPressed: podeStop && movel
                        ? () => unawaited(
                            controle.criarStopAvulso(
                              context,
                              resultado,
                              compra,
                              movel: true,
                            ),
                          )
                        : null,
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
