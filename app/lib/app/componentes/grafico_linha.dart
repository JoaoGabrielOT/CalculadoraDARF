// Gráfico de linha por `CustomPainter` próprio (sem pacote de gráficos).

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../tema/cores_app.dart';

const _margem = 8.0;

/// Linha de [pontos] (x inteiro, por exemplo o instante; y o preço). O pai
/// precisa dar largura e altura limitadas. A cor vem da comparação do último
/// ponto com [referencia] (alta/queda do tema); sem referência, com o primeiro
/// ponto. Interativo: tocar, arrastar ou passar o mouse mostra o cursor
/// vertical e o ponto mais próximo, e avisa por [aoTocar] (null quando o mouse
/// sair).
class GraficoLinha extends StatefulWidget {
  const GraficoLinha({
    super.key,
    required this.pontos,
    this.referencia,
    this.cor,
    this.interativo = false,
    this.aoTocar,
  });

  final List<(int, double)> pontos;
  final double? referencia;
  final Color? cor;
  final bool interativo;
  final ValueChanged<(int, double)?>? aoTocar;

  @override
  State<GraficoLinha> createState() => _GraficoLinhaState();
}

class _GraficoLinhaState extends State<GraficoLinha> {
  (int, double)? _tocado;

  @override
  void didUpdateWidget(GraficoLinha antigo) {
    super.didUpdateWidget(antigo);
    // Outros pontos: o ponto tocado ficou obsoleto.
    if (_tocado != null && !listEquals(antigo.pontos, widget.pontos)) {
      _tocado = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.aoTocar?.call(null);
      });
    }
  }

  Color _cor(CoresApp c) {
    if (widget.cor != null) return widget.cor!;
    if (widget.pontos.isEmpty) return c.textoSuave;
    final ultimo = widget.pontos.last.$2;
    final ref = widget.referencia ?? widget.pontos.first.$2;
    if (ultimo > ref) return c.alta;
    if (ultimo < ref) return c.queda;
    return c.textoSuave;
  }

  void _em(double dx, double largura) {
    if (!widget.interativo || widget.pontos.isEmpty) return;
    final geo = _Geometria(widget.pontos, widget.referencia, Size(largura, 1));
    (int, double)? melhor;
    var menor = double.infinity;
    for (final p in widget.pontos) {
      final d = (geo.x(p.$1) - dx).abs();
      if (d < menor) {
        menor = d;
        melhor = p;
      }
    }
    setState(() => _tocado = melhor);
    widget.aoTocar?.call(melhor);
  }

  void _sair() {
    if (_tocado == null) return;
    setState(() => _tocado = null);
    widget.aoTocar?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return LayoutBuilder(
      builder: (context, caixa) {
        assert(
          caixa.hasBoundedHeight && caixa.hasBoundedWidth,
          'GraficoLinha precisa de largura e altura limitadas: envolva-o em '
          'um SizedBox com altura, em um Expanded ou em um AspectRatio '
          '(dentro de rolagem ou Column ele não tem tamanho próprio).',
        );
        final largura = caixa.maxWidth;
        final grafico = RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: PintorLinha(
              pontos: widget.pontos,
              referencia: widget.referencia,
              cor: _cor(c),
              guia: c.textoSuave,
              contorno: c.cartao,
              tocado: widget.interativo ? _tocado : null,
            ),
          ),
        );
        if (!widget.interativo) return grafico;
        return MouseRegion(
          onHover: (e) => _em(e.localPosition.dx, largura),
          onExit: (_) => _sair(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _em(d.localPosition.dx, largura),
            onHorizontalDragStart: (d) => _em(d.localPosition.dx, largura),
            onHorizontalDragUpdate: (d) => _em(d.localPosition.dx, largura),
            child: grafico,
          ),
        );
      },
    );
  }
}

/// Conversão de valores em coordenadas, a mesma para desenhar e para tocar.
class _Geometria {
  _Geometria(List<(int, double)> pontos, double? referencia, this.tamanho) {
    final xs = pontos.map((p) => p.$1);
    final ys = pontos.map((p) => p.$2);
    if (pontos.isEmpty) {
      minX = maxX = 0;
      minY = maxY = 0;
    } else {
      minX = xs.reduce((a, b) => a < b ? a : b);
      maxX = xs.reduce((a, b) => a > b ? a : b);
      minY = ys.reduce((a, b) => a < b ? a : b);
      maxY = ys.reduce((a, b) => a > b ? a : b);
    }
    if (referencia != null) {
      if (referencia < minY) minY = referencia;
      if (referencia > maxY) maxY = referencia;
    }
  }

  final Size tamanho;
  late int minX, maxX;
  late double minY, maxY;

  double x(int v) {
    final util = tamanho.width - 2 * _margem;
    if (maxX == minX) return tamanho.width / 2;
    return _margem + (v - minX) / (maxX - minX) * util;
  }

  double y(double v) {
    final util = tamanho.height - 2 * _margem;
    if (maxY == minY) return tamanho.height / 2;
    return tamanho.height - _margem - (v - minY) / (maxY - minY) * util;
  }
}

class PintorLinha extends CustomPainter {
  PintorLinha({
    required this.pontos,
    required this.referencia,
    required this.cor,
    required this.guia,
    required this.contorno,
    required this.tocado,
  });

  final List<(int, double)> pontos;
  final double? referencia;
  final Color cor;
  final Color guia;
  final Color contorno;
  final (int, double)? tocado;

  @override
  void paint(Canvas canvas, Size size) {
    if (pontos.isEmpty) return;
    final geo = _Geometria(pontos, referencia, size);

    if (referencia != null) {
      final y = geo.y(referencia!);
      final tracejado = Paint()
        ..color = guia.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (var x = _margem; x < size.width - _margem; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), tracejado);
      }
    }

    final linha = Path();
    for (final (i, p) in pontos.indexed) {
      final o = Offset(geo.x(p.$1), geo.y(p.$2));
      i == 0 ? linha.moveTo(o.dx, o.dy) : linha.lineTo(o.dx, o.dy);
    }
    if (pontos.length > 1) {
      final area = Path.from(linha)
        ..lineTo(geo.x(pontos.last.$1), size.height)
        ..lineTo(geo.x(pontos.first.$1), size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cor.withValues(alpha: .18), cor.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        linha,
        Paint()
          ..color = cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawCircle(
        Offset(geo.x(pontos.first.$1), geo.y(pontos.first.$2)),
        3,
        Paint()..color = cor,
      );
    }

    final t = tocado;
    if (t != null) {
      final o = Offset(geo.x(t.$1), geo.y(t.$2));
      canvas.drawLine(
        Offset(o.dx, 0),
        Offset(o.dx, size.height),
        Paint()
          ..color = guia
          ..strokeWidth = 1,
      );
      canvas.drawCircle(o, 5, Paint()..color = contorno);
      canvas.drawCircle(o, 3.5, Paint()..color = cor);
    }
  }

  @override
  bool shouldRepaint(PintorLinha antigo) =>
      antigo.pontos != pontos ||
      antigo.referencia != referencia ||
      antigo.cor != cor ||
      antigo.guia != guia ||
      antigo.contorno != contorno ||
      antigo.tocado != tocado;
}
