// Logo do ativo: iniciais enquanto carrega (ou sem logo), imagem quando chega.
// Os bytes vêm do isolate de serviços; a decodificação é do motor.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../nucleo/nucleo.dart';
import '../servicos/api.dart';
import '../tema/cores_app.dart';

/// Logos já pedidas, por ticker, para uma lista inteira não repetir o pedido.
class CacheLogos {
  final _futuros = <String, Future<ImagemBytes?>>{};
  final _prontos = <String, ImagemBytes?>{};

  /// Resposta já recebida (null também vale: ticker sem logo); `false` em
  /// [conhecido] quando ainda não chegou.
  (bool conhecido, ImagemBytes? imagem) pronto(String ticker) =>
      (_prontos.containsKey(ticker), _prontos[ticker]);

  Future<ImagemBytes?> obter(
    String ticker,
    Future<ImagemBytes?> Function() pedir,
  ) => _futuros.putIfAbsent(
    ticker,
    () => Future.sync(pedir).then<ImagemBytes?>(
      (v) => _prontos[ticker] = v,
      // Erro de rede ou pedido superado: fica nas iniciais.
      onError: (Object _) => _prontos[ticker] = null,
    ),
  );
}

/// Dá aos [LogoAtivo] abaixo um cache comum. Sem ele, cada logo tem o seu.
class EscopoLogos extends StatefulWidget {
  const EscopoLogos({super.key, required this.child});

  final Widget child;

  static CacheLogos? cacheDe(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_CacheDoEscopo>()?.cache;

  @override
  State<EscopoLogos> createState() => _EscopoLogosState();
}

class _EscopoLogosState extends State<EscopoLogos> {
  final _cache = CacheLogos();

  @override
  Widget build(BuildContext context) =>
      _CacheDoEscopo(cache: _cache, child: widget.child);
}

class _CacheDoEscopo extends InheritedWidget {
  const _CacheDoEscopo({required this.cache, required super.child});

  final CacheLogos cache;

  @override
  bool updateShouldNotify(_CacheDoEscopo antigo) => cache != antigo.cache;
}

class LogoAtivo extends StatefulWidget {
  const LogoAtivo({super.key, required this.ticker, this.tamanho = 34});

  final String ticker;
  final double tamanho;

  @override
  State<LogoAtivo> createState() => _LogoAtivoState();
}

class _LogoAtivoState extends State<LogoAtivo> {
  late CacheLogos _cache;
  ImagemBytes? _imagem;

  @override
  void initState() {
    super.initState();
    _cache = EscopoLogos.cacheDe(context) ?? CacheLogos();
    _carregar();
  }

  @override
  void didUpdateWidget(LogoAtivo antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.ticker != widget.ticker) _carregar();
  }

  void _carregar() {
    final ticker = widget.ticker;
    final (conhecido, imagem) = _cache.pronto(ticker);
    _imagem = imagem;
    if (conhecido) return;
    final servicos = Provider.of<ServicosApp>(context, listen: false);
    _cache.obter(ticker, () => servicos.logo(ticker)).then((r) {
      if (mounted && widget.ticker == ticker) setState(() => _imagem = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final t = widget.tamanho;
    final iniciaisTexto = Center(
      child: Text(
        iniciais(widget.ticker),
        maxLines: 1,
        style: TextStyle(
          color: c.textoSuave,
          fontSize: t * 0.28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final imagem = _imagem;
    final Widget conteudo;
    if (imagem == null) {
      conteudo = iniciaisTexto;
    } else if (imagem.svg) {
      conteudo = SvgPicture.memory(
        imagem.bytes,
        width: t,
        height: t,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => iniciaisTexto,
      );
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      conteudo = Image.memory(
        imagem.bytes,
        width: t,
        height: t,
        fit: BoxFit.contain,
        cacheWidth: (t * dpr).round(),
        filterQuality: ui.FilterQuality.medium,
        errorBuilder: (_, _, _) => iniciaisTexto,
      );
    }
    return Semantics(
      label: 'Logo de ${widget.ticker}',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: t,
        height: t,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.logoFundo,
          borderRadius: BorderRadius.circular(t * 0.25),
        ),
        child: conteudo,
      ),
    );
  }
}
