// Textos e peças dos extremos (melhor/pior possível) das listas da Apuração.
// Análise complementar: não entra no resultado oficial, no imposto nem no DARF.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../tema/cores_app.dart';
import 'controle_apuracao.dart';

/// Aviso fixo dos cartões de extremos do PC.
const notaExtremos = 'Estimativa por compra; não altera o resultado fiscal.';

/// Como a coluna Resultado: `R$ 270,00`, `-R$ 50,00`; "Carregando…" ou
/// "Indisponível" sem valor.
String textoExtremo(AnaliseExtremos? a, double? valor) {
  if (a == null) return '—';
  if (a.carregando) return 'Carregando…';
  if (valor == null) return 'Indisponível';
  return brl(valor);
}

String _dm(String iso) => '${iso.substring(8)}/${iso.substring(5, 7)}';

/// `máx R$ 38,00 (14/10) · mín R$ 5,00 (21/10) · período: 05/10 a 28/10`;
/// vazio sem valores.
String referenciaExtremos(AnaliseExtremos a) {
  final desde = a.desde;
  final ate = a.ate;
  if (a.melhor == null || desde == null || ate == null) return '';
  if (a.variaPeriodo) {
    return 'período: a partir da compra de cada lote, até ${_dm(ate)}';
  }
  final e = a.extremos;
  if (e == null) return '';
  return 'máx ${brl(e.maximo.preco)} (${_dm(e.maximo.data)}) · '
      'mín ${brl(e.minimo.preco)} (${_dm(e.minimo.data)}) · '
      'período: ${_dm(desde)} a ${_dm(ate)}';
}

/// Só o negativo ganha cor, como na coluna Resultado.
Color? corExtremo(CoresApp c, double? v) =>
    v != null && v < -0.004 ? c.queda : null;

/// Um valor com o rótulo à esquerda.
class _Par extends StatelessWidget {
  const _Par(this.rotulo, this.analise, this.valor);

  final String rotulo;
  final AnaliseExtremos analise;
  final double? valor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(rotulo, style: TextStyle(fontSize: 12, color: c.textoSuave)),
        Text(
          textoExtremo(analise, valor),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: corExtremo(c, valor),
          ),
        ),
      ],
    );
  }
}

/// Duas linhas (rótulo à esquerda, valor à direita) e a referência embaixo,
/// para o cartão do celular.
class BlocoExtremos extends StatelessWidget {
  const BlocoExtremos({
    super.key,
    required this.analise,
    required this.rotuloMelhor,
    required this.rotuloPior,
  });

  final AnaliseExtremos analise;
  final String rotuloMelhor;
  final String rotuloPior;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    Widget linha(String rotulo, double? v) => Row(
      spacing: 8,
      children: [
        Expanded(
          child: Text(
            rotulo,
            style: TextStyle(fontSize: 12, color: c.textoSuave),
          ),
        ),
        Text(
          textoExtremo(analise, v),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: corExtremo(c, v),
          ),
        ),
      ],
    );
    final ref = referenciaExtremos(analise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        linha(rotuloMelhor, analise.melhor),
        linha(rotuloPior, analise.pior),
        if (ref.isNotEmpty)
          Text(ref, style: TextStyle(fontSize: 11, color: c.textoSuave)),
      ],
    );
  }
}

/// Um item do [CartaoExtremos]: [id] vira a Key `<prefixo>-<id>`.
class ItemExtremos {
  const ItemExtremos({
    required this.id,
    required this.titulo,
    required this.analise,
  });

  final String id;
  final String titulo;
  final AnaliseExtremos analise;
}

/// Cartão do PC logo abaixo de uma tabela: uma linha por item, na ordem e
/// com o filtro da tabela.
class CartaoExtremos extends StatelessWidget {
  const CartaoExtremos({
    super.key,
    required this.titulo,
    required this.prefixoItem,
    required this.itens,
    required this.rotuloMelhor,
    required this.rotuloPior,
  });

  final String titulo;
  final String prefixoItem;
  final List<ItemExtremos> itens;
  final String rotuloMelhor;
  final String rotuloPior;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Text(
            notaExtremos,
            style: TextStyle(fontSize: 11, color: c.textoSuave),
          ),
          for (final i in itens)
            Column(
              key: Key('$prefixoItem-${i.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i.titulo,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _Par(rotuloMelhor, i.analise, i.analise.melhor),
                    _Par(rotuloPior, i.analise, i.analise.pior),
                  ],
                ),
                if (referenciaExtremos(i.analise).isNotEmpty)
                  Text(
                    referenciaExtremos(i.analise),
                    style: TextStyle(fontSize: 11, color: c.textoSuave),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
