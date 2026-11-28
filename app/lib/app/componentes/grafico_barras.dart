// Gráfico de barras verticais por `CustomPainter` próprio (sem pacote de
// gráficos): uma barra por valor, com o texto do valor e o rótulo embaixo.

import 'package:flutter/material.dart';

import '../tema/cores_app.dart';

/// Uma barra: [valor] define a altura, [texto] é o valor já formatado, [cor]
/// vem do tema (padrão: cinza do texto suave).
class BarraGrafico {
  const BarraGrafico(this.rotulo, this.valor, this.texto, {this.cor});

  final String rotulo;
  final double valor;
  final String texto;
  final Color? cor;
}

/// Barras lado a lado, todas na mesma escala (a maior ocupa [altura]). O pai
/// só precisa dar largura limitada.
class GraficoBarras extends StatelessWidget {
  const GraficoBarras({super.key, required this.barras, this.altura = 110});

  final List<BarraGrafico> barras;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        SizedBox(
          height: altura,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: PintorBarras(
                valores: [for (final b in barras) b.valor],
                cores: [for (final b in barras) b.cor ?? c.textoSuave],
                base: c.linha,
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in barras)
              Expanded(
                child: Column(
                  spacing: 1,
                  children: [
                    Text(
                      b.texto,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      b.rotulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textoSuave, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class PintorBarras extends CustomPainter {
  PintorBarras({
    required this.valores,
    required this.cores,
    required this.base,
  });

  final List<double> valores;
  final List<Color> cores;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;
    final maior = valores.reduce((a, b) => a > b ? a : b);
    final fatia = size.width / valores.length;
    final largura = fatia * .5;
    for (final (i, v) in valores.indexed) {
      final h = maior <= 0 || v <= 0 ? 0.0 : v / maior * (size.height - 2);
      final x = fatia * i + (fatia - largura) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - 1 - h, largura, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = cores[i],
      );
    }
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(PintorBarras antigo) =>
      antigo.valores != valores || antigo.cores != cores || antigo.base != base;
}
