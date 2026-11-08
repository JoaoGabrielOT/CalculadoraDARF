// Cartão de um ativo nas sugestões: o resumo do cenário sempre à vista (com
// horizonte, fonte, data e hora) e, expandido, os três números separados
// (ponto de equilíbrio, meta financeira e cenário de mercado), a simulação de
// saída da posição e as compras com o botão de criar as metas.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../servicos/api.dart';
import '../../componentes/cartao.dart';
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
    final r = widget.resultado;
    final ticker = r.ativo.ticker;
    final campos = widget.controle.camposDe(ticker);
    return Cartao(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      // o ListTile do ExpansionTile pinta sobre o Material, não sobre o cartão
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('abrir-$ticker'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: _Resumo(r),
            children: [
              _Bloco('Ponto de equilíbrio', [_pontoEquilibrio(context, r)]),
              _Bloco('Meta financeira (simulação)', [
                if (r.posicao == null)
                  _nota(context, 'Sem posição em aberto.')
                else ...[
                  _Campo(
                    chave: 'lucro-$ticker',
                    rotulo: 'Lucro líquido de IR desejado (R\$)',
                    controlador: campos.lucro,
                    aoMudar: _digitou,
                  ),
                  ..._meta(context, r),
                ],
              ]),
              _Bloco('Cenário de mercado', _cenario(context, r)),
              if (r.posicao != null)
                _Bloco('Simulação de saída da posição', [
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: _Campo(
                          chave: 'qtd-$ticker',
                          rotulo: 'Quantidade',
                          controlador: campos.qtd,
                          aoMudar: _digitou,
                        ),
                      ),
                      Expanded(
                        child: _Campo(
                          chave: 'preco-$ticker',
                          rotulo: 'Saída (R\$)',
                          controlador: campos.preco,
                          aoMudar: _digitou,
                        ),
                      ),
                    ],
                  ),
                  ..._saidas(context, r),
                ]),
              if (r.posicao != null)
                _Bloco('Compras (gerencial)', [
                  for (final compra in r.posicao!.compras)
                    _LinhaCompra(
                      resultado: r,
                      compra: compra,
                      controle: widget.controle,
                    ),
                ]),
            ],
          ),
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

Widget _pontoEquilibrio(BuildContext context, ResultadoAtivo r) {
  final pe = r.pontoEquilibrio;
  if (pe == null) {
    return _nota(context, 'Indisponível (sem posição em aberto).');
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _par(context, 'Preço de venda que zera o custo:', '${brl(pe)} por ação'),
      _nota(
        context,
        'Custo médio das compras e taxa B3 da venda, no tick para cima.',
        tamanho: 11,
      ),
    ],
  );
}

List<Widget> _meta(BuildContext context, ResultadoAtivo r) {
  final c = CoresApp.de(context);
  final meta = r.meta;
  final avisos = r.cenario?.avisos ?? const <String>[];
  return [
    if (r.erroMeta != null) _nota(context, r.erroMeta!, cor: c.queda),
    if (meta != null) ...[
      _par(
        context,
        'Preço de venda para o lucro desejado:',
        '${brl(meta)} por ação',
      ),
      _nota(
        context,
        'Simulação sobre a posição inteira (${r.posicao!.qtd} un.); não é recomendação.',
        tamanho: 11,
      ),
    ],
    if (avisos.contains(textoMetaAcima))
      _nota(context, textoMetaAcima, cor: c.aviso, negrito: true),
  ];
}

List<Widget> _cenario(BuildContext context, ResultadoAtivo r) {
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
  final sufixo = 'por ação, sem taxas';
  return [
    Text(
      'Horizonte: ${textoHorizonte[cen.horizonte]}',
      style: const TextStyle(fontSize: 12),
    ),
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
    if (!cen.oportunidade) _SemOportunidade(motivo: cen.motivo),
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
        '${brl(s.resultado)} (${fmtPct(s.resultadoPct)})',
        cor: s.resultado >= 0 ? c.alta : c.queda,
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

/// Resumo à vista: ativo, posição, estado, alvo e stop (ou o motivo de não
/// haver oportunidade) e o horizonte com a fonte, a data e a hora.
class _Resumo extends StatelessWidget {
  const _Resumo(this.r);

  final ResultadoAtivo r;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = r.ativo;
    final cen = r.cenario;
    final p = r.posicao;
    final ultimaBarra = a.barras.isEmpty ? null : a.barras.last.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              a.ticker,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (p != null && p.qtd > 0)
              _nota(context, '${p.qtd} un. · custo médio ${brl(p.precoMedio!)}')
            else
              _nota(context, 'só no radar'),
            if (a.estado != EstadoDados.ok)
              Pilula(
                texto: switch (a.estado) {
                  EstadoDados.semDados => 'Sem dados',
                  EstadoDados.desatualizado => 'Desatualizado',
                  _ => 'Falha',
                },
                // fundo próprio: o do chip some no tema Terminal
                cor: switch (a.estado) {
                  EstadoDados.falha => c.queda,
                  EstadoDados.desatualizado => c.aviso,
                  _ => c.textoSuave,
                },
                fundo: Color.alphaBlend(
                  (switch (a.estado) {
                    EstadoDados.falha => c.queda,
                    EstadoDados.desatualizado => c.aviso,
                    _ => c.textoSuave,
                  }).withValues(alpha: .18),
                  c.cartao,
                ),
              ),
          ],
        ),
        if (a.estado == EstadoDados.falha || a.estado == EstadoDados.semDados)
          _nota(
            context,
            a.mensagem ?? 'Sem dados.',
            cor: a.estado == EstadoDados.falha ? c.queda : null,
          )
        else ...[
          if (a.estado == EstadoDados.desatualizado)
            _nota(
              context,
              'Dados desatualizados: ${ultimaBarra == null ? '' : 'última barra de ${fmtData(ultimaBarra)}'}'
              '${a.cotacao == null ? '' : '; cotação de ${_dataHora(a.cotacao!.hora)}'}.',
              cor: c.aviso,
            ),
          if (cen != null && cen.oportunidade && r.temCenario)
            Text(
              'Alvo ${brl(cen.alvo!)} · Stop ${brl(cen.stop!)} · R/R ${fmtDec(cen.rr!, 2)}',
              style: TextStyle(fontSize: 12, color: c.alta),
            )
          else
            _SemOportunidade(motivo: cen?.motivo),
          _nota(
            context,
            [
              'Horizonte: ${textoHorizonte[r.horizonte]}',
              'Yahoo',
              if (a.cotacao != null)
                'cotação ${_dataHora(a.cotacao!.hora)}'
              else if (ultimaBarra != null)
                'última barra ${fmtData(ultimaBarra)}',
            ].join(' · '),
            tamanho: 11,
          ),
        ],
      ],
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco(this.titulo, this.filhos);

  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
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
      ),
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
