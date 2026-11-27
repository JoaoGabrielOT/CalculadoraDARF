// Peças do campo Especialistas do cartão quando o relatório traz o guia para
// leigos: caixa do guia, comparação preço × alvo médio e sub-cartão por casa.
// Cada peça tem a chave no próprio widget, dentro de um invólucro sem chave:
// tickers repetidos não viram chaves duplicadas entre irmãos.

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/destaques.dart';
import '../../../nucleo/relatorios/guia.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../tema/cores_app.dart';
import 'paleta_relatorio.dart';

/// Explicação do preço-alvo no topo da aba.
const textoExplicacaoPrecoAlvo =
    'Preço-alvo é quanto a casa acha que a ação vai valer no prazo indicado '
    '(em geral 12 meses). Não é preço para comprar nem para vender.';

class ExplicacaoPrecoAlvo extends StatelessWidget {
  const ExplicacaoPrecoAlvo({super.key});

  @override
  Widget build(BuildContext context) => caixaRelatorio(
    key: const Key('explicacao-preco-alvo'),
    fundo: PaletaRelatorio.azulFundo,
    child: const Text(
      textoExplicacaoPrecoAlvo,
      style: TextStyle(color: PaletaRelatorio.azulTexto, fontSize: 13),
    ),
  );
}

class GuiaAtivo extends StatelessWidget {
  const GuiaAtivo(this.ticker, this.texto, {super.key});

  final String ticker;
  final String texto;

  @override
  Widget build(BuildContext context) => caixaRelatorio(
    key: Key('guia-$ticker'),
    fundo: PaletaRelatorio.azulFundo,
    child: Text(
      texto,
      style: const TextStyle(
        color: PaletaRelatorio.azulTexto,
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// "Último preço" | "Alvo médio" com o potencial em selo, e a faixa embaixo.
/// [precoUltimo] é o texto do preço do ativo, usado se faltar a referência.
class ComparacaoAlvo extends StatelessWidget {
  const ComparacaoAlvo(this.ticker, this.esp, this.precoUltimo, {super.key});

  final String ticker;
  final Especialistas esp;
  final String precoUltimo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final min = esp.alvoMin, max = esp.alvoMax;
    final faixa = min == null || max == null
        ? null
        : (min == max
              ? 'Faixa dos alvos: $min'
              : 'Faixa dos alvos: $min a $max');
    final potencial = esp.potencialMedio;
    Widget coluna(String rotulo, List<Widget> filhos) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 3,
        children: [
          Text(
            rotulo,
            style: TextStyle(
              color: c.textoSuave,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          ...filhos,
        ],
      ),
    );
    const valor = TextStyle(fontSize: 15, fontWeight: FontWeight.bold);
    return Column(
      key: Key('comparacao-$ticker'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            coluna('Último preço', [
              Text(esp.precoReferencia ?? precoUltimo, style: valor),
            ]),
            coluna('Alvo médio', [
              Text(esp.alvoMedio!, style: valor),
              if (potencial != null) _SeloPotencial(potencial),
            ]),
          ],
        ),
        if (faixa != null)
          Text(faixa, style: TextStyle(color: c.textoSuave, fontSize: 12)),
      ],
    );
  }
}

class _SeloPotencial extends StatelessWidget {
  const _SeloPotencial(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = texto.trim();
    final leitura = t.startsWith('+')
        ? Leitura.positiva
        : (t.startsWith('-') || t.startsWith('−')
              ? Leitura.negativa
              : Leitura.neutra);
    return Align(
      alignment: Alignment.centerLeft,
      child: SeloLeitura(leitura, texto: texto),
    );
  }
}

/// Item com `fraseGuia` ou `motivo` ganha sub-cartão.
bool itemComGuia(ItemEspecialista i) => i.fraseGuia != null || i.motivo != null;

class CasaEspecialista extends StatelessWidget {
  const CasaEspecialista(
    this.ticker,
    this.indice,
    this.item, {
    super.key,
    required this.aoAbrirLink,
  });

  final String ticker;
  final int indice;
  final ItemEspecialista item;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final i = item;
    final voto = votoDoItem(i);
    final frase = i.fraseGuia == null
        ? null
        : fraseSemMotivo(i.fraseGuia!, i.motivo);
    // Sem a frase do guia, a recomendação, o alvo e o potencial da linha antiga.
    final linhaAntiga = i.fraseGuia != null
        ? ''
        : juntar([
            i.recomendacao,
            if (i.precoAlvo case final p?) 'alvo $p',
            i.potencial,
          ]);
    return DecoratedBox(
      key: Key('casa-$ticker-$indice'),
      decoration: BoxDecoration(
        border: Border.all(color: c.cartaoBorda),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (voto != null) _seloVoto(voto),
                if (i.casa case final casa?)
                  Text(
                    casa,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (i.data case final d?)
                  Text(
                    dataCurta(d),
                    style: TextStyle(color: c.textoSuave, fontSize: 12),
                  ),
              ],
            ),
            if (linhaAntiga.isNotEmpty)
              Text(
                linhaAntiga,
                style: TextStyle(color: c.textoSuave, fontSize: 12),
              ),
            if (frase != null && frase.isNotEmpty)
              Text(frase, style: const TextStyle(fontSize: 13, height: 1.35)),
            if (i.motivo case final m?)
              Text(
                'Motivo: $m',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontStyle: FontStyle.italic,
                  color: c.textoSuave,
                ),
              ),
            if (linkSeguro(i.url) != null)
              LinkRelatorio(
                texto: 'Ver fonte',
                url: i.url,
                aoAbrir: aoAbrirLink,
              ),
          ],
        ),
      ),
    );
  }
}

Widget _seloVoto(Consenso v) => switch (v) {
  Consenso.compra => const SeloLeitura(Leitura.positiva, texto: 'Compra'),
  Consenso.venda => const SeloLeitura(Leitura.negativa, texto: 'Venda'),
  Consenso.neutra => const SeloLeitura(Leitura.neutra, texto: 'Manter'),
  _ => const SeloLeitura(Leitura.neutra, texto: 'Sem classificação'),
};
