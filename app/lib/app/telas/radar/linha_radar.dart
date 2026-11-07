// Um ativo do radar: linha de tabela no PC (calculadora_darf.py:796-937) e
// cartão no celular (android/main.py:1801-1867). A linha só formata o que o
// serviço entregou; sem cotação mostra "—", e com erro, o texto do erro.

import 'package:flutter/material.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/grafico_linha.dart';
import '../../componentes/logo_ativo.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/temas.dart';

/// Largura da alça de arrastar na linha do PC.
const larguraAlcaRadar = 30.0;

/// Colunas da tabela do PC: (título, peso, alinhamento); o peso 0 é largura
/// fixa ([larguraRisco], [larguraAcoes]).
const colunasRadar = <(String, int, TextAlign)>[
  ('ATIVO', 28, TextAlign.left),
  ('COTAÇÃO', 11, TextAlign.right),
  ('DIA', 18, TextAlign.right),
  ('MÉDIA 6 MESES', 14, TextAlign.right),
  ('ATR (14)', 10, TextAlign.right),
  ('ATR%', 9, TextAlign.right),
  ('RISCO', 0, TextAlign.center),
  ('', 0, TextAlign.right),
];
const larguraRisco = 170.0;
const larguraAcoes = 250.0;

/// Largura mínima da tabela; abaixo disso ela rola na horizontal.
const larguraMinimaTabelaRadar = 1040.0;

/// Mini-gráfico do dia.
const _miniLargura = 48.0;
const _miniAltura = 22.0;

/// O que fazer com um ativo; os callbacks que não existem na visão (amigo ou
/// meus dados) vêm nulos.
class AcoesRadar {
  const AcoesRadar({
    required this.aoAbrir,
    this.aoComprar,
    this.aoVender,
    this.aoRemover,
    this.aoImportar,
  });

  final VoidCallback aoAbrir;
  final VoidCallback? aoComprar;

  /// Nulo = ticker sem custódia: o botão fica desabilitado.
  final VoidCallback? aoVender;
  final VoidCallback? aoRemover;

  /// Só no radar de amigo; nulo quando o ativo já está no meu radar.
  final VoidCallback? aoImportar;
}

Color? _corHex(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Rótulo de risco com as cores da faixa (iguais nos três temas, como no
/// Python).
class SeloRisco extends StatelessWidget {
  const SeloRisco(this.risco, {super.key, this.texto});

  final Risco risco;

  /// Sobrescreve o rótulo (a legenda junta a faixa de ATR%).
  final String? texto;

  @override
  Widget build(BuildContext context) => Pilula(
    texto: texto ?? risco.rotulo,
    fundo: _corHex(risco.fundo),
    cor: _corHex(risco.texto),
  );
}

/// O que as colunas mostram, já formatado.
class _Textos {
  _Textos(this.item, this.cotacao) {
    final r = cotacao;
    if (r is CotacaoOk) dados = r.dados;
    if (r is CotacaoErro) erro = r.mensagem;
  }

  final ItemRadar item;
  final CotacaoRadar? cotacao;
  DadosAtivo? dados;
  String? erro;

  /// Nome da empresa (ou o erro, ou "Carregando…").
  String get nome {
    final e = erro;
    if (e != null) return e;
    final d = dados;
    if (d == null) return item.nome.isEmpty ? 'Carregando…' : item.nome;
    return d.nome.isNotEmpty ? d.nome : item.nome;
  }

  String get preco => _brl(dados?.preco);
  String get media => _brl(dados?.media6m);
  String get atr {
    final v = dados?.atr;
    return v == null || v == 0 ? '—' : brl(v);
  }

  String get atrPct => fmtPct(dados?.atrPct, sinal: false);

  double? get varPct => dados?.variacaoPct;

  /// Seta e percentual do dia.
  String get dia {
    final v = varPct;
    if (v == null) return '—';
    final seta = v > 0.0049 ? '▲ ' : (v < -0.0049 ? '▼ ' : '');
    return seta + fmtPct(v);
  }

  String get diaReais {
    final v = dados?.variacao;
    return v == null ? '' : (v > 0 ? '+' : '') + brl(v);
  }

  Risco? get risco => dados?.risco;

  static String _brl(double? v) => v == null ? '—' : brl(v);
}

Widget _mini(Grafico? g) => SizedBox(
  width: _miniLargura,
  height: _miniAltura,
  child: g == null || g.pontos.isEmpty
      ? null
      : GraficoLinha(pontos: g.pontos, referencia: g.referencia),
);

/// Ícone da alça de arrastar.
class _Alca extends StatelessWidget {
  const _Alca();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.drag_indicator, color: CoresApp.de(context).textoSuave);
}

/// Linha da tabela do PC. A [alca] (só nos meus dados) já traz o gesto de
/// arrastar ou o aviso; a linha só a posiciona.
class LinhaRadar extends StatelessWidget {
  const LinhaRadar({
    super.key,
    required this.item,
    required this.cotacao,
    required this.mini,
    required this.zebra,
    required this.acoes,
    this.alca,
    this.amigo = false,
  });

  final ItemRadar item;
  final CotacaoRadar? cotacao;
  final Grafico? mini;
  final bool zebra;
  final AcoesRadar acoes;

  /// Null no radar de amigo (sem alça).
  final Widget Function(Widget icone)? alca;
  final bool amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final x = _Textos(item, cotacao);
    final suave = TextStyle(color: c.textoSuave, fontSize: 11);
    final corDia = corVariacao(context, x.varPct);
    Widget celula(int i, Widget filho) {
      final (_, peso, alinhar) = colunasRadar[i];
      final alinhamento = switch (alinhar) {
        TextAlign.right => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      };
      final dentro = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(alignment: alinhamento, child: filho),
      );
      return switch (i) {
        6 => SizedBox(width: larguraRisco, child: dentro),
        7 => SizedBox(width: larguraAcoes, child: dentro),
        _ => Expanded(flex: peso, child: dentro),
      };
    }

    Widget valor(String t, {double tamanho = 13}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        t,
        style: TextStyle(fontSize: tamanho, fontWeight: FontWeight.bold),
      ),
    );
    final risco = x.risco;
    return Material(
      key: Key('linha-radar-${item.ticker}'),
      color: zebra ? c.linha.withValues(alpha: c.linha.a * .5) : c.cartao,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: acoes.aoAbrir,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                celula(
                  0,
                  Row(
                    children: [
                      if (alca != null)
                        SizedBox(
                          width: larguraAlcaRadar,
                          child: alca!(const _Alca()),
                        ),
                      LogoAtivo(ticker: item.ticker, tamanho: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.ticker,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              x.nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: x.erro == null
                                  ? suave
                                  : TextStyle(color: c.queda, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                celula(1, valor(x.preco, tamanho: 14)),
                celula(
                  2,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _mini(mini),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                x.dia,
                                style: TextStyle(
                                  color: corDia,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (x.diaReais.isNotEmpty)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  x.diaReais,
                                  style: TextStyle(color: corDia, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                celula(3, valor(x.media)),
                celula(4, valor(x.atr)),
                celula(5, valor(x.atrPct)),
                celula(6, risco == null ? const SizedBox() : SeloRisco(risco)),
                celula(7, _AcoesLinha(acoes: acoes, amigo: amigo)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Comprar, Vender e Remover (meus dados) ou "+  Meu radar" (amigo).
class _AcoesLinha extends StatelessWidget {
  const _AcoesLinha({required this.acoes, required this.amigo});

  final AcoesRadar acoes;
  final bool amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    const medidas = Size(72, 32);
    const margem = EdgeInsets.symmetric(horizontal: 8);
    // parte do estilo do tema (fonte do app), só menor
    final texto = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: 12, fontWeight: FontWeight.bold);
    if (amigo) {
      final importar = acoes.aoImportar;
      return importar == null
          ? OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(234, 32),
                textStyle: texto,
              ),
              child: const Text('✓  No meu radar'),
            )
          : FilledButton(
              onPressed: importar,
              style: FilledButton.styleFrom(
                minimumSize: const Size(234, 32),
                textStyle: texto,
              ),
              child: const Text('+  Meu radar'),
            );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        FilledButton(
          onPressed: acoes.aoComprar,
          style: FilledButton.styleFrom(
            minimumSize: medidas,
            padding: margem,
            textStyle: texto,
          ),
          child: const Text('Comprar'),
        ),
        OutlinedButton(
          onPressed: acoes.aoVender,
          style: OutlinedButton.styleFrom(
            minimumSize: medidas,
            padding: margem,
            textStyle: texto,
          ),
          child: const Text('Vender'),
        ),
        OutlinedButton(
          onPressed: acoes.aoRemover,
          style: OutlinedButton.styleFrom(
            minimumSize: medidas,
            padding: margem,
            textStyle: texto,
            foregroundColor: c.queda,
            side: BorderSide(color: c.queda),
          ),
          child: const Text('Remover'),
        ),
      ],
    );
  }
}

/// Cabeçalho da tabela do PC, alinhado às colunas das linhas.
class CabecalhoRadar extends StatelessWidget {
  const CabecalhoRadar({super.key, required this.comAlca});

  final bool comAlca;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final (i, (titulo, peso, alinhar)) in colunasRadar.indexed)
            () {
              final texto = Padding(
                padding: EdgeInsets.fromLTRB(
                  i == 0 && comAlca ? larguraAlcaRadar + 4 : 4,
                  0,
                  4,
                  0,
                ),
                child: Text(
                  titulo,
                  textAlign: alinhar,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textoSuave,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
              return switch (i) {
                6 => SizedBox(width: larguraRisco, child: texto),
                7 => SizedBox(width: larguraAcoes, child: texto),
                _ => Expanded(flex: peso, child: texto),
              };
            }(),
        ],
      ),
    );
  }
}

/// Cartão do celular: logo, ticker e nome, mini-gráfico, preço e selo do
/// dia; embaixo as estatísticas e as ações.
class CartaoRadar extends StatelessWidget {
  const CartaoRadar({
    super.key,
    required this.item,
    required this.cotacao,
    required this.mini,
    required this.acoes,
    this.comAlca = false,
    this.amigo = false,
  });

  final ItemRadar item;
  final CotacaoRadar? cotacao;
  final Grafico? mini;
  final AcoesRadar acoes;

  /// Mostra o ícone de arrastar (o gesto é do pai: toque e segure).
  final bool comAlca;
  final bool amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final x = _Textos(item, cotacao);
    final v = x.varPct;
    final risco = x.risco;
    Widget estatistica(String titulo, String valor) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: TextStyle(color: c.textoSuave, fontSize: 11)),
        Text(
          valor,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
    return Material(
      key: Key('cartao-radar-${item.ticker}'),
      color: c.cartao,
      borderRadius: BorderRadius.circular(c.raioCartao),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: acoes.aoAbrir,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Row(
                spacing: 10,
                children: [
                  LogoAtivo(ticker: item.ticker, tamanho: 36),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.ticker,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          x.nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: x.erro == null ? c.textoSuave : c.queda,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _mini(mini),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        x.preco,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (v != null)
                        Selo(
                          texto: x.dia,
                          alta: v > 0 ? true : (v < 0 ? false : null),
                        ),
                    ],
                  ),
                  if (comAlca) const _Alca(),
                ],
              ),
              if (x.dados != null)
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    estatistica('Média 6 meses', x.media),
                    estatistica('ATR (14)', x.atr),
                    estatistica('ATR%', x.atrPct),
                    if (risco != null) SeloRisco(risco),
                  ],
                ),
              _AcoesCartao(acoes: acoes, amigo: amigo),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcoesCartao extends StatelessWidget {
  const _AcoesCartao({required this.acoes, required this.amigo});

  final AcoesRadar acoes;
  final bool amigo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    if (amigo) {
      final importar = acoes.aoImportar;
      return importar == null
          ? OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.check),
              label: Text('Já está no seu radar'),
            )
          : FilledButton.icon(
              onPressed: importar,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Adicionar ao meu radar'),
            );
    }
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: acoes.aoComprar,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Comprar'),
              ),
              OutlinedButton.icon(
                onPressed: acoes.aoVender,
                icon: const Icon(Icons.sell),
                label: const Text('Vender'),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: acoes.aoRemover,
          icon: Icon(Icons.delete_outline, color: c.queda),
          tooltip: 'Remover do radar',
        ),
      ],
    );
  }
}
