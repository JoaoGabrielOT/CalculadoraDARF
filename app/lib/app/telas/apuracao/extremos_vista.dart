// Textos e peças dos extremos (melhor/pior possível) das listas da Apuração.
// Análise complementar: não entra no resultado oficial, no imposto nem no DARF.

import 'package:flutter/material.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/apresentacao.dart';
import '../../tema/cores_app.dart';
import 'controle_apuracao.dart';

/// Aviso fixo dos cartões de extremos do PC.
const notaExtremos = 'Estimativa por compra; não altera o resultado fiscal.';

/// Seta e valor como na coluna Resultado: `▲ R$ 270,00`, `▼ -R$ 50,00`;
/// "Carregando…" ou "Indisponível" sem valor.
String textoExtremo(AnaliseExtremos? a, double? valor) {
  if (a == null) return '—';
  if (a.carregando) return 'Carregando…';
  if (valor == null) return 'Indisponível';
  return '${setaDe(sinalDe(valor))}${brl(valor)}';
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

/// Verde no positivo, vermelho no negativo, cinza no zero (ou sem valor).
Color corExtremo(CoresApp c, double? v) => switch (sinalDe(v)) {
  Sinal.alta => c.alta,
  Sinal.queda => c.queda,
  Sinal.neutro => c.textoSuave,
};

String _minuscula(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Valor num selo arredondado, com o fundo translúcido da cor do sinal.
class _Selo extends StatelessWidget {
  const _Selo({required this.chave, required this.analise, this.valor});

  final String chave;
  final AnaliseExtremos analise;
  final double? valor;

  @override
  Widget build(BuildContext context) {
    final cor = corExtremo(CoresApp.de(context), valor);
    return Container(
      key: Key(chave),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        textoExtremo(analise, valor),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }
}

/// Faixa fina do pior ao melhor, em gradiente do vermelho ao verde (ou só a
/// parte que existe), com um marcador no resultado [real] (preso na ponta
/// quando cai fora da faixa).
class _Faixa extends StatelessWidget {
  const _Faixa({required this.melhor, required this.pior, this.real});

  final double melhor;
  final double pior;
  final double? real;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final List<Color> cores;
    if (pior >= 0) {
      cores = [c.alta.withValues(alpha: .35), c.alta];
    } else if (melhor <= 0) {
      cores = [c.queda, c.queda.withValues(alpha: .35)];
    } else {
      cores = [c.queda, c.alta];
    }
    final r = real;
    final largura = melhor - pior;
    final fracao = r == null
        ? null
        : (largura <= 0 ? .5 : ((r - pior) / largura).clamp(0.0, 1.0));
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, caixa) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                key: const Key('faixa-extremos'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: cores),
                ),
              ),
            ),
            if (fracao != null)
              Positioned(
                left: fracao * caixa.maxWidth - 6,
                top: -3,
                child: Container(
                  key: const Key('marcador-extremos'),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.texto,
                    border: Border.all(color: c.cartao, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dois selos (rótulo à esquerda, valor à direita), a faixa com o marcador do
/// resultado real, a legenda e a referência; serve ao cartão do celular e aos
/// mini-cartões do PC.
class BlocoExtremos extends StatelessWidget {
  const BlocoExtremos({
    super.key,
    required this.analise,
    required this.rotuloMelhor,
    required this.rotuloPior,
    this.real,
    this.legendaReal = 'Resultado real',
  });

  final AnaliseExtremos analise;
  final String rotuloMelhor;
  final String rotuloPior;

  /// Resultado real (líquido da venda, ou ganho/perda atual do lote); nulo
  /// quando não está disponível.
  final double? real;
  final String legendaReal;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    Widget linha(String rotulo, String chave, double? v) => Row(
      spacing: 8,
      children: [
        Expanded(
          child: Text(
            rotulo,
            style: TextStyle(fontSize: 12, color: c.textoSuave),
          ),
        ),
        _Selo(chave: chave, analise: analise, valor: v),
      ],
    );
    final melhor = analise.melhor;
    final pior = analise.pior;
    final tem = melhor != null && pior != null;
    final r = tem ? real : null;
    final ref = referenciaExtremos(analise);
    final resumo = tem
        ? '$rotuloMelhor ${brl(melhor)}, ${_minuscula(rotuloPior)} ${brl(pior)}'
              '${r == null ? '' : ', ${_minuscula(legendaReal)} ${brl(r)}'}'
        : '$rotuloMelhor e ${_minuscula(rotuloPior)}: '
              '${analise.carregando ? 'carregando' : 'indisponível'}';
    return Semantics(
      container: true,
      label: resumo,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          linha(rotuloMelhor, 'selo-melhor', melhor),
          linha(rotuloPior, 'selo-pior', pior),
          if (tem) ...[
            const SizedBox(height: 2),
            _Faixa(melhor: melhor, pior: pior, real: r),
            if (r != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$legendaReal: ${brl(r)}',
                  style: TextStyle(fontSize: 11, color: c.textoSuave),
                ),
              ),
          ],
          if (ref.isNotEmpty)
            Text(ref, style: TextStyle(fontSize: 11, color: c.textoSuave)),
        ],
      ),
    );
  }
}

/// Um item do [CartaoExtremos]: [id] vira a Key `<prefixo>-<id>`.
class ItemExtremos {
  const ItemExtremos({
    required this.id,
    required this.titulo,
    required this.analise,
    this.real,
  });

  final String id;
  final String titulo;
  final AnaliseExtremos analise;
  final double? real;
}

/// Cartão do PC logo abaixo de uma tabela: uma grade de mini-cartões (largura
/// fixa), na ordem e com o filtro da tabela.
class CartaoExtremos extends StatelessWidget {
  const CartaoExtremos({
    super.key,
    required this.titulo,
    required this.prefixoItem,
    required this.itens,
    required this.rotuloMelhor,
    required this.rotuloPior,
    required this.legendaReal,
  });

  static const larguraItem = 300.0;

  final String titulo;
  final String prefixoItem;
  final List<ItemExtremos> itens;
  final String rotuloMelhor;
  final String rotuloPior;
  final String legendaReal;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Cartao(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final i in itens)
                Container(
                  key: Key('$prefixoItem-${i.id}'),
                  width: larguraItem,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.fundo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.linha),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text(
                        i.titulo,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      BlocoExtremos(
                        analise: i.analise,
                        rotuloMelhor: rotuloMelhor,
                        rotuloPior: rotuloPior,
                        real: i.real,
                        legendaReal: legendaReal,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
