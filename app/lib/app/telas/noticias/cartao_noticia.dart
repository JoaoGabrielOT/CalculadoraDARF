// Cartão de uma matéria: no PC uma mini página com foto, fonte, título, resumo,
// ativos e temas (calculadora_darf.py:1035-1105); no celular, o cartão com o
// logo do ativo (android/main.py:1932-1947). As imagens vêm como bytes e só
// são pedidas quando o cartão é construído.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/logo_ativo.dart';
import '../../tema/cores_app.dart';
import 'controle_noticias.dart';
import 'mural.dart';

class CartaoNoticia extends StatefulWidget {
  const CartaoNoticia({
    super.key,
    required this.item,
    required this.estilo,
    this.compacto = false,
  });

  final Noticia item;
  final EstiloNoticia estilo;

  /// Layout do celular (sem foto).
  final bool compacto;

  @override
  State<CartaoNoticia> createState() => _CartaoNoticiaState();
}

class _CartaoNoticiaState extends State<CartaoNoticia> {
  bool _realce = false;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final controle = context.watch<ControleNoticias>();
    final item = widget.item;
    final det = controle.detalhe(item);
    final nova = controle.ehNova(item);
    final borda = c.cartaoBorda.a == 0 ? c.linha : c.cartaoBorda;
    return Semantics(
      link: true,
      child: Material(
        key: Key('cartao-noticia-${item.id}'),
        color: c.cartao,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _realce ? c.destaque : borda),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => controle.abrir(item, expandido: !widget.compacto),
          onHover: (v) => setState(() => _realce = v),
          child: widget.compacto
              ? _Compacto(item: item, nova: nova)
              : _Expandido(
                  item: item,
                  det: det,
                  nova: nova,
                  estilo: widget.estilo,
                ),
        ),
      ),
    );
  }
}

// --- PC

class _Expandido extends StatelessWidget {
  const _Expandido({
    required this.item,
    required this.det,
    required this.nova,
    required this.estilo,
  });

  final Noticia item;
  final DetalheNoticia? det;
  final bool nova;
  final EstiloNoticia estilo;

  @override
  Widget build(BuildContext context) {
    final img = det?.img ?? '';
    return LayoutBuilder(
      builder: (context, caixa) {
        final largura = caixa.maxWidth;
        if (estilo == EstiloNoticia.destaque) {
          final larguraImg = img.isEmpty
              ? 0.0
              : (largura * 0.48).floorToDouble();
          final alturaImg = math.max(
            260.0,
            math.min(360.0, (larguraImg * 0.56).floorToDouble()),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (larguraImg > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                  child: _Foto(
                    id: item.id,
                    url: img,
                    largura: larguraImg,
                    altura: alturaImg,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _Conteudo(
                    item: item,
                    det: det,
                    nova: nova,
                    estilo: estilo,
                  ),
                ),
              ),
            ],
          );
        }
        final proporcao = img.isEmpty ? 0.0 : estilo.proporcao;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (proporcao > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _Foto(
                  id: item.id,
                  url: img,
                  largura: largura - 16,
                  altura: ((largura - 16) * proporcao).floorToDouble(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: _Conteudo(
                item: item,
                det: det,
                nova: nova,
                estilo: estilo,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Foto da matéria: espaço neutro até chegar, e para sempre se não vier.
class _Foto extends StatefulWidget {
  const _Foto({
    required this.id,
    required this.url,
    required this.largura,
    required this.altura,
  });

  final String id;
  final String url;
  final double largura;
  final double altura;

  @override
  State<_Foto> createState() => _FotoState();
}

class _FotoState extends State<_Foto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(_Foto antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.url != widget.url) {
      _bytes = null;
      _carregar();
    }
  }

  void _carregar() {
    final url = widget.url;
    context.read<ControleNoticias>().imagem(url).then((r) {
      if (mounted && widget.url == url) setState(() => _bytes = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final vazio = SizedBox(
      key: Key('foto-vazia-${widget.id}'),
      width: widget.largura,
      height: widget.altura,
      child: DecoratedBox(decoration: BoxDecoration(color: c.logoFundo)),
    );
    final bytes = _bytes;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: bytes == null
            ? vazio
            : Image.memory(
                bytes,
                key: Key('imagem-noticia-${widget.id}'),
                width: widget.largura,
                height: widget.altura,
                fit: BoxFit.cover,
                // reduz já na decodificação; a qualidade média suaviza o
                // serrilhado das imagens reduzidas
                cacheWidth:
                    (widget.largura * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                filterQuality: ui.FilterQuality.medium,
                errorBuilder: (_, _, _) => vazio,
              ),
      ),
    );
  }
}

/// Favicon da fonte (16 px): some se não chegar.
class _Favicon extends StatefulWidget {
  const _Favicon(this.item);

  final Noticia item;

  @override
  State<_Favicon> createState() => _FaviconState();
}

class _FaviconState extends State<_Favicon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    context.read<ControleNoticias>().favicon(widget.item).then((r) {
      if (mounted) setState(() => _bytes = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox(width: 16, height: 16);
    return ExcludeSemantics(
      child: Image.memory(
        bytes,
        key: Key('favicon-${widget.item.id}'),
        width: 16,
        height: 16,
        filterQuality: ui.FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox(width: 16, height: 16),
      ),
    );
  }
}

class _SeloNova extends StatelessWidget {
  const _SeloNova();

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Pilula(
      texto: 'Nova',
      fundo: c.chipAtivoFundo,
      cor: c.chipAtivoTexto,
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({
    required this.item,
    required this.det,
    required this.nova,
    required this.estilo,
  });

  final Noticia item;
  final DetalheNoticia? det;
  final bool nova;
  final EstiloNoticia estilo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final destaque = estilo == EstiloNoticia.destaque;
    final link = (det?.url ?? '').isNotEmpty ? det!.url : item.link;
    final resumo = cortar(det?.resumo, estilo.limite);
    final mostrarResumo =
        resumo.isNotEmpty && chaveTitulo(resumo) != chaveTitulo(item.titulo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Favicon(item),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.fonte.isNotEmpty ? item.fonte : dominio(link),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '  ·  ${tempoRelativo(item.data)}',
              maxLines: 1,
              style: TextStyle(color: c.textoSuave, fontSize: 12),
            ),
            if (nova) ...[const Spacer(), const _SeloNova()],
          ],
        ),
        SizedBox(height: destaque ? 10 : 8),
        Text(
          item.titulo,
          style: TextStyle(fontSize: estilo.fonte, fontWeight: FontWeight.bold),
        ),
        if (mostrarResumo) ...[
          const SizedBox(height: 8),
          Text(
            resumo,
            style: TextStyle(color: c.textoSuave, fontSize: destaque ? 13 : 12),
          ),
        ],
        SizedBox(height: destaque ? 14 : 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final t in item.tickers.take(4)) _ChipAtivo(t),
            for (final t in item.temas.take(2)) Pilula(texto: t),
          ],
        ),
      ],
    );
  }
}

class _ChipAtivo extends StatelessWidget {
  const _ChipAtivo(this.ticker);

  final String ticker;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.logoFundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            LogoAtivo(ticker: ticker, tamanho: 20),
            Text(
              ticker,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// --- celular

class _Compacto extends StatelessWidget {
  const _Compacto({required this.item, required this.nova});

  final Noticia item;
  final bool nova;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final meta = [
      for (final x in [
        item.fonte,
        tempoRelativo(item.data),
        item.tickers.join(', '),
      ])
        if (x.isNotEmpty) x,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          if (item.tickers.isNotEmpty)
            LogoAtivo(ticker: item.tickers.first, tamanho: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(
                  item.titulo,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  spacing: 6,
                  children: [
                    _Favicon(item),
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textoSuave, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                if (nova || item.temas.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (nova) const _SeloNova(),
                      for (final t in item.temas.take(2)) Pilula(texto: t),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
