// Calculadora de preço-alvo: compra, quantidade e lucro líquido desejado dão
// o preço de venda; o preço pode ser editado antes de criar a venda
// automática (calculadora_darf.py:3491-3657; android/main.py:2442-2512).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../tema/cores_app.dart';
import 'controle_metas.dart';

class AbaCalculadora extends StatelessWidget {
  const AbaCalculadora({super.key});

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleMetas>();
    final c = CoresApp.de(context);
    final lotes = controle.visao?.lotes ?? const <LoteLivre>[];
    final sem = lotes.isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          const _Rotulo('ATIVO / COMPRA'),
          InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('meta-compra'),
                isExpanded: true,
                isDense: true,
                value: sem ? null : controle.loteId,
                disabledHint: const Text('Nenhuma compra em aberto'),
                onChanged: sem
                    ? null
                    : (id) => unawaited(controle.escolherLote(id)),
                items: [
                  for (final l in lotes)
                    DropdownMenuItem(
                      value: l.lote.id,
                      child: Text(
                        '${l.lote.ticker} · ${fmtData(l.lote.dataCompra)} · '
                        '${brl(l.lote.preco)} · ${l.livre} livres',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const _Rotulo('QUANTIDADE'),
          TextField(
            key: const ValueKey('meta-qtd'),
            controller: controle.qtd,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Ex.: 100',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => unawaited(controle.calcular()),
          ),
          const _Rotulo('LUCRO LÍQUIDO DESEJADO (R\$)'),
          TextField(
            key: const ValueKey('meta-lucro'),
            controller: controle.lucro,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Ex.: 1.000,00',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => unawaited(controle.calcular()),
          ),
          const SizedBox(height: 10),
          _Projecao(controle),
          const _Rotulo(
            'PREÇO-ALVO DA VENDA (R\$) · pode editar antes de salvar',
          ),
          TextField(
            key: const ValueKey('meta-preco'),
            controller: controle.preco,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Ex.: 21,78',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => unawaited(controle.projetarPreco()),
          ),
          if (controle.mensagem.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  controle.mensagem,
                  style: TextStyle(
                    fontSize: 12,
                    color: controle.mensagemOk ? c.alta : c.queda,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: controle.criando
                ? null
                : () => unawaited(controle.criar()),
            child: const Text('Criar venda automática com este preço'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Estimativa conservadora: sem isenção de R\$ 20 mil e sem '
              'prejuízos anteriores.',
              style: TextStyle(fontSize: 11, color: c.textoSuave),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      texto,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: CoresApp.de(context).textoSuave,
      ),
    ),
  );
}

/// As sete linhas da projeção e a nota do regime (py:3524-3534, 3583-3592).
class _Projecao extends StatelessWidget {
  const _Projecao(this.controle);

  final ControleMetas controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = controle.calculo;
    final p = controle.projecao;
    String nota = controle.notaVazia;
    if (r != null && p != null) {
      final regime = r.dayTrade ? 'Day trade (20%)' : 'Swing trade (15%)';
      final irrf = p.irrf != 0
          ? ' IRRF retido estimado: ${brl(p.irrf)} (abate da DARF).'
          : '';
      nota =
          '$regime · custos: taxas B3 ${brl(p.taxas)} + corretagem '
          '${brl(p.corretagem)}.$irrf';
    }
    return Cartao(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          _Linha('Lucro líquido desejado', r?.lucroDesejado),
          _Linha('Preço médio do lote', r?.precoMedio),
          _Linha('Custo estimado de venda', p?.custos),
          _Linha('Imposto estimado', p?.imposto),
          _Linha('Preço-alvo sugerido (por ação)', r?.preco),
          _Linha('Lucro bruto projetado', p?.bruto),
          _Linha(
            'Lucro líquido projetado',
            p?.lucroAposImposto,
            cor: p != null && p.lucroAposImposto < 0 ? c.queda : c.alta,
          ),
          if (nota.isNotEmpty)
            Text(nota, style: TextStyle(fontSize: 11, color: c.textoSuave)),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.titulo, this.valor, {this.cor});

  final String titulo;

  /// null = ainda sem cálculo ("—").
  final double? valor;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final v = valor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: 8,
      children: [
        Flexible(
          child: Text(
            titulo,
            style: TextStyle(fontSize: 12, color: c.textoSuave),
          ),
        ),
        Text(
          v == null ? '—' : brl(v),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: v == null ? null : cor,
          ),
        ),
      ],
    );
  }
}
