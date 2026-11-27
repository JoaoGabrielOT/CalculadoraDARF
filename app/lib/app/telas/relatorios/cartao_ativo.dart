// Cartão de um ativo do relatório (seção h): faixa lateral na cor da leitura,
// ticker, descrição, selo, explicação na caixa azul e os campos do dia. Campo
// ausente: a linha some.

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/destaques.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../componentes/cartao.dart';
import '../../tema/cores_app.dart';
import 'especialistas_ativo.dart';
import 'paleta_relatorio.dart';

class CartaoAtivo extends StatelessWidget {
  const CartaoAtivo(this.ativo, {super.key, required this.aoAbrirLink});

  final AtivoRelatorio ativo;
  final void Function(Uri) aoAbrirLink;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final a = ativo;
    final (corLeitura, _) = PaletaRelatorio.coresLeitura(a.leitura);
    final esp = a.especialistas;
    final preco = a.preco, exterior = a.precoExterior;
    final destaque = emDestaque(a);
    final placar = placarDe(esp);
    return Cartao(
      key: Key('cartao-${a.ticker}'),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(c.raioCartao),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: destaque
                ? Border(
                    left: BorderSide(color: corLeitura, width: 5),
                    top: BorderSide(
                      color: PaletaRelatorio.verdeDestaque(context),
                      width: 2,
                    ),
                    right: BorderSide(
                      color: PaletaRelatorio.verdeDestaque(context),
                      width: 2,
                    ),
                    bottom: BorderSide(
                      color: PaletaRelatorio.verdeDestaque(context),
                      width: 2,
                    ),
                  )
                : Border(left: BorderSide(color: corLeitura, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      a.ticker,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SeloLeitura(a.leitura),
                    if (destaque) _SeloDestaqueCartao(a.ticker),
                  ],
                ),
                if (a.descricao case final d?)
                  Text(d, style: TextStyle(color: c.textoSuave, fontSize: 13)),
                if (a.explicacao case final e?)
                  caixaRelatorio(
                    key: Key('explicacao-${a.ticker}'),
                    fundo: PaletaRelatorio.azulFundo,
                    child: Text(
                      e,
                      style: const TextStyle(
                        color: PaletaRelatorio.azulTexto,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (a.dono case final d?) _Campo('Quem é dono', [_texto(d)]),
                if (preco != null || exterior != null)
                  _Campo('Preço', [
                    if (preco != null)
                      _comVariacao(
                        textoPreco(preco),
                        preco.variacao,
                        preco.direcao,
                      ),
                    if (preco?.observacao case final o?)
                      Text(
                        o,
                        style: TextStyle(color: c.textoSuave, fontSize: 12),
                      ),
                    if (exterior != null)
                      _comVariacao(
                        textoPrecoExterior(exterior),
                        exterior.variacao,
                        exterior.direcao,
                      ),
                  ]),
                if (a.noticias case final n?) _Campo('Notícias', [_texto(n)]),
                if (esp.resumo != null ||
                    esp.guiaLeigo != null ||
                    esp.alvoMedio != null ||
                    esp.itens.isNotEmpty ||
                    placar.total > 0)
                  _Campo('Especialistas', [
                    if (esp.guiaLeigo case final g?)
                      GuiaAtivo(a.ticker, g)
                    else if (esp.resumo case final r?)
                      _texto(r),
                    if (esp.alvoMedio != null)
                      ComparacaoAlvo(a.ticker, esp, textoPreco(preco)),
                    if (placar.total > 0) _PlacarCartao(a.ticker, placar),
                    for (final (n, i) in esp.itens.indexed)
                      if (itemComGuia(i))
                        CasaEspecialista(
                          a.ticker,
                          n,
                          i,
                          aoAbrirLink: aoAbrirLink,
                        )
                      else if (_textoItem(i) case final t
                          when t.isNotEmpty || i.potencial != null)
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (t.isNotEmpty)
                              LinkRelatorio(
                                texto: t,
                                url: i.url,
                                aoAbrir: aoAbrirLink,
                              ),
                            if (i.potencial case final p?)
                              Text(
                                p,
                                style: TextStyle(
                                  color: c.textoSuave,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                  ]),
                if (a.riscos case final r?) _Campo('Riscos', [_texto(r)]),
                if (a.fontes.isNotEmpty)
                  _Campo('Fontes', [
                    Wrap(
                      spacing: 14,
                      runSpacing: 2,
                      children: [
                        for (final f in a.fontes)
                          LinkRelatorio(
                            texto: f.nome,
                            url: f.url,
                            aoAbrir: aoAbrirLink,
                          ),
                      ],
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A chave fica no selo, dentro deste invólucro sem chave: tickers repetidos
/// não viram chaves duplicadas entre irmãos.
class _SeloDestaqueCartao extends StatelessWidget {
  const _SeloDestaqueCartao(this.ticker);

  final String ticker;

  @override
  Widget build(BuildContext context) =>
      SeloDestaque(key: Key('selo-destaque-$ticker'));
}

class _PlacarCartao extends StatelessWidget {
  const _PlacarCartao(this.ticker, this.placar);

  final String ticker;
  final Placar placar;

  @override
  Widget build(BuildContext context) =>
      SelosPlacar(placar, key: Key('placar-$ticker'));
}

Widget _texto(String s) =>
    Text(s, style: const TextStyle(fontSize: 14, height: 1.35));

/// "BTG Pactual · venda · alvo R$ 40,00 · 11/11/2026"; partes ausentes somem.
/// Só com a URL, o texto é a própria URL.
String _textoItem(ItemEspecialista i) {
  final t = juntar([
    i.casa,
    i.recomendacao,
    if (i.precoAlvo case final p?) 'alvo $p',
    if (i.data case final d?) dataCurta(d),
  ]);
  return t.isEmpty ? i.url ?? '' : t;
}

Widget _comVariacao(String texto, String? variacao, Direcao direcao) => Wrap(
  spacing: 8,
  runSpacing: 4,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    _texto(texto),
    if (variacao != null) PilulaDirecao(variacao, direcao),
  ],
);

/// Rótulo pequeno e o conteúdo do campo embaixo.
class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.filhos);

  final String rotulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
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
    );
  }
}
